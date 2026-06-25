-- Habilita pg_net (necessário para chamadas HTTP dentro de triggers)
create extension if not exists pg_net schema extensions;

-- Coluna fcm_token na tabela entregadores (pula se já existir)
alter table public.entregadores
  add column if not exists fcm_token text;

-- ATENÇÃO: app.notify_secret NÃO pode ser definido via migration (exige superusuário).
-- Configure pelo painel Supabase: Database → Configuration → Custom config
-- Adicione:  app.notify_secret = '<seu_secret>'

-- Função chamada pelo trigger
create or replace function public.fn_notify_pedido_pronto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Só dispara quando status muda PARA 'pronto'
  if NEW.status = 'pronto' and (OLD.status is null or OLD.status <> 'pronto') then
    perform extensions.net.http_post(
      url     := 'https://astbkmpegcmqljltmdpx.supabase.co/functions/v1/notify-novo-pedido',
      headers := jsonb_build_object(
                   'Content-Type',      'application/json',
                   'x-webhook-secret',  current_setting('app.notify_secret')
                 ),
      body    := jsonb_build_object(
                   'tipo',      'novo_pedido',
                   'pedido_id', NEW.id
                 )::text
    );
  end if;
  return NEW;
end;
$$;

-- Trigger na tabela pedidos
drop trigger if exists tg_pedido_pronto_notify on public.pedidos;

create trigger tg_pedido_pronto_notify
  after insert or update of status
  on public.pedidos
  for each row
  execute function public.fn_notify_pedido_pronto();
