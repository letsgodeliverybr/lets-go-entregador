-- Corrige o Ponto 1: quando um pedido volta para status 'pronto' (ex.: admin
-- reabre o pedido para rechamar motoboys disponíveis), motoboy_id/entregador_id
-- ficavam com o id do motoboy anterior. Como o app filtra os pedidos
-- disponíveis por "motoboy_id is null or motoboy_id = usuário atual"
-- (lib/screens/pedidos_disponiveis_screen.dart), o pedido reaberto só
-- aparecia de volta para o motoboy que já tinha aceitado antes, mesmo o
-- push (FCM) sendo de fato enviado a todos os motoboys disponíveis.
--
-- Esta função roda BEFORE UPDATE OF status, então o valor gravado no banco
-- já sai com os ids limpos, e o trigger AFTER (tg_pedido_pronto_notify,
-- em 20260602_notify_pedido_trigger.sql) que dispara o broadcast continua
-- funcionando normalmente.
create or replace function public.fn_reset_motoboy_on_pronto()
returns trigger
language plpgsql
as $$
begin
  if NEW.status = 'pronto' and (OLD.status is null or OLD.status <> 'pronto') then
    NEW.motoboy_id := null;
    NEW.entregador_id := null;
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_reset_motoboy_on_pronto on public.pedidos;

create trigger tg_reset_motoboy_on_pronto
  before update of status
  on public.pedidos
  for each row
  execute function public.fn_reset_motoboy_on_pronto();
