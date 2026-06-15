import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<double> calcularSaldoSemana(SupabaseClient supabase, String uid) async {
  // weekday: Dart retorna 1=segunda, 2=terça, ..., 7=domingo
  final agora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
  final diasDesdeSegunda = agora.weekday == 1 ? 0 : agora.weekday - 1;
  final diaSegunda = agora.day - diasDesdeSegunda;
  final inicioSemanaUtc = DateTime.utc(agora.year, agora.month, diaSegunda, 0, 1, 0)
      .add(const Duration(hours: 3));
  final fimSemanaUtc = DateTime.utc(agora.year, agora.month, diaSegunda + 6, 23, 59, 0)
      .add(const Duration(hours: 3));
  final inicioSemana = inicioSemanaUtc.toIso8601String();
  final fimSemana = fimSemanaUtc.toIso8601String();

  debugPrint('[SEMANA] query: pedidos WHERE motoboy_id=$uid AND status=finalizado AND finalizado_em >= $inicioSemana AND finalizado_em <= $fimSemana');

  final results = await Future.wait<dynamic>([
    supabase
        .from('pedidos')
        .select('id,finalizado_em,taxa_motoboy,gorjeta')
        .eq('motoboy_id', uid)
        .eq('status', 'finalizado')
        .gte('finalizado_em', inicioSemana)
        .lte('finalizado_em', fimSemana),
    supabase
        .from('saques')
        .select('valor')
        .eq('entregador_id', uid)
        .neq('status', 'cancelado')
        .gte('created_at', inicioSemana)
        .lte('created_at', fimSemana),
  ]);

  final pedidos = List<Map<String, dynamic>>.from(results[0] as List);
  final saques = List<Map<String, dynamic>>.from(results[1] as List);

  debugPrint('[SEMANA] inicio_utc=$inicioSemana fim_utc=$fimSemana weekday=${agora.weekday} pedidos_encontrados=${pedidos.length}');
  for (final p in pedidos) {
    debugPrint('[SEMANA] pedido id=${p['id']} finalizado_em=${p['finalizado_em']} taxa_motoboy=${p['taxa_motoboy']}');
  }

  final totalGanho = pedidos.fold<double>(0, (s, p) {
    final taxa = (p['taxa_motoboy'] as num?)?.toDouble() ?? 0;
    final gorjeta = (p['gorjeta'] as num?)?.toDouble() ?? 0;
    return s + taxa + gorjeta;
  });
  final totalSaques = saques.fold<double>(
      0, (s, p) => s + ((p['valor'] as num?)?.toDouble() ?? 0));
  final saldo = (totalGanho - totalSaques).clamp(0.0, double.infinity);

  debugPrint('[SALDO] ganhos=$totalGanho saques=$totalSaques resultado=$saldo');
  return saldo;
}
