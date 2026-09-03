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
/// Chamado de 3 pontos: _firebaseBackgroundHandler (main.dart, app
/// background/morto) e os 2 branches de FirebaseMessaging.onMessage
/// (notification_service.dart, app em foreground) — achado em auditoria
/// (2026-09-03): o caminho de foreground nunca chamava isso, só o de
/// background. AudioAttributesUsage.alarm (canal) sozinho decide QUAL
/// stream toca, não força o volume DAQUELE stream — sem essa chamada, um
/// usuário com o volume de alarme abaixado manualmente ouviria o alerta
/// insistente nesse volume baixo, mesmo com o canal certo. Continua
/// forçando os dois streams (Mídia E Alarme) mesmo assim — não custa nada
/// forçar um stream que não está em uso agora, e cobre de graça qualquer
/// som futuro que volte a usar o stream de Mídia.
///
/// Dúvida em aberto, nunca confirmada ao vivo (mesma incerteza documentada
/// no catch abaixo): a chamada de dentro do _firebaseBackgroundHandler
/// depende do MethodChannel 'letsgo/volume' estar registrado na engine
/// headless de background — que só é garantidamente registrado na engine
/// da MainActivity. Se não estiver, essa chamada específica (app
/// background/morto) falha em silêncio e SÓ o canal nativo (alarm stream,
/// no volume que já estava) toca — os 2 branches de foreground não têm
/// esse risco, rodam com a MainActivity viva de verdade.
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
