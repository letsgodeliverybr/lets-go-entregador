-- Corrige solicitar_saque para preencher data_inicio e data_fim
-- com o período da semana atual (segunda a domingo, horário Brasília).
-- Sem isso, saques avulsos ficam invisíveis ao cálculo de saldo_semana,
-- que filtra por overlap de data_inicio/data_fim (não por created_at).

CREATE OR REPLACE FUNCTION public.solicitar_saque(
  p_entregador_id uuid,
  p_valor_bruto   numeric,
  p_chave_pix     text,
  p_tipo_chave_pix text,
  p_banco         text
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
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(p_entregador_id::text));

  -- ✅ Usa taxa_entrega (sempre preenchido), fallback taxa_entrega_motoboy, fallback gorjeta
  SELECT COALESCE(SUM(
    CASE
      WHEN COALESCE(taxa_entrega, 0) > 0 THEN taxa_entrega
      WHEN COALESCE(taxa_entrega_motoboy, 0) > 0 THEN taxa_entrega_motoboy
      ELSE COALESCE(gorjeta, 0)
    END
  ), 0)
  INTO v_total_ganho
  FROM pedidos
  WHERE (entregador_id = p_entregador_id OR motoboy_id = p_entregador_id)
    AND status = 'finalizado';

  SELECT COALESCE(SUM(valor_bruto), 0)
  INTO v_total_sacado
  FROM saques
  WHERE entregador_id = p_entregador_id
    AND status IN ('pago', 'pendente');

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

  -- Período da semana atual em horário Brasília (segunda a domingo)
  v_data_inicio := date_trunc('week', (now() AT TIME ZONE 'America/Sao_Paulo'))::date;
  v_data_fim    := v_data_inicio + interval '6 days';

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
