-- Push (FCM) direcionado para o entregador quando o roterizador automático
-- coloca um pedido/rota na fila individual dele (despacho_fila). Espelha o
-- padrão de 20260602_notify_pedido_trigger.sql, mas com entrega direcionada
-- (um único entregador) em vez de broadcast pra todos os disponíveis.

create or replace function public.fn_notify_despacho_fila()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.status = 'aguardando' then
    perform extensions.net.http_post(
      url     := 'https://astbkmpegcmqljltmdpx.supabase.co/functions/v1/notify-novo-pedido',
      headers := jsonb_build_object(
                   'Content-Type',      'application/json',
                   'x-webhook-secret',  current_setting('app.notify_secret')
                 ),
      body    := jsonb_build_object(
                   'tipo',          'nova_rota',
                   'entregador_id', NEW.entregador_id
                 )::text
    );
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_despacho_fila_notify on public.despacho_fila;

create trigger tg_despacho_fila_notify
  after insert
  on public.despacho_fila
  for each row
  execute function public.fn_notify_despacho_fila();
