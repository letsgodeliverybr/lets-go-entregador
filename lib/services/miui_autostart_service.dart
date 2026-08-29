import 'package:flutter/services.dart';

/// Detecção de Xiaomi/MIUI + atalho pra tela de "Início automático" nativa
/// da Xiaomi (Settings.ACTION_* padrão do Android não cobre isso — é
/// recurso próprio do gerenciador de bateria da MIUI, sem API pública).
///
/// Sem essa permissão concedida manualmente pelo usuário, a MIUI mata o
/// processo do app agressivamente assim que ele sai de primeiro plano —
/// nenhuma notificação de novo pedido consegue tocar som depois disso,
/// mesmo com canal/payload/FCM tudo correto (confirmado em campo:
/// Redmi 4 Pro, notificação chegando muda mesmo após canal recriado do
/// zero via reinstall).
class MiuiAutostartService {
  static const _channel = MethodChannel('letsgo/miui_autostart');

  /// true se o aparelho for Xiaomi (checa manufacturer E brand, já que
  /// sub-marcas como Redmi/POCO variam qual campo usam pra se identificar).
  static Future<bool> isXiaomi() async {
    try {
      final manufacturer =
          (await _channel.invokeMethod<String>('getManufacturer') ?? '')
              .toLowerCase();
      final brand = (await _channel.invokeMethod<String>('getBrand') ?? '')
          .toLowerCase();
      return manufacturer.contains('xiaomi') || brand.contains('xiaomi');
    } catch (_) {
      return false;
    }
  }

  /// Abre a tela de gerenciamento de autoinício da MIUI. Sem retorno de
  /// estado do SO pra essa tela (diferente de DND/fullscreen intent) — por
  /// isso a confirmação de que foi ativado é manual (checkbox), não
  /// reconferida automaticamente.
  static Future<void> openAutostartSettings() async {
    try {
      await _channel.invokeMethod('openAutostartSettings');
    } catch (_) {}
  }
}
