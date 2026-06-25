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

  final inicio = DateTime(segundaBrasilia.year, segundaBrasilia.month, segundaBrasilia.day, 0, 1).toUtc();
  final fim = inicio.add(const Duration(days: 6, hours: 23, minutes: 58));

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

  final saquesCorretos = await Supabase.instance.client
      .from('saques')
      .select('valor, data_inicio, data_fim')
      .eq('entregador_id', user.id)
      .inFilter('status', ['pago', 'pendente'])
      .lte('data_inicio', fimData)
      .gt('data_fim', inicioData);

  final listaSaquesCorretos = saquesCorretos as List<dynamic>;
  final totalSaques = listaSaquesCorretos.fold<double>(
      0, (s, p) => s + ((p['valor'] as num?)?.toDouble() ?? 0));

  final creditos = await Supabase.instance.client
      .from('creditos_entregadores')
      .select('tipo, valor')
      .eq('entregador_id', user.id)
      .gte('data', inicioData)
      .lte('data', fimData);

  final listaCreditos = creditos as List<dynamic>;
  double totalCreditos = 0;
  double totalDebitos = 0;
  for (final c in listaCreditos) {
    final v = (c['valor'] as num?)?.toDouble() ?? 0;
    if (c['tipo'] == 'credito') {
      totalCreditos += v;
    } else if (c['tipo'] == 'debito') {
      totalDebitos += v;
    }
  }

  final saldoFinal = (ganhos - totalSaques + totalCreditos - totalDebitos).clamp(0.0, double.infinity);

  debugPrint('[SALDO_SEMANA] periodo=$inicioData a $fimData');
  debugPrint('[SALDO_SEMANA] ganhos=$ganhos saques=$totalSaques creditos=$totalCreditos debitos=$totalDebitos saldo=$saldoFinal');

  return saldoFinal;
}
