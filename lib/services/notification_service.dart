import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // _v2: canais Android são imutáveis depois de criados (o som não pode
  // mudar via código uma vez que o canal já existe no aparelho) — troca de
  // ID força o Android a criar um canal novo do zero com o som certo,
  // em vez de manter travado um canal antigo criado sem som customizado.
  static const String _channelPedidoId = 'letsgo_novo_pedido_v3';
  static const String _channelPedidoName = 'Novo Pedido';
  static const String _channelPedidoDesc = 'Alerta de novo pedido disponível';

  static const String _channelRotaId = 'letsgo_nova_rota_v3';
  static const String _channelRotaName = 'Nova Rota';
  static const String _channelRotaDesc = 'Alerta de rota com múltiplas entregas';

  static const String _channelDestinoId = 'letsgo_chegou_destino';
  static const String _channelDestinoName = 'Chegou ao Destino';
  static const String _channelDestinoDesc = 'Alerta de chegada ao endereço de entrega';

  // Sem som customizado de propósito — usa o som padrão do sistema
  // (playSound:true, sem RawResourceAndroidNotificationSound), pra não
  // repetir o mesmo problema já achado nos outros canais: som referenciado
  // só por nome via string é removido pelo shrinker de recursos do build
  // de release se não tiver o res/raw/keep.xml também cobrindo ele. Como
  // este canal não é urgente (não precisa de som customizado/insistente
  // igual pedido novo), simplesmente não usa recurso customizado nenhum.
  static const String _channelAvaliarId = 'letsgo_avaliar_app';
  static const String _channelAvaliarName = 'Avaliação do app';
  static const String _channelAvaliarDesc = 'Convite pra avaliar o app na Play Store';
  static const String _androidPackageId = 'br.com.letsgodelivery.parceiro';

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
        if (details.payload == 'avaliar_app') abrirAvaliacaoPlayStore();
      },
    );

    if (Platform.isAndroid) {
      final plugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // Crash real e confirmado: requestNotificationsPermission() acessa a
      // Activity internamente (plugin nativo) — quando initLocal() roda
      // dentro de _firebaseBackgroundHandler (isolate de background, sem
      // Activity nenhuma), derruba com NullPointerException
      // ("Context.checkPermission on a null object reference"), sem
      // try/catch nenhum ao redor. Isso interrompia a função ANTES da
      // criação dos canais logo abaixo — nenhuma notificação local
      // conseguia ser mostrada via esse caminho, pra nenhum tipo de
      // mensagem (pedido, rota, avaliação), sempre que o app estava
      // realmente em segundo plano. A permissão já foi pedida no onboarding
      // (PermissoesScreen/DeviceSetupScreen, isolate principal, com
      // Activity) — pedir de novo aqui é redundante mesmo quando funciona;
      // envolver em try/catch garante que uma falha aqui nunca impede o
      // resto (canais) de ser criado.
      try {
        await plugin?.requestNotificationsPermission();
      } catch (e) {
        debugPrint('[NotificationService] requestNotificationsPermission falhou (provável isolate sem Activity): $e');
      }

      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelPedidoId,
        _channelPedidoName,
        description: _channelPedidoDesc,
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('letsgo_notification'),
        enableVibration: true,
        enableLights: true,
      ));

      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelRotaId,
        _channelRotaName,
        description: _channelRotaDesc,
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('letsgo_notification'),
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

      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelAvaliarId,
        _channelAvaliarName,
        description: _channelAvaliarDesc,
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
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
      if (tipo == 'avaliar_app') {
        await showAvaliarAppLocal();
      } else if (tipo == 'nova_rota') {
        await showNovaRotaLocal();
      } else {
        await showNovoPedidoLocal();
      }
    });

    // Usuário tocou na notificação com app em background
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[FCM] aberto via notificação: ${msg.data}');
      _tratarTapNotificacao(msg.data);
    });

    // App estava terminado e foi aberto pela notificação
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] iniciado via notificação: ${initialMessage.data}');
      _tratarTapNotificacao(initialMessage.data);
    }
  }

  // Toque na notificação (app reaberto/trazido pra frente por ela) — hoje
  // só trata o tipo 'avaliar_app' (abre a tela de avaliação da Play Store
  // direto); pedido/rota já abrem a tela certa sozinhos porque o app inteiro
  // é sobre acompanhar pedidos, não precisa de deep link específico.
  static void _tratarTapNotificacao(Map<String, dynamic> data) {
    final tipo = data['tipo']?.toString() ?? '';
    if (tipo == 'avaliar_app') abrirAvaliacaoPlayStore();
  }

  // market://details abre o app da Play Store direto na ficha do app com
  // showAllReviews=true (tenta levar pra seção de avaliações/escrever
  // avaliação — não é 100% documentado/garantido pelo Google, pode variar
  // por versão da Play Store). Sem o app da Play Store instalado (raro,
  // mas existe em alguns aparelhos), cai no fallback https://, que abre no
  // navegador.
  static Future<void> abrirAvaliacaoPlayStore() async {
    final marketUri = Uri.parse(
        'market://details?id=$_androidPackageId&showAllReviews=true');
    final webUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=$_androidPackageId&showAllReviews=true');
    try {
      final abriu = await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      if (abriu) return;
    } catch (_) {}
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[avaliarApp] falhou ao abrir Play Store: $e');
    }
  }

  // ── Notificação local: pedir avaliação na Play Store ────────────────────
  static Future<void> showAvaliarAppLocal() async {
    if (!_initialized) await initLocal();

    const androidDetails = AndroidNotificationDetails(
      _channelAvaliarId,
      _channelAvaliarName,
      channelDescription: _channelAvaliarDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    await _localNotifications.show(
      3001,
      'Gostando do app? 💙🩵',
      'Deixa sua avaliação pra gente na Play Store!',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: 'avaliar_app',
    );
  }

  // ── Salva token FCM na tabela entregadores ──────────────────────────────
  // Chamado sempre que o app abre com sessão válida (main.dart) e após login
  // (login_screen.dart) — sempre sobrescreve com o token atual do Firebase,
  // sem comparar com o valor salvo antes (overwrite incondicional é mais
  // simples e robusto que comparar-e-atualizar). Grava 'updated_at' pra dar
  // pra confirmar de fora (sem log) que essa gravação de fato rodou.
  static Future<void> saveFcmToken(String uid) async {
    if (uid.isEmpty) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await Supabase.instance.client
          .from('entregadores')
          .update({
            'fcm_token': token,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', uid);
      debugPrint('[FCM] token salvo');

      // Atualiza automaticamente se o token for renovado
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        Supabase.instance.client
            .from('entregadores')
            .update({
              'fcm_token': newToken,
              'updated_at': DateTime.now().toIso8601String(),
            })
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

    final androidDetails = AndroidNotificationDetails(
      _channelPedidoId,
      _channelPedidoName,
      channelDescription: _channelPedidoDesc,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('letsgo_notification'),
      enableVibration: true,
      enableLights: true,
      ticker: 'Novo pedido disponível',
      icon: '@mipmap/ic_launcher',
      fullScreenIntent: true,
      // FLAG_INSISTENT (valor 4, nativo do Android Notification) — repete o
      // som/vibração em loop até o entregador abrir ou dispensar a
      // notificação, igual uma ligação. Sem isso o som toca só uma vez.
      additionalFlags: Int32List.fromList(<int>[4]),
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
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // ── Notificação local: nova rota ────────────────────────────────────────
  static Future<void> showNovaRotaLocal() async {
    if (!_initialized) await initLocal();

    final androidDetails = AndroidNotificationDetails(
      _channelRotaId,
      _channelRotaName,
      channelDescription: _channelRotaDesc,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('letsgo_notification'),
      enableVibration: true,
      enableLights: true,
      ticker: 'Nova rota disponível',
      icon: '@mipmap/ic_launcher',
      fullScreenIntent: true,
      additionalFlags: Int32List.fromList(<int>[4]),
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
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
