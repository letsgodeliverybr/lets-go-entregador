import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Alerta sonoro de "pedido novo disponível" — nível de APP (singleton), não
// de tela. Antes vivia inteiro dentro de PedidosDisponiveisScreen (um
// AudioPlayer por instância da tela, só tocava com ela montada); virou
// requisito o loop tocar em QUALQUER tela (Home, Aceitos, Vagas...), então
// precisa sobreviver a troca de tela — um State de tela morre no dispose(),
// esse serviço não.
//
// Contrato (pedido do usuário, 2026-09-02):
// 1. Vibração + som de moeda (isso já é a notificação local, ver
//    notification_service.dart) + início do loop disparam JUNTOS, não
//    sequencial — por isso iniciar() é chamado direto de onde a notificação
//    chega (foreground: junto com showNovoPedidoLocal(); cold-start via
//    fullScreenIntent: assim que o app está de fato vivo, no AuthGate), não
//    esperando a tela Disponíveis montar e buscar dado pra só então tocar.
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

  // Requisito 1 (vibra + moeda + loop juntos) e 3 (só 1 por vez): chamar
  // direto de onde a notificação chega. Sem await bloqueante no vibrar —
  // dispara e já segue pro áudio, os dois ficam praticamente simultâneos.
  Future<void> iniciar() async {
    if (_tocando) return; // trava do "só 1 loop por vez"
    _tocando = true;
    HapticFeedback.heavyImpact();
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
