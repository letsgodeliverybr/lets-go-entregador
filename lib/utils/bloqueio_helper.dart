import 'package:supabase_flutter/supabase_flutter.dart';

// Bloqueio de entregador por loja — definido no painel (Editar Loja →
// "Entregador bloqueado"), tabela loja_entregadores_bloqueados (ver
// migrations/bloqueio_entregador_por_loja.sql no repo do painel). Pedido de
// loja que bloqueou o entregador logado não aparece em Disponíveis.
//
// A trava de verdade é no banco (gatilho recusa o aceite e a oferta); aqui é
// só pra não mostrar o que ele não pode pegar e dar a mensagem certa. RLS da
// tabela: o entregador só enxerga as próprias linhas.
//
// Mesmo padrão de cla_helper.dart: recarrega a cada busca (o bloqueio pode
// mudar com o app aberto) e, se a consulta falhar, mantém o último estado.
Set<String> _lojasBloqueadas = {};

Future<void> carregarBloqueios() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    _lojasBloqueadas = {};
    return;
  }
  try {
    final rows = await Supabase.instance.client
        .from('loja_entregadores_bloqueados')
        .select('loja_id')
        .eq('entregador_id', user.id);
    _lojasBloqueadas = lojasDeLinhas(List<Map<String, dynamic>>.from(rows));
  } catch (_) {
    // mantém o último estado conhecido
  }
}

Set<String> lojasDeLinhas(List<Map<String, dynamic>> rows) =>
    {for (final r in rows) if (r['loja_id'] != null) r['loja_id'].toString()};

/// true = entregador logado pode ver/aceitar pedido dessa loja.
bool pedidoPermitido(String? lojaId) => lojaPermitida(lojaId, _lojasBloqueadas);

bool lojaPermitida(String? lojaId, Set<String> bloqueadas) =>
    lojaId == null || lojaId.isEmpty || !bloqueadas.contains(lojaId);

const mensagemBloqueado = 'Você não pode aceitar pedidos desta loja.';

/// Erro do banco quando o gatilho recusa (tg_00_bloqueio_loja_pedido).
bool erroDeBloqueio(Object e) => e.toString().contains('ENTREGADOR_BLOQUEADO_NA_LOJA');

/// Texto do SnackBar de erro no aceite: mensagem amigável se foi bloqueio.
String mensagemErroAceite(Object e, String padrao) => erroDeBloqueio(e) ? mensagemBloqueado : padrao;
