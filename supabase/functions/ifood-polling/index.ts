import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const IFOOD_CLIENT_ID = Deno.env.get("IFOOD_CLIENT_ID") ?? "";
const IFOOD_CLIENT_SECRET = Deno.env.get("IFOOD_CLIENT_SECRET") ?? "";
const IFOOD_BASE_URL = "https://merchant-api.ifood.com.br";

// Regra de ouro desta integração (aprendida hoje, do jeito caro): nenhuma
// falha pode ser silenciosa. Toda chamada externa (auth, polling, detalhes
// de pedido, acknowledgment) passa por aqui em caso de erro — vira uma linha
// consultável em logs_acoes, nunca só um console.error perdido.
async function logErro(fonte: string, detalhes: Record<string, unknown>) {
  const { error } = await supabase.from("logs_acoes").insert({
    acao: `ifood_erro_${fonte}`,
    detalhes,
  });
  if (error) {
    console.error(`[ifood-polling] FALHA AO GRAVAR LOG DE ERRO (${fonte}):`, error.message, detalhes);
  }
}

async function upsertConfig(chave: string, valor: string) {
  const { data, error: selErr } = await supabase.from("configuracoes").select("chave").eq("chave", chave).limit(1);
  if (selErr) { await logErro("config_ler", { chave, message: selErr.message }); return; }
  const { error: writeErr } = (data && data.length > 0)
    ? await supabase.from("configuracoes").update({ valor }).eq("chave", chave)
    : await supabase.from("configuracoes").insert({ chave, valor });
  if (writeErr) await logErro("config_gravar", { chave, message: writeErr.message });
}

// Token cacheado em `configuracoes` (mesmo padrão já usado por outras
// integrações do painel) — evita autenticar a cada polling. Token expira em
// 6h segundo a documentação; renovamos com 5min de margem.
async function getAccessToken(): Promise<string | null> {
  const { data: cfg, error: cfgErr } = await supabase
    .from("configuracoes")
    .select("chave, valor")
    .in("chave", ["ifood_access_token", "ifood_token_expires_at"]);
  if (cfgErr) await logErro("auth_ler_cache", { message: cfgErr.message });

  const cache: Record<string, string> = {};
  for (const c of cfg || []) cache[c.chave] = c.valor;

  const expiraEm = cache["ifood_token_expires_at"] ? new Date(cache["ifood_token_expires_at"]) : null;
  const aindaValido = !!expiraEm && expiraEm.getTime() - Date.now() > 5 * 60 * 1000;
  if (aindaValido && cache["ifood_access_token"]) return cache["ifood_access_token"];

  if (!IFOOD_CLIENT_ID || !IFOOD_CLIENT_SECRET) {
    await logErro("auth_credenciais_ausentes", { temClientId: !!IFOOD_CLIENT_ID, temClientSecret: !!IFOOD_CLIENT_SECRET });
    return null;
  }

  try {
    const res = await fetch(`${IFOOD_BASE_URL}/authentication/v1.0/oauth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grantType: "client_credentials",
        clientId: IFOOD_CLIENT_ID,
        clientSecret: IFOOD_CLIENT_SECRET,
      }),
    });

    const bodyText = await res.text();
    if (!res.ok) {
      await logErro("auth_http", { status: res.status, body: bodyText });
      return null;
    }

    let json: any;
    try { json = JSON.parse(bodyText); } catch (e) {
      await logErro("auth_parse", { message: String(e), body: bodyText });
      return null;
    }

    // TODO confirmar contra a doc autenticada: nome exato dos campos de
    // resposta (accessToken/access_token, expiresIn/expires_in).
    const token = json.accessToken ?? json.access_token;
    const expiresInSec = json.expiresIn ?? json.expires_in ?? 21600;
    if (!token) {
      await logErro("auth_resposta_sem_token", { body: bodyText });
      return null;
    }

    await upsertConfig("ifood_access_token", token);
    await upsertConfig("ifood_token_expires_at", new Date(Date.now() + expiresInSec * 1000).toISOString());
    return token;
  } catch (e) {
    await logErro("auth_excecao", { message: String(e) });
    return null;
  }
}

async function ifoodFetch(path: string, token: string, init: RequestInit = {}) {
  return fetch(`${IFOOD_BASE_URL}${path}`, {
    ...init,
    headers: { ...(init.headers || {}), Authorization: `Bearer ${token}` },
  });
}

// TODO confirmar contra a doc autenticada: schema exato do payload de
// detalhes do pedido (endereços, itens, valores). Estrutura abaixo é uma
// reconstrução a partir de documentação pública indireta — pesquisa não deu
// acesso à página oficial (403). Ajustar os caminhos (d.merchant?.address
// etc.) antes de ligar em produção, usando um pedido real do sandbox.
function mapearPedidoIfood(d: any) {
  const agora = new Date().toISOString();
  return {
    ifood_order_id: d.id ?? d.orderId,
    numero: String(d.displayId ?? d.id),
    numero_loja: String(d.displayId ?? d.id),
    origem: "ifood",
    status: "pronto",
    status_detalhado: "pronto",
    pagamento_confirmado: true,
    endereco: d.delivery?.deliveryAddress?.formattedAddress ?? d.deliveryAddress?.formattedAddress ?? "",
    latitude: d.delivery?.deliveryAddress?.coordinates?.latitude ?? null,
    longitude: d.delivery?.deliveryAddress?.coordinates?.longitude ?? null,
    endereco_coleta: d.merchant?.address?.formattedAddress ?? "",
    latitude_coleta: d.merchant?.address?.coordinates?.latitude ?? null,
    longitude_coleta: d.merchant?.address?.coordinates?.longitude ?? null,
    contato_coleta: d.merchant?.name ?? null,
    cliente: d.customer?.name ?? "",
    telefone: d.customer?.phone?.number ?? null,
    itens: d.items ?? [],
    valor: d.total?.subTotal ?? d.total?.orderAmount ?? 0,
    total_pedido: d.total?.orderAmount ?? 0,
    // TODO confirmar campo exato do valor repassado pelo iFood à LetsGo
    // pela entrega (não confirmado contra a doc — pode ser um campo
    // separado de "benefits"/"deliveryFee" no total).
    taxa_entrega: d.total?.deliveryFee ?? 0,
    recebido_em: agora,
    pronto_em: agora,
    created_at: agora,
    updated_at: agora,
  };
}

async function buscarDetalhesPedido(orderId: string, token: string) {
  // TODO confirmar path exato (pesquisa pública indicou GET
  // /logistics/orders/{id}, não confirmado contra doc autenticada).
  const res = await ifoodFetch(`/logistics/orders/${orderId}`, token, { method: "GET" });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    await logErro("detalhes_pedido_http", { orderId, status: res.status, body });
    return null;
  }
  try {
    return await res.json();
  } catch (e) {
    await logErro("detalhes_pedido_parse", { orderId, message: String(e) });
    return null;
  }
}

async function pollOnce(token: string) {
  // excludeHeartbeat=true é obrigatório para integradores de Logistics
  // (senão conta como "abrir a loja" e trava cancelamento no lado iFood).
  const res = await ifoodFetch("/events/v1.0/events:polling?excludeHeartbeat=true", token, { method: "GET" });

  if (res.status === 204) return;
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    await logErro("polling_http", { status: res.status, body });
    return;
  }

  let eventos: any[];
  try {
    eventos = await res.json();
  } catch (e) {
    await logErro("polling_parse", { message: String(e) });
    return;
  }

  const acks: string[] = [];

  for (const evento of eventos || []) {
    const orderId = evento.orderId ?? evento.id;
    if (!orderId) {
      await logErro("polling_evento_sem_orderId", { evento });
      continue; // sem ACK — se for evento real, volta no próximo polling
    }

    try {
      const detalhes = await buscarDetalhesPedido(orderId, token);
      if (!detalhes) continue; // erro já logado; sem ACK, tenta de novo

      const pedido = mapearPedidoIfood(detalhes);
      const { error: upsertErr } = await supabase
        .from("pedidos")
        .upsert(pedido, { onConflict: "ifood_order_id", ignoreDuplicates: true });

      if (upsertErr) {
        await logErro("persistir_pedido", { orderId, message: upsertErr.message });
        continue; // sem ACK — tenta de novo no próximo polling
      }

      acks.push(evento.id ?? orderId);
    } catch (e) {
      await logErro("processar_evento_excecao", { orderId, message: String(e) });
    }
  }

  if (acks.length > 0) {
    // TODO confirmar path e formato exato do body esperado por
    // /events/acknowledgment (doc pública não detalha o schema do body).
    const ackRes = await ifoodFetch("/events/v1.0/events/acknowledgment", token, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(acks.map((id) => ({ id }))),
    });
    if (!ackRes.ok) {
      const body = await ackRes.text().catch(() => "");
      await logErro("acknowledgment_http", { status: ackRes.status, body, acks });
    }
  }
}

serve(async () => {
  const problemas: string[] = [];
  // iFood recomenda polling a cada ~30s; pg_cron deste projeto só agenda de
  // minuto em minuto — duas iterações internas por invocação aproximam a
  // cadência recomendada sem exigir nada fora do padrão já usado no cron.
  for (let i = 0; i < 2; i++) {
    const token = await getAccessToken();
    if (!token) {
      problemas.push("sem token de acesso — ver logs_acoes (ifood_erro_auth*)");
      break;
    }
    try {
      await pollOnce(token);
    } catch (e) {
      await logErro("poll_loop_excecao", { message: String(e) });
      problemas.push(String(e));
    }
    if (i === 0) await new Promise((r) => setTimeout(r, 28000));
  }
  return new Response(JSON.stringify({ ok: problemas.length === 0, problemas }), { status: 200 });
});
