import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const String _channelPedidoId = 'letsgo_novo_pedido';
  static const String _channelPedidoName = 'Novo Pedido';
  static const String _channelPedidoDesc = 'Alerta de novo pedido disponível';

  static const String _channelRotaId = 'letsgo_nova_rota';
  static const String _channelRotaName = 'Nova Rota';
  static const String _channelRotaDesc = 'Alerta de rota com múltiplas entregas';

  static const String _channelDestinoId = 'letsgo_chegou_destino';
  static const String _channelDestinoName = 'Chegou ao Destino';
  static const String _channelDestinoDesc = 'Alerta de chegada ao endereço de entrega';

  static bool _initialized = false;

  // ── Notificações locais ─────────────────────────────────────────────────
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

      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelRotaId,
        _channelRotaName,
        description: _channelRotaDesc,
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('letsgo'),
        enableVibration: true,
        enableLights: true,
      ));

      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelDestinoId,
        _channelDestinoName,
        description: _channelDestinoDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      ));
    }

    _initialized = true;
    debugPrint('NotificationService: canais criados com sucesso');
  }

  // ── FCM: foreground + token ─────────────────────────────────────────────
  static Future<void> initFCM() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Mensagens com app em foreground — FCM não exibe automaticamente
    FirebaseMessaging.onMessage.listen((msg) async {
      debugPrint('[FCM] foreground: ${msg.data}');
      final tipo = msg.data['tipo']?.toString() ?? '';
      if (tipo == 'nova_rota') {
        await showNovaRotaLocal();
      } else {
        await showNovoPedidoLocal();
      }
    });

    // Usuário tocou na notificação com app em background
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[FCM] aberto via notificação: ${msg.data}');
    });

    // App estava terminado e foi aberto pela notificação
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] iniciado via notificação: ${initialMessage.data}');
    }
  }

  // ── Salva token FCM na tabela entregadores ──────────────────────────────
  static Future<void> saveFcmToken(String uid) async {
    if (uid.isEmpty) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await Supabase.instance.client
          .from('entregadores')
          .update({'fcm_token': token})
          .eq('id', uid);
      debugPrint('[FCM] token salvo');

      // Atualiza automaticamente se o token for renovado
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        Supabase.instance.client
            .from('entregadores')
            .update({'fcm_token': newToken})
            .eq('id', uid);
        debugPrint('[FCM] token renovado e salvo');
      });
    } catch (e) {
      debugPrint('[FCM] erro ao salvar token: $e');
    }
  }

  // ── Notificação local: chegou ao destino ───────────────────────────────
  static Future<void> showChegouDestinoLocal() async {
    if (!_initialized) await initLocal();

    const androidDetails = AndroidNotificationDetails(
      _channelDestinoId,
      _channelDestinoName,
      channelDescription: _channelDestinoDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ticker: 'Você chegou ao destino',
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    await _localNotifications.show(
      2001,
      '📍 Chegou ao destino!',
      'Peça o código de confirmação ao cliente.',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // ── Notificação local: novo pedido ──────────────────────────────────────
  static Future<void> showNovoPedidoLocal() async {
    if (!_initialized) await initLocal();

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
      1001,
      "LET'S GO MOTOCA 🛵",
      "Pedidos na tela! Vem Pra Rua! Aproveite Alta Demanda Para Faturar Mais Com A Let's Go Delivery!",
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // ── Notificação local: nova rota ────────────────────────────────────────
  static Future<void> showNovaRotaLocal() async {
    if (!_initialized) await initLocal();

    const androidDetails = AndroidNotificationDetails(
      _channelRotaId,
      _channelRotaName,
      channelDescription: _channelRotaDesc,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('letsgo'),
      enableVibration: true,
      enableLights: true,
      ticker: 'Nova rota disponível',
      icon: '@mipmap/ic_launcher',
      fullScreenIntent: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifications.show(
      1002,
      '🛵 Rota Disponível!',
      'Nova rota com múltiplas entregas para você!',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
