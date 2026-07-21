import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Player compartilhado do som de novo pedido — toca em loop contínuo em
/// qualquer tela do app (não só Disponíveis), enquanto existir pelo menos
/// um pedido/rota disponível pra aceitar. _MyAppState (main.dart) decide
/// quando chamar tocarLoop()/pararLoop() com base no estado real dos
/// pedidos/despacho_fila, não em qual tela está aberta.
class SomPedidoService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _loopAtivo = false;

  static Future<void> tocarLoop() async {
    if (_loopAtivo) return; // já tocando — novo pedido só mantém o loop
    _loopAtivo = true;
    HapticFeedback.heavyImpact();
    try {
      await _player.setLoopMode(LoopMode.one);
      await _player.setAsset('assets/sounds/letsgo_notification.wav');
      await _player.play();
    } catch (_) {
      _loopAtivo = false;
    }
  }

  static Future<void> pararLoop() async {
    if (!_loopAtivo) return;
    _loopAtivo = false;
    try {
      await _player.stop();
      await _player.setLoopMode(LoopMode.off);
    } catch (_) {}
  }
}
