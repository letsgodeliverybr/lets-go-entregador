-- Habilita pg_net (necessário para chamadas HTTP dentro de triggers)
create extension if not exists pg_net schema extensions;

-- Coluna fcm_token na tabela entregadores (pula se já existir)
alter table public.entregadores
  add column if not exists fcm_token text;

-- Armazena o segredo do webhook como configuração do banco
-- SUBSTITUA 'SEU_SECRET_AQUI' pelo mesmo valor definido em NOTIFY_WEBHOOK_SECRET
alter database postgres set app.notify_secret = 'SEU_SECRET_AQUI';

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
