import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Handler de mensagens em background (deve ser top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  NotificationService._showLocalNotification(message);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'letsgo_pedidos';
  static const String _channelName = 'Pedidos';
  static const String _channelDesc = 'Notificações de novos pedidos';

  // ── Inicialização principal ──────────────────────────────────────────────
  static Future<void> initialize() async {
    // Garante que o Firebase está inicializado
    await Firebase.initializeApp();

    // Registra handler de background
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Inicializa flutter_local_notifications
    await _initLocalNotifications();

    // Solicita permissão (iOS + Android 13+)
    await _requestPermissions();

    // Handlers de mensagem
    _setupMessageHandlers();

    // Token FCM (útil para debug / salvar no Supabase)
    final token = await FirebaseMessaging.instance.getToken();
    if (kDebugMode && token != null) {
      debugPrint('🔔 FCM Token: $token');
    }

    // Escuta renovação de token
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      if (kDebugMode) debugPrint('🔔 FCM Token renovado: $newToken');
      // TODO: salvar newToken em Supabase na tabela entregadores
    });
  }

  // ── Local Notifications ──────────────────────────────────────────────────
  static Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Ao tocar na notificação — pode navegar para a tela de pedidos
        debugPrint('Notificação tocada: ${details.payload}');
      },
    );

    // Cria canal Android (obrigatório Android 8+)
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  // ── Permissões ───────────────────────────────────────────────────────────
  static Future<void> _requestPermissions() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (kDebugMode) {
      debugPrint(
          '🔔 Permissão FCM: ${settings.authorizationStatus.name}');
    }
  }

  // ── Handlers de mensagens ────────────────────────────────────────────────
  static void _setupMessageHandlers() {
    // App em foreground → mostra notificação local
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 Mensagem foreground: ${message.notification?.title}');
      _showLocalNotification(message);
    });

    // App aberto a partir de notificação (em background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
          '📩 App aberto por notificação: ${message.notification?.title}');
      // TODO: navegar para /pedidos se for pedido novo
    });
  }

  // ── Exibe notificação local ──────────────────────────────────────────────
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Novo pedido',
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _localNotifications.show(
      notification.hashCode,
      notification.title ?? '🛵 Novo pedido!',
      notification.body ?? 'Um novo pedido está disponível para você.',
      details,
      payload: message.data.toString(),
    );
  }

  // ── Salva token FCM no Supabase (chame após login) ───────────────────────
  static Future<String?> getFcmToken() async {
    return FirebaseMessaging.instance.getToken();
  }
}
