-- Tabela de rotas agrupadas pelo roterizador
CREATE TABLE IF NOT EXISTS rotas_agrupadas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  loja_id uuid REFERENCES lojas(id) ON DELETE SET NULL,
  pedido_ids uuid[],
  valor_total numeric(10,2) DEFAULT 0,
  status text DEFAULT 'pendente',
  created_at timestamptz DEFAULT now()
);

-- Configurações do roterizador por loja
ALTER TABLE lojas ADD COLUMN IF NOT EXISTS roterizador_ativo boolean DEFAULT false;
ALTER TABLE lojas ADD COLUMN IF NOT EXISTS roterizador_tempo_espera_seg integer DEFAULT 120;
ALTER TABLE lojas ADD COLUMN IF NOT EXISTS roterizador_raio_km numeric(6,2) DEFAULT 3.0;

-- FK para rota agrupada nos pedidos e na fila
ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS rota_agrupada_id uuid REFERENCES rotas_agrupadas(id) ON DELETE SET NULL;
ALTER TABLE despacho_fila ADD COLUMN IF NOT EXISTS rota_agrupada_id uuid REFERENCES rotas_agrupadas(id) ON DELETE SET NULL;
