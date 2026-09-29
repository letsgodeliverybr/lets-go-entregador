import 'package:supabase_flutter/supabase_flutter.dart';

const _tabelaId = '7bf1cf41-b3f2-4694-b326-d4e830dae8e1';

List<Map<String, dynamic>> faixasGlobais = [];

Future<void> carregarFaixas() async {
  if (faixasGlobais.isNotEmpty) return;
  try {
    final data = await Supabase.instance.client
        .from('tabelas_preco_faixas')
        .select('km_ate, valor_sem_retorno, valor_com_retorno')
        .eq('tabela_id', _tabelaId)
        .order('km_ate', ascending: true);
    faixasGlobais = List<Map<String, dynamic>>.from(data);
  } catch (_) {}
}

double calcularTaxaMotoboy(
  double distanciaKm,
  bool comRetorno,
  List<Map<String, dynamic>> faixas,
) {
  if (faixas.isEmpty) return 0;
  final faixa = faixas.firstWhere(
    (f) => (f['km_ate'] as num).toDouble() >= distanciaKm,
    orElse: () => faixas.last,
  );
  if (comRetorno) {
    return (faixa['valor_com_retorno'] as num).toDouble();
  }
  return (faixa['valor_sem_retorno'] as num).toDouble();
}

// ── Tabela de pagamento POR LOJA (2026-09-29) ──────────────────────────────
// Bug real: o app calculava o valor do entregador sempre pela tabela global
// (_tabelaId acima), ignorando lojas.tabela_pagamento_id — pedido aparecia
// R$ 10,22 e pagava R$ 9,00 (valor da tabela da loja). Mesma classe de bug já
// corrigida no painel em 2026-09-22 (_getFaixasPagamento).
//
// Regra = painel (_valorPagoMotoboyPedido): vale pedidos.taxa_motoboy, gravada
// na criação com a tabela da loja + preço dinâmico + gorjeta. Sem ela, calcula
// pela tabela da loja (com km adicional após a última faixa) e, se a loja não
// tiver tabela própria ou ainda não carregou, pela global.
final Map<String, String?> _tabelaDaLoja = {};
final Map<String, List<Map<String, dynamic>>> _faixasPorTabela = {};
final Map<String, double> _kmAdicionalPorTabela = {};

Future<void> carregarFaixasLojas(Iterable<String?> lojaIds) async {
  await carregarFaixas();
  final novas = lojaIds.whereType<String>().where((id) => id.isNotEmpty && !_tabelaDaLoja.containsKey(id)).toSet();
  if (novas.isEmpty) return;
  try {
    final sb = Supabase.instance.client;
    final lojas = await sb.from('lojas').select('id, tabela_pagamento_id').inFilter('id', novas.toList());
    for (final l in List<Map<String, dynamic>>.from(lojas)) {
      _tabelaDaLoja[l['id'].toString()] = l['tabela_pagamento_id']?.toString();
    }
    final tabelas = _tabelaDaLoja.values.whereType<String>().where((t) => !_faixasPorTabela.containsKey(t)).toSet();
    if (tabelas.isEmpty) return;
    final faixas = await sb.from('tabelas_preco_faixas')
        .select('tabela_id, km_ate, valor_sem_retorno, valor_com_retorno')
        .inFilter('tabela_id', tabelas.toList()).order('km_ate', ascending: true);
    final tabs = await sb.from('tabelas_preco').select('id, km_adicional_valor').inFilter('id', tabelas.toList());
    for (final t in tabelas) {
      _faixasPorTabela[t] = List<Map<String, dynamic>>.from(faixas).where((f) => f['tabela_id'].toString() == t).toList();
    }
    for (final t in List<Map<String, dynamic>>.from(tabs)) {
      _kmAdicionalPorTabela[t['id'].toString()] = double.tryParse(t['km_adicional_valor']?.toString() ?? '') ?? 0;
    }
  } catch (_) {
    // falha de rede: fica com a global pro cálculo de reserva; o valor
    // mostrado continua sendo taxa_motoboy quando o pedido tem.
  }
}

/// Taxa base (sem preço dinâmico e gorjeta) pela tabela da loja.
double calcularPorLoja(String? lojaId, double km, bool comRetorno) {
  final tab = lojaId == null ? null : _tabelaDaLoja[lojaId];
  final faixas = (tab != null ? _faixasPorTabela[tab] : null) ?? const [];
  if (faixas.isEmpty) return calcularTaxaMotoboy(km, comRetorno, faixasGlobais);
  final kmCalc = km > 0 ? km : 1.0;
  var valor = calcularTaxaMotoboy(kmCalc, comRetorno, faixas);
  final kmAdic = _kmAdicionalPorTabela[tab] ?? 0;
  final maxKm = (faixas.last['km_ate'] as num).toDouble();
  if (kmAdic > 0 && kmCalc > maxKm) valor += (kmCalc - maxKm) * kmAdic;
  return valor;
}

/// Valor que o entregador recebe pelo pedido (o mesmo que o painel paga).
double valorEntregador(Map<String, dynamic> p) {
  final salvo = double.tryParse(p['taxa_motoboy']?.toString() ?? '');
  if (salvo != null) return salvo;
  final km = double.tryParse(p['distancia_km']?.toString() ?? '0') ?? 0;
  final retorno = p['com_retorno'] == true || p['retorno'] == true;
  final pd = double.tryParse(p['preco_dinamico']?.toString() ?? '0') ?? 0;
  final gorjeta = double.tryParse(p['gorjeta']?.toString() ?? '0') ?? 0;
  return ((calcularPorLoja(p['loja_id']?.toString(), km, retorno) + pd + gorjeta) * 100).round() / 100;
}

/// Decompõe o valor pra exibir: base da tabela da loja, preço dinâmico
/// (o que sobra acima da base, sem a gorjeta) e o valor sem retorno.
({double total, double base, double pd, double gorjeta, double semRetorno}) detalharValor(Map<String, dynamic> p) {
  final km = double.tryParse(p['distancia_km']?.toString() ?? '0') ?? 0;
  final retorno = p['com_retorno'] == true || p['retorno'] == true;
  final gorjeta = double.tryParse(p['gorjeta']?.toString() ?? '0') ?? 0;
  final lojaId = p['loja_id']?.toString();
  final total = valorEntregador(p);
  final base = calcularPorLoja(lojaId, km, retorno);
  final resto = total - gorjeta - base;
  final pd = resto >= 0.05 ? resto : 0.0;
  final semRetorno = retorno ? total - (base - calcularPorLoja(lojaId, km, false)) : total;
  return (total: total, base: base, pd: pd, gorjeta: gorjeta, semRetorno: semRetorno);
}
