import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const IFOOD_CLIENT_ID = Deno.env.get("IFOOD_CLIENT_ID") ?? "";
const IFOOD_CLIENT_SECRET = Deno.env.get("IFOOD_CLIENT_SECRET") ?? "";
const IFOOD_BASE_URL = "https://merchant-api.ifood.com.br";
const MAX_TENTATIVAS = 5;

async function logErro(fonte: string, detalhes: Record<string, unknown>) {
  const { error } = await supabase.from("logs_acoes").insert({
    acao: `ifood_erro_${fonte}`,
    detalhes,
  });
  if (error) {
    console.error(`[ifood-status-sync] FALHA AO GRAVAR LOG DE ERRO (${fonte}):`, error.message, detalhes);
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

// Mesmo cache de token usado em ifood-polling (functions do Supabase são
// isoladas por deploy; duplicar esse helper segue o mesmo padrão já usado
// no resto do projeto — nenhuma outra function daqui compartilha módulo).
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

// TODO confirmar contra a doc autenticada: paths exatos. Pesquisa pública
// indicou POST /goingToOrigin, /arrivedAtOrigin, /dispatch,
// /arrivedAtDestination sob o recurso do pedido de logistics — formato
// abaixo (/logistics/orders/{id}/{evento}) é a reconstrução mais provável,
// mas não confirmada. Ajustar antes de ligar em produção.
function endpointParaEvento(ifoodOrderId: string, evento: string): string {
  return `/logistics/orders/${ifoodOrderId}/${evento}`;
}

serve(async () => {
  const token = await getAccessToken();
  if (!token) {
    return new Response(JSON.stringify({ ok: false, motivo: "sem token de acesso" }), { status: 200 });
  }

  const { data: fila, error: filaErr } = await supabase
    .from("ifood_status_queue")
    .select("id, pedido_id, evento, tentativas, pedidos(ifood_order_id)")
    .in("status", ["pendente", "erro"])
    .lt("tentativas", MAX_TENTATIVAS)
    .order("criado_em", { ascending: true })
    .limit(50);

  if (filaErr) {
    await logErro("ler_fila", { message: filaErr.message });
    return new Response(JSON.stringify({ ok: false, motivo: "erro ao ler fila" }), { status: 200 });
  }

  let enviados = 0, comErro = 0;

  for (const item of fila || []) {
    const ifoodOrderId = (item as any).pedidos?.ifood_order_id;
    if (!ifoodOrderId) {
      await logErro("fila_sem_ifood_order_id", { queueId: item.id, pedidoId: item.pedido_id });
      await supabase.from("ifood_status_queue").update({
        status: "erro", tentativas: item.tentativas + 1, erro: "pedido sem ifood_order_id",
      }).eq("id", item.id);
      comErro++;
      continue;
    }

    try {
      const path = endpointParaEvento(ifoodOrderId, item.evento);
      const res = await fetch(`${IFOOD_BASE_URL}${path}`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      });

      if (res.ok) {
        await supabase.from("ifood_status_queue").update({
          status: "enviado", enviado_em: new Date().toISOString(),
        }).eq("id", item.id);
        enviados++;
      } else {
        const body = await res.text().catch(() => "");
        await logErro("enviar_status_http", { queueId: item.id, ifoodOrderId, evento: item.evento, status: res.status, body });
        await supabase.from("ifood_status_queue").update({
          status: "erro", tentativas: item.tentativas + 1, erro: `HTTP ${res.status}: ${body.slice(0, 500)}`,
        }).eq("id", item.id);
        comErro++;
      }
    } catch (e) {
      await logErro("enviar_status_excecao", { queueId: item.id, ifoodOrderId, evento: item.evento, message: String(e) });
      await supabase.from("ifood_status_queue").update({
        status: "erro", tentativas: item.tentativas + 1, erro: String(e),
      }).eq("id", item.id);
      comErro++;
    }
  }

  return new Response(JSON.stringify({ ok: true, enviados, comErro }), { status: 200 });
});
