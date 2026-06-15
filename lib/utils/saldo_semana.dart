import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<double> calcularSaldoSemana(SupabaseClient supabase, String uid) async {
  // Horário atual convertido para Brasília (UTC-3)
  final nowUtc = DateTime.now().toUtc();
  final nowBrasilia = nowUtc.subtract(const Duration(hours: 3));

  // Segunda-feira da semana atual às 00:01 no horário de Brasília
  final diasDesdeSegunda = nowBrasilia.weekday == 1 ? 0 : nowBrasilia.weekday - 1;
  final segundaBrasilia = DateTime(
    nowBrasilia.year, nowBrasilia.month, nowBrasilia.day - diasDesdeSegunda,
    0, 1,
  );

  // Domingo da mesma semana às 23:59 no horário de Brasília
  final domingoBrasilia = DateTime(
    segundaBrasilia.year, segundaBrasilia.month, segundaBrasilia.day + 6,
    23, 59,
  );

  // Conversão para UTC (+3h): segunda 00:01 Brasília = segunda 03:01 UTC
  //                            domingo 23:59 Brasília = próxima segunda 02:59 UTC
  final inicioUtc = segundaBrasilia.add(const Duration(hours: 3));
  final fimUtc = domingoBrasilia.add(const Duration(hours: 3));

  debugPrint('[SEMANA] inicio_utc=${inicioUtc.toIso8601String()} fim_utc=${fimUtc.toIso8601String()}');

  final results = await Future.wait<dynamic>([
    supabase
        .from('pedidos')
        .select('id,taxa_motoboy,gorjeta,finalizado_em')
        .eq('motoboy_id', uid)
        .eq('status', 'finalizado')
        .gte('finalizado_em', inicioUtc.toIso8601String())
        .lte('finalizado_em', fimUtc.toIso8601String()),
    supabase
        .from('saques')
        .select('valor')
        .eq('entregador_id', uid)
        .neq('status', 'cancelado')
        .gte('created_at', inicioUtc.toIso8601String())
        .lte('created_at', fimUtc.toIso8601String()),
  ]);

  final pedidos = List<Map<String, dynamic>>.from(results[0] as List);
  final saques = List<Map<String, dynamic>>.from(results[1] as List);

  debugPrint('[SEMANA] pedidos_encontrados=${pedidos.length}');
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
