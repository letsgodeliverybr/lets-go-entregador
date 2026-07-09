-- Corrige o Ponto 2: quando admin/loja/suporte realoca manualmente um
-- pedido já em andamento pra outro motoboy, a escrita direta em
-- pedidos.entregador_id/motoboy_id pulava o fluxo normal de notificação
-- e aceite/recusa, indo direto pra status='aceito'.
--
-- Esta trigger intercepta esse tipo de escrita e a redireciona pro mesmo
-- mecanismo de despacho direcionado (despacho_fila) já usado pelo modo
-- sequencial em pedidos_disponiveis_screen.dart — o motoboy escolhido
-- recebe o card com contagem de 29s e precisa aceitar/recusar, com o
-- mesmo claim guard (`status = 'pronto'`) de qualquer aceite normal.
--
-- Como distingue "realocação" de "aceite normal" sem depender de quem
-- fez a escrita (admin, loja, suporte ou o próprio motoboy):
-- todo aceite normal no app (aceitar_pedido_screen.dart,
-- pedidos_disponiveis_screen.dart, rota_disponivel_screen.dart) só
-- consegue escrever motoboy_id/entregador_id em linhas que já estavam
-- com status='pronto' OU status_detalhado='pronto' (é o WHERE da própria
-- query de aceite) — ou seja, OLD.status/status_detalhado SEMPRE é
-- 'pronto' num aceite normal. Se o motoboy muda enquanto NENHUM dos dois
-- campos era 'pronto' (pedido já em andamento: 'aceito', 'em_rota' etc.),
-- só pode ser reatribuição.
create or replace function public.fn_intercept_realocacao_manual()
returns trigger
language plpgsql
as $$
declare
  v_novo_courier uuid;
begin
  v_novo_courier := coalesce(NEW.entregador_id, NEW.motoboy_id);

  if v_novo_courier is not null
     and v_novo_courier is distinct from coalesce(OLD.entregador_id, OLD.motoboy_id)
     and OLD.status is distinct from 'pronto'
     and OLD.status_detalhado is distinct from 'pronto'
  then
    insert into public.despacho_fila (pedido_id, entregador_id, status, onda, enviado_em, expira_em)
    values (NEW.id, v_novo_courier, 'aguardando', 1, now(), now() + interval '30 seconds');

    NEW.status := 'pronto';
    NEW.status_detalhado := 'pronto';
    NEW.motoboy_id := null;
    NEW.entregador_id := null;
  end if;

  return NEW;
end;
$$;

drop trigger if exists tg_intercept_realocacao_manual on public.pedidos;

create trigger tg_intercept_realocacao_manual
  before update on public.pedidos
  for each row
  execute function public.fn_intercept_realocacao_manual();

-- ─────────────────────────────────────────────────────────────────────────
-- Segunda camada de proteção contra broadcast acidental pra todos os
-- motoboys (já tivemos incidente disso antes, com outro mecanismo).
--
-- fn_notify_pedido_pronto (20260602_notify_pedido_trigger.sql) dispara
-- AFTER UPDATE OF status quando um pedido vira 'pronto', e o edge function
-- que ela chama (notify-novo-pedido) manda push FCM pra TODO entregador
-- com disponivel=true — é um broadcast sem nenhum targeting por pedido.
--
-- O intercept acima força NEW.status := 'pronto' dentro de um BEFORE
-- trigger. Pela semântica do Postgres, "AFTER UPDATE OF status" só
-- dispara se a coluna status estiver na lista SET da instrução UPDATE
-- original — então, hoje, uma realocação que escreve só entregador_id/
-- motoboy_id não deveria religar esse broadcast. Mas essa proteção
-- depende inteiramente de como o painel de admin/loja/suporte monta o
-- UPDATE (fora deste repositório, sem visibilidade daqui) — se algum dia
-- esse UPDATE incluir status no mesmo SET, o broadcast dispara nesse
-- caso de novo.
--
-- Esta segunda camada remove essa dependência: pula o broadcast sempre
-- que já existe uma linha 'aguardando' em despacho_fila pro pedido —
-- sinal de que é uma reatribuição direcionada (inserida pelo intercept
-- acima, na mesma transação), não um pedido genuinamente novo. Pedidos
-- novos legítimos nunca têm despacho_fila neste momento, porque quem
-- povoa despacho_fila pro modo sequencial é o cron despacho-engine,
-- rodando de forma assíncrona (a cada minuto) — nunca na mesma transação
-- da escrita que muda o pedido pra 'pronto'.
create or replace function public.fn_notify_pedido_pronto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.status = 'pronto' and (OLD.status is null or OLD.status <> 'pronto') then
    if exists (
      select 1 from public.despacho_fila
      where pedido_id = NEW.id and status = 'aguardando'
    ) then
      return NEW;
    end if;

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
