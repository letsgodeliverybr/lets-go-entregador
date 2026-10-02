// Diárias (Entrega Dedicada) no "valor do dia" da Home e no Extrato
// (2026-09-30). A diária finalizada vira um lançamento em
// creditos_entregadores com vaga_id preenchido (gatilho
// tg_credito_diaria_finalizada, migrations/credito_diaria_finalizada.sql do
// painel): tipo 'credito' "Diária Finalizada - <loja>" e, se a vaga for
// cancelada depois, tipo 'debito' "Estorno De Diária - <loja>". O saldo
// (calcularSaldoSemana) já somava creditos_entregadores — aqui é só a
// exibição no dia e no extrato. Créditos manuais (vaga_id nulo) ficam de
// fora daqui, como antes.

/// Valor líquido de um lançamento de diária: crédito soma, estorno subtrai.
double valorDiaria(Map<String, dynamic> c) {
  final v = (c['valor'] as num?)?.toDouble() ?? 0;
  return c['tipo'] == 'debito' ? -v : v;
}

/// Soma líquida das diárias (créditos menos estornos).
double somaDiarias(Iterable<Map<String, dynamic>> lancamentos) =>
    lancamentos.fold(0, (s, c) => s + valorDiaria(c));

/// 'AAAA-MM-DD' da data local, no formato da coluna `data` (date).
String dataIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Item do extrato: pedido ou diária, com o que a lista precisa pra ordenar
/// e exibir no mesmo padrão.
class ItemExtrato {
  final bool ehDiaria;
  final DateTime? quando;
  final double valor;
  final Map<String, dynamic> dados;
  const ItemExtrato({required this.ehDiaria, required this.quando, required this.valor, required this.dados});
}

/// Junta pedidos e diárias em uma lista só, mais recente primeiro.
/// [valorPedido] e [quandoPedido] vêm da tela (mesma regra de antes).
List<ItemExtrato> juntarExtrato(
  List<Map<String, dynamic>> pedidos,
  List<Map<String, dynamic>> diarias,
  double Function(Map<String, dynamic>) valorPedido,
  DateTime? Function(Map<String, dynamic>) quandoPedido,
) {
  final itens = <ItemExtrato>[
    for (final p in pedidos) ItemExtrato(ehDiaria: false, quando: quandoPedido(p), valor: valorPedido(p), dados: p),
    for (final c in diarias)
      ItemExtrato(
        ehDiaria: true,
        // created_at é timestamptz (UTC) → hora local do aparelho
        quando: DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal(),
        valor: valorDiaria(c),
        dados: c,
      ),
  ];
  itens.sort((a, b) => (b.quando ?? DateTime(0)).compareTo(a.quando ?? DateTime(0)));
  return itens;
}
