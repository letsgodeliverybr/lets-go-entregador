import 'package:supabase_flutter/supabase_flutter.dart';

// Fonte única do cálculo de "Entregador Premium" (2026-09-10) — usada tanto
// pelo card "Entregador Premium" da tela Home quanto pelo selo no menu
// lateral (drawer_screen.dart), pra nunca divergir. Investigado antes de
// criar: não existe hoje nenhuma tabela/coluna/flag de "premium" no banco
// (o sistema de "clã" é outro assunto, exclusividade de despacho por
// cidade) — o status é 100% calculado a partir de pedidos finalizados,
// sem persistir nada. Ver home_screen.dart pro card com a barra de
// progresso completa.
class PremiumService {
  static const metaEntregas90Dias = 850;

  // Conta pedidos finalizados nos últimos 90 dias corridos — mesma query
  // usada em home_screen.dart._carregarDados() (.or() com motoboy_id e
  // entregador_id porque pedidos antigos podem ter só um dos dois
  // preenchido).
  static Future<int> entregas90Dias(String uid) async {
    final agora = DateTime.now();
    final noventaDiasAtras =
        agora.subtract(const Duration(days: 90)).toIso8601String();
    final data = await Supabase.instance.client
        .from('pedidos')
        .select('id')
        .or('motoboy_id.eq.$uid,entregador_id.eq.$uid')
        .eq('status', 'finalizado')
        .gte('finalizado_em', noventaDiasAtras);
    return List<Map<String, dynamic>>.from(data).length;
  }

  static bool isPremium(int entregas90Dias) =>
      entregas90Dias >= metaEntregas90Dias;
}
