-- Corrige solicitar_saque: v_total_ganho e v_total_sacado passam a
-- respeitar o ciclo semanal (segunda–domingo, horário Brasília),
-- alinhando a validação de saldo com o cálculo exibido em saldo_semana.dart.
-- Sem esse filtro, saques e pedidos de semanas anteriores eram somados,
-- distorcendo o saldo disponível e bloqueando saques legítimos.

CREATE OR REPLACE FUNCTION public.solicitar_saque(
  p_entregador_id  uuid,
  p_valor_bruto    numeric,
  p_chave_pix      text,
  p_tipo_chave_pix text,
  p_banco          text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_total_ganho   numeric;
  v_total_sacado  numeric;
  v_saldo         numeric;
  v_taxa          numeric;
  v_valor_liquido numeric;
  v_data_inicio   date;
  v_data_fim      date;
  v_ts_inicio     timestamptz;
  v_ts_fim        timestamptz;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(p_entregador_id::text));

  -- Período da semana atual em horário Brasília (segunda a domingo)
  v_data_inicio := date_trunc('week', (now() AT TIME ZONE 'America/Sao_Paulo'))::date;
  v_data_fim    := v_data_inicio + 6;

  -- Timestamps UTC: início da segunda-feira e início da segunda seguinte (exclusive)
  v_ts_inicio := v_data_inicio::timestamp AT TIME ZONE 'America/Sao_Paulo';
  v_ts_fim    := (v_data_fim + 1)::timestamp AT TIME ZONE 'America/Sao_Paulo';

  -- Ganhos da semana atual (alinhado com saldo_semana.dart)
  SELECT COALESCE(SUM(
    COALESCE(taxa_motoboy, 0) + COALESCE(gorjeta, 0)
  ), 0)
  INTO v_total_ganho
  FROM pedidos
  WHERE motoboy_id = p_entregador_id
    AND status     = 'finalizado'
    AND finalizado_em >= v_ts_inicio
    AND finalizado_em <  v_ts_fim;

  -- Saques do ciclo semanal atual — sobreposição data_inicio/data_fim
  -- (mesma lógica de saldo_semana.dart: data_inicio <= fim AND data_fim >= inicio)
  SELECT COALESCE(SUM(valor_bruto), 0)
  INTO v_total_sacado
  FROM saques
  WHERE entregador_id = p_entregador_id
    AND status        IN ('pago', 'pendente')
    AND data_inicio   <= v_data_fim
    AND data_fim      >= v_data_inicio;

  v_saldo := v_total_ganho - v_total_sacado;

  IF p_valor_bruto <= 0 THEN
    RAISE EXCEPTION 'valor_invalido';
  END IF;

  IF p_valor_bruto > v_saldo THEN
    RAISE EXCEPTION 'saldo_insuficiente: disponível R$ %, solicitado R$ %',
      ROUND(v_saldo, 2), ROUND(p_valor_bruto, 2);
  END IF;

  IF p_valor_bruto < 100 THEN
    v_taxa := 5.0;
  ELSE
    v_taxa := ROUND(p_valor_bruto * 0.05, 2);
  END IF;

  v_valor_liquido := p_valor_bruto - v_taxa;

  INSERT INTO saques (
    entregador_id, valor_bruto, taxa, valor_liquido, valor,
    chave_pix, tipo_chave_pix, banco, status,
    data_inicio, data_fim,
    created_at, updated_at
  ) VALUES (
    p_entregador_id, p_valor_bruto, v_taxa, v_valor_liquido, p_valor_bruto,
    p_chave_pix, p_tipo_chave_pix, p_banco, 'pendente',
    v_data_inicio, v_data_fim,
    now(), now()
  );

  RETURN json_build_object('sucesso', true, 'valor_liquido', v_valor_liquido, 'taxa', v_taxa);
END;
$function$;
