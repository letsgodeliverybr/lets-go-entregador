import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<double> calcularSaldoSemana(SupabaseClient supabase, String uid) async {
  final now = DateTime.now();
  final diasDesdeSegunda = now.weekday == 1 ? 0 : now.weekday - 1;
  final inicioSemanaLocal = DateTime(now.year, now.month, now.day - diasDesdeSegunda);
  debugPrint('[SEMANA] inicio_local=${inicioSemanaLocal.toIso8601String()} weekday=${now.weekday}');

  final results = await Future.wait<dynamic>([
    supabase
        .from('pedidos')
        .select('id,taxa_motoboy,gorjeta,updated_at')
        .eq('motoboy_id', uid)
        .eq('status', 'finalizado')
        .gte('updated_at', inicioSemanaLocal.toIso8601String()),
    supabase
        .from('saques')
        .select('valor')
        .eq('entregador_id', uid)
        .neq('status', 'cancelado')
        .gte('created_at', inicioSemanaLocal.toIso8601String()),
  ]);

  final pedidos = List<Map<String, dynamic>>.from(results[0] as List);
  final saques = List<Map<String, dynamic>>.from(results[1] as List);

  debugPrint('[SEMANA] pedidos_encontrados=${pedidos.length}');
  for (final p in pedidos) {
    debugPrint('[SEMANA] pedido id=${p['id']} updated_at=${p['updated_at']} taxa_motoboy=${p['taxa_motoboy']}');
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
