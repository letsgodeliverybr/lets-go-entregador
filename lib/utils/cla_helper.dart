import 'package:supabase_flutter/supabase_flutter.dart';

// Exclusividade de clã — grupo loja(s)+entregador(es) por cidade, gerenciado
// no painel web (Ranking Entregador > Clãs, ver
// migrations/add_clas_entregador.sql no repo do painel). Regra: pedido de
// uma loja que pertence a um clã só é elegível pra entregadores do MESMO
// clã. Loja sem clã (a maioria hoje): sem restrição nenhuma, comportamento
// igual a antes de clãs existirem.
//
// Sem cache permanente de propósito (diferente de taxa_helper.carregarFaixas,
// que carrega uma vez e nunca muda em runtime): clã é editado pelo admin a
// qualquer momento enquanto o app já está aberto, e a mudança precisa valer
// pro próximo pedido que aparecer, não só depois de reabrir o app.
Map<String, String> _lojaClaMap = {};
String? _meuClaId;

Future<void> carregarCla() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    _meuClaId = null;
    _lojaClaMap = {};
    return;
  }
  try {
    final meuVinculo = await Supabase.instance.client
        .from('clas_entregadores')
        .select('cla_id')
        .eq('entregador_id', user.id)
        .maybeSingle();
    _meuClaId = meuVinculo?['cla_id']?.toString();

    final lojasDeClas = await Supabase.instance.client
        .from('clas_lojas')
        .select('loja_id, cla_id');
    _lojaClaMap = {
      for (final row in List<Map<String, dynamic>>.from(lojasDeClas))
        row['loja_id'].toString(): row['cla_id'].toString(),
    };
  } catch (_) {
    // Falha ao carregar: mantém o último estado conhecido (fail-safe pro
    // lado de "não bloquear indevidamente" — melhor mostrar demais numa
    // falha de rede rara do que travar a tela de pedidos disponíveis).
  }
}

// true = pedido elegível pro entregador logado agora.
bool pedidoElegivelParaMeuCla(String? lojaId) {
  if (lojaId == null || lojaId.isEmpty) return true;
  final claDaLoja = _lojaClaMap[lojaId];
  if (claDaLoja == null) return true; // loja não está em nenhum clã
  return claDaLoja == _meuClaId;
}
