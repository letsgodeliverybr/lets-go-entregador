import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Alerta sonoro de "pedido novo disponível" — nível de APP (singleton), não
// de tela. Antes vivia inteiro dentro de PedidosDisponiveisScreen (um
// AudioPlayer por instância da tela, só tocava com ela montada); virou
// requisito o loop tocar em QUALQUER tela (Home, Aceitos, Vagas...), então
// precisa sobreviver a troca de tela — um State de tela morre no dispose(),
// esse serviço não.
//
// Contrato (pedido do usuário, 2026-09-02, redesenhado 2026-09-03):
// 1. Vibração + moeda caindo 5x (efeito "alerta chegando") ficaram por
//    conta do CANAL nativo da notificação (moeda_caindo_5x, ver
//    notification_service.dart v7) — não mais tocadas aqui via just_audio.
//    Motivo: just_audio não tem garantia de funcionar de forma confiável
//    no isolate de background do FCM (suspeito nº1 pro bug "vibração/moeda
//    não tocam na chegada, só ao tocar na notificação" — achado em
//    auditoria 2026-09-03); o canal, por outro lado, é o mecanismo já
//    comprovado (é o que mostra a notificação em si, com fullScreenIntent
//    funcionando, em qualquer estado do app). iniciar() agora só cuida do
//    loop contínuo do Let's Go, disparado direto de onde o isolate
//    principal já está de verdade rodando (onMessage em foreground,
//    onDidReceiveNotificationResponse com app pausado, AuthGate no cold
//    start) — sem repetir a moeda, que já tocou via canal no momento da
//    chegada, evitando qualquer sobreposição entre os dois mecanismos.
// 2. Toca em qualquer tela — por isso é um singleton global, não algo preso
//    ao ciclo de vida de PedidosDisponiveisScreen.
// 3. Só 1 loop por vez — iniciar() é no-op se _tocando já for true. Um
//    segundo pedido chegando antes do primeiro ser aceito NÃO reinicia nem
//    sobrepõe o player, só mantém o que já está tocando.
// 4. Para quando aceita QUALQUER pedido (chamado direto do fluxo de
//    aceite) OU quando não sobra mais pedido 'aguardando' pra esse
//    entregador — coberto por uma assinatura realtime PRÓPRIA em
//    despacho_fila (independente de qualquer tela estar montada), senão o
//    loop nunca pararia sozinho se o último pedido expirasse/fosse pego
//    por outro entregador enquanto o app está noutra tela.
class AlertaPedidoService {
  AlertaPedidoService._();
  static final AlertaPedidoService instance = AlertaPedidoService._();

  final AudioPlayer _player = AudioPlayer();
  bool _tocando = false;
  RealtimeChannel? _channel;
  String? _entregadorId;

  bool get tocando => _tocando;

  // Chamado no AuthGate toda vez que resolve a tela pra uma sessão válida —
  // idempotente (não recria a assinatura se já for o mesmo entregador),
  // então é seguro chamar de novo a cada cold start/retomada sem custo.
  Future<void> escutar(String entregadorId) async {
    if (_entregadorId == entregadorId && _channel != null) return;
    await pararEscuta();
    _entregadorId = entregadorId;
    try {
      _channel = Supabase.instance.client
          .channel('alerta-pedido-$entregadorId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'despacho_fila',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'entregador_id',
              value: entregadorId,
            ),
            callback: (_) => _reavaliarSeDeveContinuar(),
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> pararEscuta() async {
    try { await _channel?.unsubscribe(); } catch (_) {}
    _channel = null;
    _entregadorId = null;
  }

  // Requisito 4, metade "não sobra mais pedido disponível": qualquer
  // mudança em despacho_fila pra esse entregador reavalia do zero se ainda
  // existe alguma linha 'aguardando' — se não existir mais nenhuma, para o
  // loop, não importa em qual tela o entregador estiver.
  Future<void> _reavaliarSeDeveContinuar() async {
    if (!_tocando || _entregadorId == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('despacho_fila')
          .select('id')
          .eq('entregador_id', _entregadorId!)
          .eq('status', 'aguardando')
          .limit(1);
      if (rows.isEmpty) await parar();
    } catch (_) {}
  }

  // Requisito 3 (só 1 por vez): chamar direto de onde a notificação chega
  // ou o app abre por causa dela. _tocando marcado de forma SÍNCRONA antes
  // de qualquer await — garante que uma segunda chamada concorrente (2º
  // pedido chegando antes do 1º ser aceito) vê a flag já true e não inicia
  // um segundo player por cima.
  //
  // Sem moeda repetida aqui desde 2026-09-03 — isso já tocou via canal da
  // notificação (moeda_caindo_5x) no momento em que ela chegou, antes
  // desse método ser chamado. Só entra direto no loop contínuo.
  Future<void> iniciar() async {
    if (_tocando) return; // trava do "só 1 loop por vez"
    _tocando = true;
    try {
      await _player.setLoopMode(LoopMode.one);
      await _player.setAsset('assets/sounds/letsgo.wav');
      await _player.play();
    } catch (_) {
      _tocando = false;
    }
  }

  Future<void> parar() async {
    if (!_tocando) return;
    _tocando = false;
    try { await _player.stop(); } catch (_) {}
  }
}
