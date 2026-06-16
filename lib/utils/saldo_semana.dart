import 'package:supabase_flutter/supabase_flutter.dart';

Future<double> calcularSaldoSemana() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return 0;

  final now = DateTime.now().toUtc();
  final nowBrasilia = now.subtract(const Duration(hours: 3));
  final weekday = nowBrasilia.weekday;
  final segundaBrasilia = nowBrasilia.subtract(Duration(days: weekday - 1));
  final inicio = DateTime(segundaBrasilia.year, segundaBrasilia.month, segundaBrasilia.day, 0, 1).toUtc();
  final fim = inicio.add(const Duration(days: 6, hours: 23, minutes: 58));

  final pedidos = await Supabase.instance.client
      .from('pedidos')
      .select('taxa_motoboy, gorjeta')
      .eq('motoboy_id', user.id)
      .eq('status', 'finalizado')
      .gte('finalizado_em', inicio.toIso8601String())
      .lte('finalizado_em', fim.toIso8601String());

  final ganhos = (pedidos as List).fold<double>(
      0,
      (s, p) =>
          s +
          ((p['taxa_motoboy'] as num?)?.toDouble() ?? 0) +
          ((p['gorjeta'] as num?)?.toDouble() ?? 0));

  final saques = await Supabase.instance.client
      .from('saques')
      .select('valor')
      .eq('entregador_id', user.id)
      .neq('status', 'cancelado')
      .gte('created_at', inicio.toIso8601String())
      .lte('created_at', fim.toIso8601String());

  final totalSaques = (saques as List).fold<double>(
      0, (s, p) => s + ((p['valor'] as num?)?.toDouble() ?? 0));

  return (ganhos - totalSaques).clamp(0, double.infinity);
}
