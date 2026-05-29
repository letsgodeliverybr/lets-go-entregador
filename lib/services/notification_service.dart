import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const String _channelPedidoId = 'letsgo_novo_pedido';
  static const String _channelPedidoName = 'Novo Pedido';
  static const String _channelPedidoDesc = 'Alerta de novo pedido disponível';

  static bool _initialized = false;

  // ── Inicialização local (sem Firebase) ──────────────────────────────────
  static Future<void> initLocal() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notificação tocada: ${details.payload}');
      },
    );

    if (Platform.isAndroid) {
      final plugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await plugin?.requestNotificationsPermission();

      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelPedidoId,
        _channelPedidoName,
        description: _channelPedidoDesc,
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('letsgo'),
        enableVibration: true,
        enableLights: true,
      ));
    }

    _initialized = true;
    debugPrint('NotificationService: canal criado com sucesso');
  }

  // ── Notificação de novo pedido ───────────────────────────────────────────
  static Future<void> showNovoPedidoLocal() async {
    if (!_initialized) {
      debugPrint('NotificationService: não inicializado, chamando initLocal');
      await initLocal();
    }

    const androidDetails = AndroidNotificationDetails(
      _channelPedidoId,
      _channelPedidoName,
      channelDescription: _channelPedidoDesc,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('letsgo'),
      enableVibration: true,
      enableLights: true,
      ticker: 'Novo pedido disponível',
      icon: '@mipmap/ic_launcher',
      fullScreenIntent: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Lets Go Delivery',
      'Pedido Na Tela! Vem Pra Rua E Fature Mais Com A Lets Go Delivery',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
