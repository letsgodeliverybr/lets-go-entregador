import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = 'https://astbkmpegcmqljltmdpx.supabase.co';
const _supabaseKey = 'sb_publishable_8ocBGGO6EM8GYlg-6HBdmQ_LA6VDL9O';

@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  String? _entregadorId;
  String? _pedidoId;
  double? _clienteLat;
  double? _clienteLng;
  String _statusAtual = '';
  bool _chegadaDetectada = false;
  StreamSubscription<Position>? _posStream;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _entregadorId = await FlutterForegroundTask.getData<String>(key: 'entregador_id');
    _pedidoId = await FlutterForegroundTask.getData<String>(key: 'pedido_id');
    final latStr = await FlutterForegroundTask.getData<String>(key: 'cliente_lat');
    final lngStr = await FlutterForegroundTask.getData<String>(key: 'cliente_lng');
    _clienteLat = double.tryParse(latStr ?? '');
    _clienteLng = double.tryParse(lngStr ?? '');
    _chegadaDetectada = false;

    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
    }

    debugPrint('[ForegroundTask] Iniciado: entregador=$_entregadorId, pedido=$_pedidoId, proxLat=$_clienteLat, proxLng=$_clienteLng');
    _iniciarStreamGPS();
  }

  void _iniciarStreamGPS() {
    _posStream?.cancel();
    _posStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
        // Sem ForegroundNotificationConfig — o ForegroundTaskService já é o foreground service
      ),
    ).listen(
      (pos) async => _onPosicao(pos),
      onError: (e) {
        debugPrint('[ForegroundTask|GPS] Erro no stream: $e — reiniciando em 5s');
        _posStream?.cancel();
        _posStream = null;
        Future.delayed(const Duration(seconds: 5), () {
          if (_entregadorId != null) _iniciarStreamGPS();
        });
      },
      cancelOnError: true,
    );
    debugPrint('[ForegroundTask|GPS] Stream iniciado');
  }

  Future<void> _onPosicao(Position pos) async {
    if (_entregadorId == null) return;

    debugPrint('[ForegroundTask|GPS] lat:${pos.latitude.toStringAsFixed(6)}, lng:${pos.longitude.toStringAsFixed(6)}, acc:${pos.accuracy.toStringAsFixed(0)}m');

    try {
      await Supabase.instance.client.from('entregadores').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'disponivel': true,
        'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _entregadorId!);
    } catch (e) {
      debugPrint('[ForegroundTask|GPS] Erro ao atualizar posição: $e');
    }

    await _verificarProximidade(pos);
  }

  // onRepeatEvent agora é só watchdog: reinicia o stream se morreu silenciosamente
  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_posStream == null && _entregadorId != null) {
      debugPrint('[ForegroundTask] Watchdog: stream GPS morto — reiniciando');
      _iniciarStreamGPS();
    }
  }

  Future<void> _verificarProximidade(Position pos) async {
    if (_pedidoId == null || _clienteLat == null || _clienteLng == null || _chegadaDetectada) return;

    final distM = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      _clienteLat!, _clienteLng!,
    );
    debugPrint('[GEO] distancia_destino=${distM.toStringAsFixed(0)}m status=$_statusAtual');

    if (distM <= 50) {
      _chegadaDetectada = true;
      debugPrint('[ForegroundTask|PROX] ✓ Chegou ao destino! Atualizando Supabase...');
      try {
        await Supabase.instance.client.from('pedidos').update({
          'status': 'chegou_destino',
          'status_detalhado': 'chegou_destino',
          'chegou_destino_em': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', _pedidoId!);

        FlutterForegroundTask.sendDataToMain('chegou_destino:$_pedidoId');

        await FlutterForegroundTask.updateService(
          notificationTitle: "Let's Go Delivery",
          notificationText: '📍 Você chegou ao destino!',
        );
        debugPrint('[ForegroundTask|PROX] Supabase atualizado e main notificado');
      } catch (e) {
        debugPrint('[ForegroundTask|PROX] Erro ao atualizar status: $e');
        _chegadaDetectada = false;
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _posStream?.cancel();
    _posStream = null;
    debugPrint('[ForegroundTask] Destruído — stream GPS cancelado');
  }

  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    try {
      final map = json.decode(data) as Map<String, dynamic>;
      final cmd = map['cmd'] as String?;
      if (cmd == 'set_entregador') {
        _entregadorId = map['entregador_id'] as String?;
        if (_posStream == null && _entregadorId != null) _iniciarStreamGPS();
      } else if (cmd == 'ativar_proximidade') {
        _pedidoId = map['pedido_id'] as String?;
        _clienteLat = (map['lat'] as num?)?.toDouble();
        _clienteLng = (map['lng'] as num?)?.toDouble();
        _statusAtual = (map['status'] as String?) ?? 'em_rota';
        _chegadaDetectada = false;
        debugPrint('[ForegroundTask] Proximidade ativada: pedido=$_pedidoId lat=$_clienteLat lng=$_clienteLng status=$_statusAtual');
      } else if (cmd == 'desativar_proximidade') {
        _pedidoId = null;
        _clienteLat = null;
        _clienteLng = null;
        _chegadaDetectada = false;
        debugPrint('[ForegroundTask] Proximidade desativada');
      }
    } catch (_) {
      _entregadorId = data;
    }
  }
}

class ForegroundService {
  static bool _iniciado = false;

  static void _init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'letsgo_location_channel',
        channelName: 'Rastreamento GPS',
        channelDescription: 'Mantém o envio de localização ativo em background',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(10000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> iniciar(String entregadorId) async {
    await FlutterForegroundTask.saveData(key: 'entregador_id', value: entregadorId);

    if (_iniciado || await FlutterForegroundTask.isRunningService) {
      _iniciado = true;
      FlutterForegroundTask.sendDataToTask(
        json.encode({'cmd': 'set_entregador', 'entregador_id': entregadorId}),
      );
      return;
    }

    _init();
    _iniciado = true;
    await FlutterForegroundTask.startService(
      notificationTitle: "Let's Go Delivery",
      notificationText: 'Rastreamento GPS ativo',
      callback: startForegroundCallback,
    );
  }

  static Future<void> ativarProximidade(String pedidoId, double lat, double lng, {String status = 'em_rota'}) async {
    await FlutterForegroundTask.saveData(key: 'pedido_id', value: pedidoId);
    await FlutterForegroundTask.saveData(key: 'cliente_lat', value: lat.toString());
    await FlutterForegroundTask.saveData(key: 'cliente_lng', value: lng.toString());
    FlutterForegroundTask.sendDataToTask(json.encode({
      'cmd': 'ativar_proximidade',
      'pedido_id': pedidoId,
      'lat': lat,
      'lng': lng,
      'status': status,
    }));
    debugPrint('[ForegroundService] Proximidade ativada: pedido=$pedidoId lat=$lat lng=$lng status=$status');
  }

  static Future<void> desativarProximidade() async {
    await FlutterForegroundTask.saveData(key: 'pedido_id', value: '');
    await FlutterForegroundTask.saveData(key: 'cliente_lat', value: '');
    await FlutterForegroundTask.saveData(key: 'cliente_lng', value: '');
    FlutterForegroundTask.sendDataToTask(json.encode({'cmd': 'desativar_proximidade'}));
    debugPrint('[ForegroundService] Proximidade desativada');
  }

  static Future<void> parar() async {
    if (!_iniciado) return;
    _iniciado = false;
    await FlutterForegroundTask.stopService();
  }

  static bool get ativo => _iniciado;
}
