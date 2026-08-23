import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const FCM_SA = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
const FCM_PROJECT = FCM_SA.project_id ?? "";

async function getFcmAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: FCM_SA.client_email,
    sub: FCM_SA.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat: getNumericDate(0),
    exp: getNumericDate(3600),
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };
  const privateKey = FCM_SA.private_key;
  const keyData = privateKey.replace(/\\n/g, "\n");
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const pemContents = keyData.substring(
    keyData.indexOf(pemHeader) + pemHeader.length,
    keyData.indexOf(pemFooter)
  ).replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8", binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"]
  );
  const jwt = await create({ alg: "RS256", typ: "JWT" }, payload, cryptoKey);
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await tokenRes.json();
  return tokenData.access_token;
}

async function enviarPushFCM(fcmToken: string, pedidoId: string, numero: string) {
  if (!FCM_PROJECT || !fcmToken) return;
  try {
    const accessToken = await getFcmAccessToken();
    await fetch(`https://fcm.googleapis.com/v1/projects/${FCM_PROJECT}/messages:send`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        // Data-only de propósito (sem bloco `notification`): um payload com
        // `notification` é renderizado pelo próprio Android direto do
        // sistema quando o app está em background/morto, sem nunca chamar
        // código do app — nesse caminho não tem como pedir full-screen
        // intent nem controlar o som (esse campo não existe no formato
        // `notification` do FCM), e também foi assim que um channel_id
        // desatualizado (sem o sufixo _v3, achado nesta correção) foi
        // parar em produção sem ninguém notar — nada validava contra os
        // canais reais criados no app. Data-only força a entrega sempre
        // passar pelo código do app (_firebaseBackgroundHandler em
        // main.dart, mesmo com o app morto), que constrói a notificação
        // local com fullScreenIntent de verdade, usando os canais reais.
        message: {
          token: fcmToken,
          data: { tipo: "novo_pedido", pedido_id: pedidoId, numero: String(numero) },
          android: { priority: "HIGH" },
        },
      }),
    });
  } catch (e) {
    console.error("Erro FCM V1:", e);
  }
}

function haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// rotas_agrupadas.status tem CHECK constraint restrita a:
// 'pendente' | 'aceita' | 'em_rota' | 'finalizada' | 'cancelada'.
// Qualquer outro valor falha a constraint e o UPDATE é rejeitado.
function logErr(ctx: string, error: { message?: string } | null | undefined) {
  if (error) console.error(`[despacho-engine] ${ctx}:`, error.message ?? error);
}

serve(async () => {
  try {
    const { data: configs } = await supabase
      .from("configuracoes").select("chave, valor")
      .in("chave", [
        "modo_despacho","despacho_tempo_exibicao_seg",
        "despacho_onda_1_raio","despacho_onda_1_max",
        "despacho_onda_2_raio","despacho_onda_2_max",
        "despacho_onda_3_raio","despacho_onda_3_max",
        "despacho_onda_4_raio","despacho_onda_4_max",
        "despacho_tempo_reset_min","despacho_raio_busca_km",
      ]);

    const cfg: Record<string, string> = {};
    for (const c of configs || []) cfg[c.chave] = c.valor;

    const modo = cfg["modo_despacho"] || "todos";
    const tempoExibicao = parseInt(cfg["despacho_tempo_exibicao_seg"] || "29");
    const tempoReset = parseInt(cfg["despacho_tempo_reset_min"] || "12") * 60;
    const ondas = [
      { raio: parseFloat(cfg["despacho_onda_1_raio"] || "4"),  maxMin: parseFloat(cfg["despacho_onda_1_max"] || "3") },
      { raio: parseFloat(cfg["despacho_onda_2_raio"] || "8"),  maxMin: parseFloat(cfg["despacho_onda_2_max"] || "6") },
      { raio: parseFloat(cfg["despacho_onda_3_raio"] || "16"), maxMin: parseFloat(cfg["despacho_onda_3_max"] || "9") },
      { raio: parseFloat(cfg["despacho_onda_4_raio"] || "32"), maxMin: parseFloat(cfg["despacho_onda_4_max"] || "12") },
    ];

    // ── ROTERIZADOR: agrupa pedidos em preparo, não despacha ainda ───────────
    const { data: lojasRoter } = await supabase
      .from("lojas")
      .select("id, roterizador_tempo_espera_seg, roterizador_raio_km")
      .eq("roterizador_ativo", true);

    for (const loja of lojasRoter || []) {
      const tempoEspera = loja.roterizador_tempo_espera_seg || 120;
      const raioKm = parseFloat(loja.roterizador_raio_km || "3");
      const janela = new Date(Date.now() - tempoEspera * 1000).toISOString();

      const { data: pedidosLoja } = await supabase
        .from("pedidos")
        .select("id, taxa_motoboy, latitude, longitude")
        .eq("status", "recebido")
        .eq("loja_id", loja.id)
        .is("motoboy_id", null)
        .is("rota_agrupada_id", null)
        .gte("created_at", janela);

      if (!pedidosLoja || pedidosLoja.length < 2) continue;

      let podeAgrupar = false;
      outer: for (let i = 0; i < pedidosLoja.length; i++) {
        for (let j = i + 1; j < pedidosLoja.length; j++) {
          const dist = haversine(
            pedidosLoja[i].latitude, pedidosLoja[i].longitude,
            pedidosLoja[j].latitude, pedidosLoja[j].longitude,
          );
          if (dist <= raioKm) { podeAgrupar = true; break outer; }
        }
      }
      if (!podeAgrupar) continue;

      const pedidoIds = pedidosLoja.map((p: any) => p.id);
      const valorTotal = pedidosLoja.reduce(
        (sum: number, p: any) => sum + (parseFloat(p.taxa_motoboy) || 0), 0,
      );

      const { data: rota, error: rotaInsertErr } = await supabase
        .from("rotas_agrupadas")
        .insert({ loja_id: loja.id, pedido_ids: pedidoIds, valor_total: valorTotal, status: "pendente" })
        .select("id").single();

      logErr(`criar rota_agrupada (loja ${loja.id})`, rotaInsertErr);
      if (!rota) continue;

      // Marca pedidos com rota_agrupada_id — despacho ocorre depois, quando todos ficarem prontos
      const { error: marcarRotaErr } = await supabase.from("pedidos")
        .update({ rota_agrupada_id: rota.id }).in("id", pedidoIds);
      logErr(`marcar pedidos com rota_agrupada_id (rota ${rota.id})`, marcarRotaErr);
    }
    // ── FIM ROTERIZADOR ──────────────────────────────────────────────────────

    // ── DESPACHO DE ROTAS: dispara quando todos os pedidos estão prontos ─────
    const { data: rotasPendentes } = await supabase
      .from("rotas_agrupadas")
      .select("id, pedido_ids, loja_id")
      .eq("status", "pendente");

    for (const rota of rotasPendentes || []) {
      const pedidoIds = (rota.pedido_ids || []) as string[];
      if (pedidoIds.length === 0) {
        const { error } = await supabase.from("rotas_agrupadas").update({ status: "cancelada" }).eq("id", rota.id);
        logErr(`cancelar rota vazia ${rota.id}`, error);
        continue;
      }

      const { data: pedidosRota, error: pedidosRotaErr } = await supabase
        .from("pedidos")
        .select("id, numero, status, motoboy_id, latitude, longitude")
        .in("id", pedidoIds);
      logErr(`buscar pedidos da rota ${rota.id}`, pedidosRotaErr);

      if (!pedidosRota || pedidosRota.length === 0) {
        const { error } = await supabase.from("rotas_agrupadas").update({ status: "cancelada" }).eq("id", rota.id);
        logErr(`cancelar rota sem pedidos ${rota.id}`, error);
        continue;
      }

      const algumAceito = pedidosRota.some((p: any) => p.motoboy_id !== null);
      if (algumAceito) {
        // Pedido aceito por alguém fora do fluxo de rota: desagrupa os restantes
        // e encerra a tentativa de rota (não virou uma entrega em grupo de fato).
        const idsRestantes = pedidosRota.filter((p: any) => !p.motoboy_id).map((p: any) => p.id);
        if (idsRestantes.length > 0) {
          const { error } = await supabase.from("pedidos").update({ rota_agrupada_id: null }).in("id", idsRestantes);
          logErr(`desagrupar pedidos restantes da rota ${rota.id}`, error);
        }
        const { error: closeErr } = await supabase.from("rotas_agrupadas").update({ status: "cancelada" }).eq("id", rota.id);
        logErr(`encerrar rota ${rota.id} (aceite individual)`, closeErr);
        continue;
      }

      const todosProtos = pedidosRota.every((p: any) => p.status === "pronto");
      const algumProto  = pedidosRota.some((p: any) => p.status === "pronto");

      if (todosProtos) {
        // Todos prontos: despacha a rota (uma vez só)
        const { data: jaFilaRota, error: jaFilaRotaErr } = await supabase
          .from("despacho_fila").select("id").eq("rota_agrupada_id", rota.id).limit(1);
        logErr(`verificar despacho_fila existente da rota ${rota.id}`, jaFilaRotaErr);
        if ((jaFilaRota?.length || 0) > 0) continue;

        const refP = pedidosRota[0];
        const agoraRota = new Date();
        const { data: entregadores, error: entRaioErr } = await supabase.rpc("entregadores_no_raio", {
          p_lat: refP.latitude, p_lng: refP.longitude,
          p_raio_km: parseFloat(cfg["despacho_raio_busca_km"] || "32"),
          p_loja_id: rota.loja_id,
        });
        logErr(`buscar entregadores no raio da rota ${rota.id}`, entRaioErr);

        for (const e of entregadores || []) {
          const expira = new Date(agoraRota.getTime() + tempoExibicao * 1000);
          // Cria uma entrada de despacho_fila por pedido do grupo — antes só o
          // primeiro pedido (pedidoIds[0]) era notificado, e os demais ficavam
          // presos: nunca recebiam despacho_fila e, por continuarem com
          // rota_agrupada_id preenchido, ficavam de fora do loop individual
          // também. Resultado: pedido "sumia" sem nunca ser despachado.
          for (const pid of pedidoIds) {
            const { error: filaErr } = await supabase.from("despacho_fila").insert({
              pedido_id: pid, entregador_id: e.id,
              rota_agrupada_id: rota.id,
              status: "aguardando", onda: 1, expira_em: expira.toISOString(),
            });
            logErr(`inserir despacho_fila (rota ${rota.id}, pedido ${pid}, entregador ${e.id})`, filaErr);
          }
          const { data: ent, error: entErr } = await supabase.from("entregadores")
            .select("fcm_token").eq("id", e.id).single();
          logErr(`buscar fcm_token do entregador ${e.id}`, entErr);
          if (ent?.fcm_token) await enviarPushFCM(ent.fcm_token, pedidoIds[0], refP.numero || "");
        }
        const { error: despachadaErr } = await supabase.from("rotas_agrupadas").update({ status: "aceita" }).eq("id", rota.id);
        logErr(`marcar rota ${rota.id} como despachada`, despachadaErr);

      } else if (algumProto) {
        // Alguns prontos, outros ainda em preparo: desagrupa os prontos para despacho individual
        const idsProtos = pedidosRota
          .filter((p: any) => p.status === "pronto")
          .map((p: any) => p.id);
        const { error } = await supabase.from("pedidos").update({ rota_agrupada_id: null }).in("id", idsProtos);
        logErr(`desagrupar pedidos prontos da rota ${rota.id}`, error);
      }
      // Se todos ainda 'recebido': aguarda o próximo tick
    }
    // ── FIM DESPACHO DE ROTAS ─────────────────────────────────────────────────

    // Loop de despacho normal — pedidos sem rota (incluindo recém-desagrupados)
    // loja_id: precisa pra checar exclusividade de clã em entregadores_no_raio.
    const { data: pedidos } = await supabase
      .from("pedidos").select("id, numero, latitude, longitude, created_at, loja_id")
      .eq("status", "pronto").is("motoboy_id", null)
      .is("rota_agrupada_id", null);

    for (const pedido of pedidos || []) {
      const agora = new Date();
      const segundosPassados = (agora.getTime() - new Date(pedido.created_at).getTime()) / 1000;

      // Verificação: pedido cancelado ou já aceito por outro entregador
      const { data: pedidoAtual, error: pedidoAtualErr } = await supabase
        .from("pedidos").select("status, motoboy_id").eq("id", pedido.id).single();
      logErr(`reler pedido ${pedido.id}`, pedidoAtualErr);
      if (!pedidoAtual || pedidoAtual.status !== "pronto" || pedidoAtual.motoboy_id !== null) {
        const { error } = await supabase.from("despacho_fila").update({ status: "expirado" })
          .eq("pedido_id", pedido.id).eq("status", "aguardando");
        logErr(`expirar despacho_fila do pedido ${pedido.id} (fora do estado despachável)`, error);
        continue;
      }

      if (segundosPassados > tempoReset) {
        // Rede de segurança final (decisão de negócio): depois do tempo de
        // reset sem aceite em nenhuma onda, dispara pra QUALQUER entregador
        // disponível que ainda não tenha recebido oferta nenhuma pra esse
        // pedido (qualquer onda/tentativa anterior, não só 'aguardando' —
        // ver comentário abaixo), SEM limite de raio. Antes disso ficava
        // capado em despacho_raio_busca_km (32km) e só rodava uma vez
        // (sentinel onda=99); um pedido fora desse raio, ou cujos únicos
        // candidatos não aceitassem, ficava preso pra sempre depois do
        // timeout. Sem o cap de raio e sem o sentinel de "uma vez só", isso
        // roda em todo tick subsequente e para sozinho quando não sobrar
        // mais ninguém pra notificar (disponiveis.length === 0) — inclusive
        // alcançando quem ficar disponível depois do timeout.
        const { error: expirarErr } = await supabase.from("despacho_fila").update({ status: "expirado" })
          .eq("pedido_id", pedido.id).eq("status", "aguardando");
        logErr(`expirar despacho_fila do pedido ${pedido.id} (fallback)`, expirarErr);

        // Todo mundo que já recebeu oferta pra esse pedido em qualquer onda
        // ou tentativa (não só 'aguardando'): senão o entregador mais
        // próximo, já expirado, seria oferecido de novo em vez de alcançar
        // alguém novo.
        const { data: jaReceberam, error: jaReceberamErr } = await supabase.from("despacho_fila")
          .select("entregador_id").eq("pedido_id", pedido.id);
        logErr(`listar quem ja recebeu o pedido ${pedido.id}`, jaReceberamErr);
        const idsJaReceberam = (jaReceberam || []).map((r: any) => r.entregador_id);

        const { data: entregadores, error: entRaioErr } = await supabase.rpc("entregadores_no_raio", {
          p_lat: pedido.latitude, p_lng: pedido.longitude,
          p_raio_km: 40075, // sem limite de raio — metade da circunferência da Terra
          p_loja_id: pedido.loja_id,
        });
        logErr(`buscar entregadores no raio (fallback, pedido ${pedido.id})`, entRaioErr);

        const disponiveis = (entregadores || []).filter((e: any) => !idsJaReceberam.includes(e.id));
        for (const e of disponiveis) {
          const expira = new Date(agora.getTime() + tempoExibicao * 1000);
          const { error: filaErr } = await supabase.from("despacho_fila").insert({
            pedido_id: pedido.id, entregador_id: e.id,
            status: "aguardando", onda: 99, expira_em: expira.toISOString(),
          });
          logErr(`inserir despacho_fila fallback (pedido ${pedido.id}, entregador ${e.id})`, filaErr);
          const { data: ent, error: entErr } = await supabase.from("entregadores")
            .select("fcm_token").eq("id", e.id).single();
          logErr(`buscar fcm_token do entregador ${e.id}`, entErr);
          if (ent?.fcm_token) await enviarPushFCM(ent.fcm_token, pedido.id, pedido.numero);
        }
        continue;
      }

      if (modo === "todos") {
        // Expira ofertas vencidas ANTES de checar "já enviado" — sem isso,
        // uma vez que a janela de expira_em passa sem ninguém aceitar, a
        // linha continua 'aguardando' pra sempre (nada nunca a marcava como
        // 'expirado' neste modo, diferente do modo 'ondas', que já fazia
        // essa varredura). O motoboy para de ver/tocar o pedido (respeitando
        // expira_em no client), mas o banco segue achando que "ainda tem
        // gente olhando" e nunca redespacha — pedido fica pronto e invisível
        // pra sempre. Bug real, reproduzido em produção (Novigo, 2026-07-12).
        const { error: expirarTodosErr } = await supabase.from("despacho_fila").update({ status: "expirado" })
          .eq("pedido_id", pedido.id).eq("status", "aguardando")
          .lt("expira_em", agora.toISOString());
        logErr(`expirar ofertas vencidas do pedido ${pedido.id} (modo todos)`, expirarTodosErr);

        // Escopado a 'aguardando' (não "qualquer linha que já existiu"): um
        // pedido aceito e depois desalocado (ou que voltou a ficar
        // disponível por qualquer outro motivo) tem que poder ser
        // redespachado. Checar por qualquer status histórico travava esse
        // pedido pra sempre, mesmo já liberado de volta pro broadcast. Com a
        // expiração acima, isso agora também cobre o retry natural: uma vez
        // que a onda expira sem aceite, este check libera um novo broadcast
        // completo no próximo tick.
        const jaEnviado = await supabase.from("despacho_fila")
          .select("id").eq("pedido_id", pedido.id).eq("status", "aguardando").limit(1);
        logErr(`verificar envio existente do pedido ${pedido.id}`, jaEnviado.error);
        if ((jaEnviado.data?.length || 0) > 0) continue;

        const { data: entregadores, error: entRaioErr } = await supabase.rpc("entregadores_no_raio", {
          p_lat: pedido.latitude, p_lng: pedido.longitude,
          p_raio_km: parseFloat(cfg["despacho_raio_busca_km"] || "32"),
          p_loja_id: pedido.loja_id,
        });
        logErr(`buscar entregadores no raio (pedido ${pedido.id})`, entRaioErr);

        for (const e of entregadores || []) {
          const expira = new Date(agora.getTime() + tempoExibicao * 1000);
          const { error: filaErr } = await supabase.from("despacho_fila").insert({
            pedido_id: pedido.id, entregador_id: e.id,
            status: "aguardando", onda: 1, expira_em: expira.toISOString(),
          });
          logErr(`inserir despacho_fila (pedido ${pedido.id}, entregador ${e.id})`, filaErr);
          const { data: ent, error: entErr } = await supabase.from("entregadores")
            .select("fcm_token").eq("id", e.id).single();
          logErr(`buscar fcm_token do entregador ${e.id}`, entErr);
          if (ent?.fcm_token) await enviarPushFCM(ent.fcm_token, pedido.id, pedido.numero);
        }
      } else {
        const { error: expirarOndaErr } = await supabase.from("despacho_fila").update({ status: "expirado" })
          .eq("pedido_id", pedido.id).eq("status", "aguardando")
          .lt("expira_em", agora.toISOString());
        logErr(`expirar ondas vencidas do pedido ${pedido.id}`, expirarOndaErr);

        const { data: aguardando, error: aguardandoErr } = await supabase.from("despacho_fila")
          .select("id").eq("pedido_id", pedido.id).eq("status", "aguardando").limit(1);
        logErr(`verificar onda aguardando do pedido ${pedido.id}`, aguardandoErr);
        if ((aguardando?.length || 0) > 0) continue;

        const minutosPassados = segundosPassados / 60;
        let ondaAtual = ondas[ondas.length - 1];
        let ondaNum = ondas.length;
        for (let i = 0; i < ondas.length; i++) {
          if (minutosPassados <= ondas[i].maxMin) { ondaAtual = ondas[i]; ondaNum = i + 1; break; }
        }

        // Todo mundo que já recebeu oferta pra esse pedido em qualquer onda
        // anterior (não só 'aguardando'): senão, assim que a oferta do mais
        // próximo expira (29s), ele deixa de estar "excluído" e volta a ser
        // o disponiveis[0] de novo — a onda escala em raio mas nunca chega
        // em ninguém novo, porque o mesmo entregador mais próximo é
        // reofertado pra sempre em vez do próximo da fila.
        const { data: jaReceberam, error: jaReceberamErr } = await supabase.from("despacho_fila")
          .select("entregador_id").eq("pedido_id", pedido.id);
        logErr(`listar quem ja recebeu o pedido ${pedido.id} (ondas)`, jaReceberamErr);
        const idsJaReceberam = (jaReceberam || []).map((r: any) => r.entregador_id);

        const { data: entregadores, error: entRaioOndaErr } = await supabase.rpc("entregadores_no_raio", {
          p_lat: pedido.latitude, p_lng: pedido.longitude, p_raio_km: ondaAtual.raio,
          p_loja_id: pedido.loja_id,
        });
        logErr(`buscar entregadores no raio (onda ${ondaNum}, pedido ${pedido.id})`, entRaioOndaErr);

        const disponiveis = (entregadores || []).filter((e: any) => !idsJaReceberam.includes(e.id));
        if (disponiveis.length === 0) continue;

        const proximo = disponiveis[0];
        const expira = new Date(agora.getTime() + tempoExibicao * 1000);
        const { error: filaOndaErr } = await supabase.from("despacho_fila").insert({
          pedido_id: pedido.id, entregador_id: proximo.id,
          status: "aguardando", onda: ondaNum, expira_em: expira.toISOString(),
        });
        logErr(`inserir despacho_fila (onda ${ondaNum}, pedido ${pedido.id}, entregador ${proximo.id})`, filaOndaErr);

        const { data: ent, error: entOndaErr } = await supabase.from("entregadores")
          .select("fcm_token").eq("id", proximo.id).single();
        logErr(`buscar fcm_token do entregador ${proximo.id}`, entOndaErr);
        if (ent?.fcm_token) await enviarPushFCM(ent.fcm_token, pedido.id, pedido.numero);
      }
    }

    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
