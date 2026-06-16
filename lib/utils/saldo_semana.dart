import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<double> calcularSaldoSemana() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return 0;

  final now = DateTime.now().toUtc();
  final nowBrasilia = now.subtract(const Duration(hours: 3));
  final weekday = nowBrasilia.weekday;
  final segundaBrasilia = nowBrasilia.subtract(Duration(days: weekday - 1));
  final domingoBrasilia = segundaBrasilia.add(const Duration(days: 6));

  // Timestamps UTC para filtrar pedidos por finalizado_em
  final inicio = DateTime(segundaBrasilia.year, segundaBrasilia.month, segundaBrasilia.day, 0, 1).toUtc();
  final fim = inicio.add(const Duration(days: 6, hours: 23, minutes: 58));

  // Datas no formato YYYY-MM-DD para comparar com data_inicio/data_fim dos saques
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final inicioData = fmt(segundaBrasilia);
  final fimData = fmt(domingoBrasilia);

  final pedidos = await Supabase.instance.client
      .from('pedidos')
      .select('taxa_motoboy, gorjeta')
      .eq('motoboy_id', user.id)
      .eq('status', 'finalizado')
      .gte('finalizado_em', inicio.toIso8601String())
      .lte('finalizado_em', fim.toIso8601String());

  final ganhos = (pedidos as List<dynamic>).fold<double>(
      0,
      (s, p) =>
          s +
          ((p['taxa_motoboy'] as num?)?.toDouble() ?? 0) +
          ((p['gorjeta'] as num?)?.toDouble() ?? 0));

  // Filtra saques pelo PERÍODO que cobrem (data_inicio/data_fim), não pelo
  // created_at — evita incluir saques de semanas anteriores criados nessa semana.
  // Condição de sobreposição: data_inicio <= fim_semana AND data_fim >= inicio_semana
  final saquesCorretos = await Supabase.instance.client
      .from('saques')
      .select('valor, data_inicio, data_fim')
      .eq('entregador_id', user.id)
      .neq('status', 'cancelado')
      .lte('data_inicio', fimData)
      .gte('data_fim', inicioData);

  final listaSaquesCorretos = saquesCorretos as List<dynamic>;
  final totalSaques = listaSaquesCorretos.fold<double>(
      0, (s, p) => s + ((p['valor'] as num?)?.toDouble() ?? 0));

  // Diagnóstico: saques que seriam incluídos pela lógica antiga (created_at
  // dentro da semana) mas têm data_fim antes do início da semana (período errado)
  final saquesAntigos = await Supabase.instance.client
      .from('saques')
      .select('valor, data_inicio, data_fim, created_at')
      .eq('entregador_id', user.id)
      .neq('status', 'cancelado')
      .gte('created_at', inicio.toIso8601String())
      .lte('created_at', fim.toIso8601String());

  final saquesExcluidos = (saquesAntigos as List<dynamic>).where((s) {
    final dataFim = s['data_fim']?.toString() ?? '';
    return dataFim.isNotEmpty && dataFim.compareTo(inicioData) < 0;
  }).toList();
  final totalExcluidos = saquesExcluidos.fold<double>(
      0, (s, p) => s + ((p['valor'] as num?)?.toDouble() ?? 0));

  final saldoFinal = (ganhos - totalSaques).clamp(0.0, double.infinity);

  debugPrint('[SALDO_SEMANA] periodo=$inicioData a $fimData');
  debugPrint('[SALDO_SEMANA] ganhos_semana_atual=$ganhos');
  debugPrint('[SALDO_SEMANA] saques_incluidos=${listaSaquesCorretos.length} total=$totalSaques');
  for (final s in listaSaquesCorretos) {
    debugPrint('[SALDO_SEMANA]   + saque data_inicio=${s['data_inicio']} data_fim=${s['data_fim']} valor=${s['valor']}');
  }
  debugPrint('[SALDO_SEMANA] saques_excluidos_por_periodo_errado=${saquesExcluidos.length} total_excluido=$totalExcluidos');
  for (final s in saquesExcluidos) {
    debugPrint('[SALDO_SEMANA]   x excluido data_inicio=${s['data_inicio']} data_fim=${s['data_fim']} valor=${s['valor']} created_at=${s['created_at']}');
  }
  debugPrint('[SALDO_SEMANA] saldo_final=$saldoFinal');

  return saldoFinal;
}
