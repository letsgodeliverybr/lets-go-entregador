import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Força o volume MÁXIMO (streams de Mídia E Alarme — ver comentário
/// completo em MainActivity.kt) antes de tocar o som de pedido novo/rota
/// nova — DECISÃO DE PRODUTO deliberada, não é bug: mesmo comportamento do
/// app do iFood pra entregadores, ciente das reclamações que esse
/// comportamento já gerou lá (perda de controle sobre o próprio volume do
/// aparelho). Decisão consciente mesmo assim: um entregador que não ouve o
/// pedido chegando (aparelho no silencioso, volume baixo) perde a corrida
/// pro próximo da fila. Não restaura o volume depois — fica no máximo até
/// o usuário abaixar na mão, igual iFood.
///
/// Chamado direto no _firebaseBackgroundHandler (main.dart), antes de
/// mostrar a notificação de pedido/rota — cobre o stream de Alarme, único
/// som do fluxo de pedido hoje (a tela Disponíveis em foreground não toca
/// som próprio nenhum, decisão de produto — ver comentário em main.dart).
/// Continua forçando os dois streams (Mídia E Alarme) mesmo assim — não
/// custa nada forçar um stream que não está em uso agora, e cobre de graça
/// qualquer som futuro que volte a usar o stream de Mídia.
///
/// Implementação real é nativa (Kotlin, MainActivity.kt) — AudioManager não
/// tem equivalente nos pacotes Flutter já usados neste projeto
/// (just_audio/flutter_local_notifications só mexem em volume relativo do
/// próprio player, nunca no volume do stream do sistema). Precisa da
/// permissão MODIFY_AUDIO_SETTINGS no AndroidManifest.xml — sem ela,
/// setStreamVolume() falha em silêncio (era a causa raiz real de o volume
/// não subir num teste anterior).
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
