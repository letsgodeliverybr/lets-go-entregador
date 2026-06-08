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

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _entregadorId = await FlutterForegroundTask.getData<String>(key: 'entregador_id');
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _enviarLocalizacao();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {
    if (data is String) _entregadorId = data;
  }

  Future<void> _enviarLocalizacao() async {
    if (_entregadorId == null) {
      _entregadorId = await FlutterForegroundTask.getData<String>(key: 'entregador_id');
    }
    if (_entregadorId == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      await Supabase.instance.client.from('entregadores').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'disponivel': true,
        'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _entregadorId!);
    } catch (_) {}
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
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(8000),
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
      FlutterForegroundTask.sendDataToTask(entregadorId);
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

  static Future<void> parar() async {
    if (!_iniciado) return;
    _iniciado = false;
    await FlutterForegroundTask.stopService();
  }

  static bool get ativo => _iniciado;
}
