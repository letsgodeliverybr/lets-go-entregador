import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Força o volume de MÍDIA (STREAM_MUSIC) pro máximo antes de tocar o som
/// de pedido novo/rota nova — DECISÃO DE PRODUTO deliberada, não é bug:
/// mesmo comportamento do app do iFood pra entregadores, ciente das
/// reclamações que esse comportamento já gerou lá (perda de controle sobre
/// o próprio volume do aparelho). Decisão consciente mesmo assim: um
/// entregador que não ouve o pedido chegando (aparelho no silencioso, mídia
/// baixa) perde a corrida pro próximo da fila. Não restaura o volume
/// depois — fica no máximo até o usuário abaixar na mão, igual iFood.
///
/// Implementação real é nativa (Kotlin, MainActivity.kt) — AudioManager não
/// tem equivalente nos pacotes Flutter já usados neste projeto
/// (just_audio/flutter_local_notifications só mexem em volume relativo do
/// próprio player, nunca no volume do stream do sistema).
class VolumeService {
  static const MethodChannel _channel = MethodChannel('letsgo/volume');

  static Future<void> forcarVolumeMidiaMaximo() async {
    try {
      await _channel.invokeMethod('forcarVolumeMidiaMaximo');
    } catch (e) {
      // Canal nativo é registrado só na engine da MainActivity — pode não
      // estar disponível numa engine headless de background criada sem
      // passar por ali (nunca confirmado se acontece de verdade neste app;
      // mesmo dúvida que outros canais MethodChannel deste projeto). Nunca
      // deixar isso derrubar o resto do fluxo de som/notificação por causa
      // disso — pior caso, o volume simplesmente não sobe sozinho.
      debugPrint('[VolumeService] falhou ao forçar volume de mídia: $e');
    }
  }
}
