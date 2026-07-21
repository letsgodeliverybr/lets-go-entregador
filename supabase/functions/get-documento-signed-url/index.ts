import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BUCKET = "documentos-entregador";
const TIPOS_VALIDOS = ["foto_perfil", "cnh", "crlv", "comprovante_residencia"];

Deno.serve(async (req) => {
  // Valida segredo compartilhado (mesmo padrão de notify-novo-pedido) — o
  // painel não tem sessão real de Supabase Auth (sistema.letsgodelivery.com.br
  // nunca gera JWT real), então não dá pra restringir isso por RLS/auth.uid().
  // O bucket em si é privado; só quem tem esse segredo consegue pedir uma URL
  // assinada, e ela expira em poucos minutos.
  const secret = req.headers.get("x-webhook-secret");
  if (secret !== Deno.env.get("PAINEL_DOCS_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }

  const payload = await req.json().catch(() => ({}));
  const entregadorId: string | undefined = payload.entregador_id;
  const tipo: string | undefined = payload.tipo;

  if (!entregadorId || !tipo || !TIPOS_VALIDOS.includes(tipo)) {
    return new Response(
      JSON.stringify({ error: "entregador_id e tipo (foto_perfil|cnh|crlv|comprovante_residencia) são obrigatórios" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const path = `${entregadorId}/${tipo}.jpg`;
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .createSignedUrl(path, 300);

  if (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 404, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ url: data.signedUrl }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
