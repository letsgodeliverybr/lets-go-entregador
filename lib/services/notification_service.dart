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

  static const String _channelPedidoId = 'letsgo_novo_pedido';
  static const String _channelPedidoName = 'Novo Pedido';
  static const String _channelPedidoDesc = 'Alerta de novo pedido disponível';

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

    // Cria canais Android (obrigatório Android 8+)
    if (Platform.isAndroid) {
      final plugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // Canal padrão
      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ));

      // Canal de novo pedido com som customizado
      await plugin?.createNotificationChannel(AndroidNotificationChannel(
        _channelPedidoId,
        _channelPedidoName,
        description: _channelPedidoDesc,
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('letsgo'),
        enableVibration: true,
        enableLights: true,
      ));
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

  // ── Notificação local de novo pedido (foreground + background) ───────────
  static Future<void> showNovoPedidoLocal() async {
    final androidDetails = AndroidNotificationDetails(
      _channelPedidoId,
      _channelPedidoName,
      channelDescription: _channelPedidoDesc,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('letsgo'),
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
      '🛵 Lets Go Delivery',
      'Pedido Na Tela! Vem Pra Rua E Fature Mais Com A Lets Go Delivery',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // ── Salva token FCM no Supabase (chame após login) ───────────────────────
  static Future<String?> getFcmToken() async {
    return FirebaseMessaging.instance.getToken();
  }
}
