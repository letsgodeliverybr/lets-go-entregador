import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tracking_service.dart';

// Logout forçado semanal (toda segunda 03:30 Brasília) — pedido do
// usuário pra todo entregador reentrar com usuário/senha no início da
// semana. Mesma lógica já implementada no painel (app.js,
// _ultimaSegunda0330BrasiliaMs), traduzida pra Dart — Brasil não tem mais
// horário de verão (abolido em 2019), então -03:00 fixo é seguro o ano
// inteiro, sem precisar do pacote `timezone`.
//
// Diferente do painel (sessionStorage, sem sessão real no servidor), aqui
// a sessão É real (Supabase Auth) — o timestamp de login fica em
// SharedPreferences (sobrevive a fechar/reabrir o app, do jeito que a
// própria sessão do Supabase também sobrevive) e é gravado só no
// signInWithPassword() bem-sucedido (login_screen.dart), nunca na
// restauração automática de sessão do cold start.

const _chaveLoginEm = 'lg_login_em_ms';

// Race real corrigida 2026-09-12: registrarLoginAgora() faz `await`
// (SharedPreferences.getInstance()/setInt() são assíncronos, round-trip
// de platform channel) — nesse intervalo, o Timer.periodic(60s) ou um
// didChangeAppLifecycleState(resumed) de main.dart podiam rodar
// checarLogoutSemanal() vendo currentSession já válido (signInWithPassword
// já retornou) mas lg_login_em ainda não persistido, lendo "sem login
// registrado" → tratado como expirado → deslogava um login que acabou de
// acontecer. Setada de forma SÍNCRONA (sem await antes) assim que o login
// dá certo, então não existe brecha pro event loop intercalar outra
// checagem antes dela virar true.
bool _loginEmAndamento = false;

// Lista mais ampla de status "em andamento" usada no app (ver
// tracking_service.dart/chat_bot_screen.dart) — inclui chegou_destino e
// retornando além do conjunto usado em entregador_home_screen.dart, de
// propósito: mais abrangente é mais seguro aqui (evita deslogar cedo
// demais no meio de uma etapa tardia da entrega).
const _statusAtivos = [
  'aceito',
  'no_local',
  'chegou_local',
  'em_rota',
  'chegou_destino',
  'retornando',
];

Future<void> registrarLoginAgora() async {
  _loginEmAndamento = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _chaveLoginEm, DateTime.now().toUtc().millisecondsSinceEpoch);
  } finally {
    _loginEmAndamento = false;
  }
}

Future<void> _limparLoginRegistrado() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_chaveLoginEm);
}

/// Epoch (instante UTC real) da última segunda 03:30 Brasília já passada.
DateTime ultimaSegunda0330Brasilia([DateTime? agoraUtc]) {
  final agora = agoraUtc ?? DateTime.now().toUtc();
  final brasilia = agora.subtract(const Duration(hours: 3));
  final diasDesdeSegunda = brasilia.weekday - 1; // segunda=0 ... domingo=6
  final segundaBrasilia = DateTime.utc(
      brasilia.year, brasilia.month, brasilia.day - diasDesdeSegunda, 3, 30);
  var corte = segundaBrasilia.add(const Duration(hours: 3));
  if (corte.isAfter(agora)) corte = corte.subtract(const Duration(days: 7));
  return corte;
}

Future<bool> _loginExpirou() async {
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt(_chaveLoginEm);
  // Sem timestamp registrado (sessão de antes desse recurso existir, ou
  // sessão restaurada nesse device sem nunca ter passado por
  // signInWithPassword) conta como expirado de propósito — mesmo critério
  // já usado no painel, desloga uma vez.
  if (ms == null) return true;
  final loginEm = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return loginEm.isBefore(ultimaSegunda0330Brasilia());
}

// Pública (2026-09-11) — também usada pelo bloqueio de LOGOUT MANUAL com
// entrega ativa (entregador_home_screen.dart/home_screen.dart), não só
// pelo logout semanal. Fonte única: TrackingService.ficarOffline() tinha
// sua própria checagem (só motoboy_id, sem entregador_id, e sem
// chegou_destino), que deixava passar o logout sem aviso quando o pedido
// estava alocado pela coluna entregador_id — daí reaproveitar essa aqui
// em vez de confiar na checagem antiga.
Future<bool> temEntregaAtiva(String userId) async {
  try {
    final data = await Supabase.instance.client
        .from('pedidos')
        .select('id')
        .or('motoboy_id.eq.$userId,entregador_id.eq.$userId')
        .inFilter('status', _statusAtivos)
        .limit(1);
    return data.isNotEmpty;
  } catch (_) {
    // Falha de rede/consulta: não força logout às cegas sem saber se tem
    // entrega ativa — mais seguro tentar de novo no próximo tick (60s) do
    // que arriscar interromper uma corrida por causa de um erro
    // transitório de conexão.
    return true;
  }
}

/// Fallback quando não dá pra saber o limite configurado da loja (sem
/// loja_id no pedido, ou falha ao consultar) — mesmo valor padrão da
/// coluna lojas.limite_pedidos_simultaneos. Alocação manual pelo admin
/// tem um teto separado e fixo (4), aplicado do lado do painel.
const limitePedidosAceiteSozinho = 2;

/// Conta quantos pedidos ativos (entre aceito e finalizado) esse
/// entregador já tem agora — usado pra travar um novo aceite sozinho.
/// [lojaId], quando informado, restringe a contagem só aos pedidos
/// DAQUELA loja (2026-09-24: o limite passou a ser por loja, não geral —
/// um entregador pode ter 2 da Loja A e mais 2 da Loja B ao mesmo tempo,
/// por exemplo, sem violar o limite de nenhuma das duas).
Future<int> contarEntregasAtivas(String userId, {String? lojaId}) async {
  final query = Supabase.instance.client
      .from('pedidos')
      .select('id')
      .or('motoboy_id.eq.$userId,entregador_id.eq.$userId')
      .inFilter('status', _statusAtivos);
  final data = await (lojaId != null ? query.eq('loja_id', lojaId) : query);
  return data.length;
}

/// Limite configurado da loja (lojas.limite_pedidos_simultaneos) pro
/// aceite sozinho — [limitePedidosAceiteSozinho] se a loja não tiver
/// (não deveria acontecer, coluna tem default 2) ou a consulta falhar.
Future<int> limitePedidosLoja(String? lojaId) async {
  if (lojaId == null) return limitePedidosAceiteSozinho;
  try {
    final data = await Supabase.instance.client
        .from('lojas')
        .select('limite_pedidos_simultaneos')
        .eq('id', lojaId)
        .maybeSingle();
    return (data?['limite_pedidos_simultaneos'] as num?)?.toInt() ??
        limitePedidosAceiteSozinho;
  } catch (_) {
    return limitePedidosAceiteSozinho;
  }
}

/// Checa o corte semanal e desloga se aplicável. Não desloga com entrega
/// ativa — só adia (reavaliado a cada chamada seguinte), deslogando
/// automaticamente assim que o entregador ficar livre. Retorna true só
/// quando de fato deslogou (o chamador deve navegar pra LoginScreen).
Future<bool> checarLogoutSemanal() async {
  if (_loginEmAndamento) return false;
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return false;
  if (!await _loginExpirou()) return false;
  if (await temEntregaAtiva(session.user.id)) return false;
  // Gap real corrigido 2026-09-11: sem isso, o entregador continuava
  // aparecendo ONLINE no Mapa ao Vivo do painel depois do logout forçado
  // (signOut() só derruba a sessão local, não marca disponivel:false no
  // banco) — mesmo efeito colateral que TrackingService.ficarOffline()
  // já produz pro botão manual de logout/toggle offline, reaproveitado
  // aqui pra herdar o comportamento que o painel já tem hoje pra qualquer
  // entregador offline, sem precisar de lógica nova lá.
  try {
    await TrackingService.ficarOffline(session.user.id);
  } catch (_) {}
  await Supabase.instance.client.auth.signOut();
  await _limparLoginRegistrado();
  return true;
}
