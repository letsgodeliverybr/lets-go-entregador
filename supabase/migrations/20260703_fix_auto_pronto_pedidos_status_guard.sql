-- Corrige o job pg_cron "auto-pronto-pedidos" (roda a cada minuto via
-- SELECT auto_pronto_pedidos();) — o WHERE original usava
-- (status = 'recebido' OR status_detalhado = 'recebido'), que reabre o
-- pedido pra 'pronto' sempre que QUALQUER UMA das duas colunas ainda diz
-- 'recebido', mesmo que a outra já tenha avançado bem além disso (ex.:
-- status='aceito' mas status_detalhado ficou parado em 'recebido' por
-- alguma escrita que não sincronizou as duas colunas).
--
-- Sintoma reproduzido: admin marca pedido como "Pronto" manualmente,
-- motoboy aceita rapidamente (status e status_detalhado corretamente
-- viram 'aceito' no app entregador — auditoria confirmou que todo fluxo
-- de aceite do app grava as duas colunas juntas, sem exceção), mas o job
-- reverte o pedido pra 'pronto' 1 minuto depois mesmo assim, tirando o
-- pedido da tela do motoboy que já tinha aceitado com sucesso.
--
-- Esta correção adiciona uma exclusão explícita: se QUALQUER UMA das
-- duas colunas já indica uma etapa além de "recebido", o job não mexe no
-- pedido — não importa a origem da dessincronia entre as colunas (app
-- entregador, painel administrativo, ou qualquer escrita futura).
create or replace function public.auto_pronto_pedidos()
returns void
language plpgsql
as $function$
begin
  update public.pedidos
  set
    status = 'pronto',
    status_detalhado = 'pronto',
    pronto_em = now(),
    updated_at = now()
  where
    (status = 'recebido' or status_detalhado = 'recebido')
    and status not in (
      'aceito', 'no_local', 'chegou_local', 'em_rota',
      'chegou_destino', 'retornando', 'finalizado', 'cancelado'
    )
    and status_detalhado not in (
      'aceito', 'no_local', 'chegou_local', 'em_rota',
      'chegou_destino', 'retornando', 'finalizado', 'cancelado'
    )
    and recebido_em is not null
    and recebido_em <= now() - interval '1 minute';
end;
$function$;
