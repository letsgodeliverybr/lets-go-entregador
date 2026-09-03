import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'battery_service.dart';
import 'location_service.dart';
import 'foreground_service.dart';
import 'notification_service.dart';

class TrackingService {
  static final _supabase = Supabase.instance.client;
  static StreamSubscription<Position>? _sub;
  static StreamSubscription<int>? _batterySub;
  static bool _ativo = false;
  static bool _forcandoOfflinePorBateria = false;
  static Position? _ultimaPosicao;
  static String? _entregadorId;

  /// Lança [Exception] se a bateria estiver abaixo do limite mínimo
  /// (BatteryService.limiteMinimo) — chamado no início de [ficarOnline] E
  /// [iniciar] (não só um dos dois): ambos os fluxos de toggle do app
  /// (entregador_home_screen.dart, online_status_screen.dart) chamam os
  /// dois em sequência, e checar só em um deixaria uma janela onde
  /// `disponivel=true` já foi gravado no banco antes do outro barrar —
  /// estado inconsistente (banco diz disponível, ninguém rastreando de
  /// verdade). nivel==null (falha de leitura) NÃO bloqueia — não faz
  /// sentido impedir o entregador de trabalhar por uma falha de leitura,
  /// não da bateria em si.
  static Future<void> _exigirBateriaOk() async {
    final nivel = await BatteryService.nivelAtual();
    if (nivel != null && nivel < BatteryService.limiteMinimo) {
      throw Exception(
        'Bateria abaixo de ${BatteryService.limiteMinimo}%. '
        'Carregue o celular antes de ficar disponível.',
      );
    }
  }

  static Future<void> iniciar(String entregadorId) async {
    if (_ativo) return;
    await _exigirBateriaOk();
    _ativo = true;
    _entregadorId = entregadorId;

    debugPrint('[TrackingService] ▶ Iniciando rastreamento para $entregadorId');

    WakelockPlus.enable();
    await ForegroundService.iniciar(entregadorId);
    _assinarBateria(entregadorId);

    // 1. Posição inicial imediata
    final posInicial = await LocationService.getCurrentPosition();
    if (posInicial != null) {
      _ultimaPosicao = posInicial;
      await _enviar(entregadorId, posInicial);
    }

    // 2. Stream do GPS — recebe atualizações quando há movimento
    _assinarStream(entregadorId);
    debugPrint('[TrackingService] Stream GPS assinado: $_sub');

    // 3. Loop resiliente: busca posição a cada 8s, se autoreinicia após erro
    _loopEnvio(entregadorId);
  }

  static Future<void> _loopEnvio(String entregadorId) async {
    await Future.delayed(const Duration(seconds: 8));
    if (!_ativo) return;
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        _ultimaPosicao = pos;
        await _enviar(entregadorId, pos);
      } else if (_ultimaPosicao != null) {
        await _enviar(entregadorId, _ultimaPosicao!);
      }
    } catch (e) {
      debugPrint('[TrackingService] ⚠ Erro no loop: $e — reiniciando em 5s');
      await Future.delayed(const Duration(seconds: 5));
    }
    if (_ativo) _loopEnvio(entregadorId);
  }

  // Stream contínua (ACTION_BATTERY_CHANGED nativo, ver BatteryService) —
  // reage assim que o Android informa o nível cruzando o limite, sem
  // esperar nenhum ciclo de verificação próprio. Assinada só enquanto
  // online (chamada em iniciar(), cancelada em parar()) — não faz sentido
  // gastar esse listener com o entregador offline.
  static void _assinarBateria(String entregadorId) {
    _batterySub?.cancel();
    _batterySub = BatteryService.onLevelChanged.listen((nivel) {
      if (nivel >= BatteryService.limiteMinimo) return;
      _forcarOfflinePorBateria(entregadorId, nivel);
    });
  }

  // Força indisponível por bateria baixa enquanto já online. NÃO força se
  // houver entrega ativa — ficarOffline() já lança Exception nesse caso
  // (mesma checagem usada pro toggle manual), e aqui só engolimos o erro:
  // não faz sentido barrar/avisar quem já foi barrado, o entregador
  // continua com o pedido em mãos, indisponível pra NOVAS ofertas só
  // depois de finalizar. _forcandoOfflinePorBateria evita disparo
  // duplicado se o stream emitir mais de um valor abaixo do limite antes
  // da primeira chamada terminar (ficarOffline é assíncrono).
  static Future<void> _forcarOfflinePorBateria(String entregadorId, int nivel) async {
    if (_forcandoOfflinePorBateria) return;
    _forcandoOfflinePorBateria = true;
    try {
      await ficarOffline(entregadorId);
      debugPrint('[TrackingService] 🔋 Forçado indisponível — bateria em $nivel%');
      // ignore: unawaited_futures
      NotificationService.showBateriaBaixaLocal(nivel);
    } catch (e) {
      debugPrint('[TrackingService] 🔋 Bateria baixa ($nivel%), mas entrega em andamento — não força offline: $e');
    } finally {
      _forcandoOfflinePorBateria = false;
    }
  }

  static void _assinarStream(String entregadorId) {
    _sub?.cancel();
    _sub = LocationService.getPositionStream().listen(
      (pos) {
        _ultimaPosicao = pos;
        _enviar(entregadorId, pos);
      },
      onError: (e) {
        debugPrint('[TrackingService] ⚠ Erro no stream: $e — reiniciando em 10s');
        _sub?.cancel();
        _sub = null;
        if (!_ativo) return;
        Future.delayed(const Duration(seconds: 10), () {
          if (_ativo) _assinarStream(entregadorId);
        });
      },
      cancelOnError: true,
    );
  }

  static Future<void> _enviar(String entregadorId, Position pos) async {
    try {
      await _supabase.from('entregadores').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'disponivel': true,
        'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
      debugPrint('[TrackingService] ✓ GPS: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}');
    } catch (e) {
      debugPrint('[TrackingService] ✗ Erro ao enviar GPS: $e');
    }
  }

  static Future<void> parar(String entregadorId) async {
    _ativo = false;
    await _sub?.cancel();
    _sub = null;
    await _batterySub?.cancel();
    _batterySub = null;
    _ultimaPosicao = null;
    _entregadorId = null;
    WakelockPlus.disable();
    await ForegroundService.parar();
    debugPrint('[TrackingService] ■ Rastreamento parado');
    try {
      await _supabase.from('entregadores').update({
        'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}
  }

  static Future<void> ficarOnline(String entregadorId) async {
    await _exigirBateriaOk();
    final pos = await LocationService.getCurrentPosition();
    try {
      await _supabase.from('entregadores').update({
        'disponivel': true,
        'status': 'disponivel',
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}
  }

  /// Tenta marcar o entregador como offline.
  ///
  /// Lança [Exception] se houver pedido ativo (aceito / chegou_local /
  /// em_rota / retornando) — o chamador deve capturar e exibir o alerta.
  static Future<void> ficarOffline(String entregadorId) async {
    final ativos = await _supabase
        .from('pedidos')
        .select('id')
        .eq('motoboy_id', entregadorId)
        .inFilter('status', ['aceito', 'chegou_local', 'em_rota', 'retornando']);

    if (ativos.isNotEmpty) {
      throw Exception(
        'Você possui uma entrega em andamento. '
        'Finalize a entrega antes de ficar offline.',
      );
    }

    await parar(entregadorId);
    try {
      await _supabase.from('entregadores').update({
        'disponivel': false,
        'status': 'offline',
        'lat': null,
        'lng': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}
  }

  static bool get ativo => _ativo;
}
