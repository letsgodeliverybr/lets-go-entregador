-- 5º documento obrigatório do cadastro: foto da placa da moto/veículo.
-- Mesmo bucket privado e mesma RLS por pasta de documentos-entregador
-- (20260721140000_documentos_entregador.sql) já cobrem qualquer tipo novo
-- sob {uid}/*; só falta a coluna pra guardar o path.
alter table public.entregadores
  add column if not exists foto_placa text;
