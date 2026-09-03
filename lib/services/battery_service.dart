import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';

/// Regra de negócio (2026-09-03, mesmo padrão do iFood): entregador com
/// bateria abaixo de [limiteMinimo]% não pode ficar/permanecer "Disponível".
///
/// Duas fontes distintas de propósito:
/// 1. [nivelAtual] (battery_plus) — leitura pontual (Future), usada só no
///    momento em que o entregador TENTA ficar disponível (checagem única,
///    não precisa de stream pra isso).
/// 2. [onLevelChanged] (EventChannel nativo, MainActivity.kt) — stream
///    contínua enquanto já está online, baseada direto no broadcast
///    ACTION_BATTERY_CHANGED do Android. NÃO uso o
///    `Battery().onBatteryStateChanged` do battery_plus pra isso de
///    propósito: aquele stream só dispara em mudança de ESTADO de carga
///    (carregando/descarregando/cheio), não em mudança de NÍVEL (%) — um
///    entregador descarregando normalmente de 16% pra 14% sem nunca
///    conectar o carregador não dispararia esse stream nenhuma vez.
///    ACTION_BATTERY_CHANGED, por outro lado, é emitido pelo Android a
///    cada mudança de nível (1 em 1%). Delay inerente, não contornável por
///    nenhum mecanismo de app: o hardware/driver da bateria (fuel gauge)
///    só reporta em passos de 1% inteiro, tipicamente atualizado pelo
///    kernel a cada ~30-60s — o app fica sabendo assim que o Android fica
///    sabendo, não antes.
class BatteryService {
  static const int limiteMinimo = 15;

  static final Battery _battery = Battery();
  static const EventChannel _levelChannel = EventChannel('letsgo/battery_level');
  static Stream<int>? _levelStream;

  /// Leitura pontual do nível atual (0-100). Null se falhar (aparelho sem
  /// suporte, erro de plataforma) — chamador deve tratar null como "não
  /// bloqueia" (não faz sentido impedir o entregador de trabalhar por causa
  /// de uma falha de leitura, não da bateria em si).
  static Future<int?> nivelAtual() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  static Stream<int> get onLevelChanged {
    _levelStream ??= _levelChannel
        .receiveBroadcastStream()
        .map((e) => e is int ? e : int.tryParse(e.toString()) ?? -1)
        .where((v) => v >= 0);
    return _levelStream!;
  }
}
