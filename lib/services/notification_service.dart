import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show navigatorKey;
import 'alerta_pedido_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // _v2: canais Android são imutáveis depois de criados (o som não pode
  // mudar via código uma vez que o canal já existe no aparelho) — troca de
  // ID força o Android a criar um canal novo do zero com o som certo,
  // em vez de manter travado um canal antigo criado sem som customizado.
  //
  // _v4: som chegava baixo E cortado (só "1 Let's Go", nunca o áudio
  // completo) — confirmado ao vivo (Gabriel, app fechado). Causa raiz:
  // AndroidNotificationChannel sem audioAttributesUsage cai no padrão do
  // pacote (AudioAttributesUsage.notification = USAGE_NOTIFICATION), que
  // o Android trata como "aviso curto": toca no stream de volume de
  // Notificação (geralmente bem mais baixo que mídia/alarme no aparelho) E
  // aplica política de duração curta pra esse uso — explica os dois
  // sintomas de uma vez. Trocado pra AudioAttributesUsage.alarm
  // (USAGE_ALARM), o mesmo "uso" que o despertador do Android usa: toca no
  // stream de Alarme (alto, não fica preso ao volume de notificação do
  // usuário) e sem truncamento de duração — bate com a intenção que já
  // existia aqui (FLAG_INSISTENT, som insistente tipo ligação). Precisou
  // subir o ID do canal de novo (canal é imutável) pra forçar recriação
  // com esse AudioAttributes novo.
  //
  // _v5: MUDANÇA DE PRODUTO (não é fix de bug) — o alerta insistente tipo
  // alarme/ligação (FLAG_INSISTENT + AudioAttributesUsage.alarm) foi
  // substituído por um toque curto (~1,5s, "moeda caindo") sem loop, só
  // vibração padrão. A insistência sonora agora fica pro loop de
  // "letsgo.wav" que só começa DEPOIS que a tela Disponíveis abre de
  // verdade (ver pedidos_disponiveis_screen.dart) — não faz mais sentido
  // repetir a notificação em si. Canal de novo com ID novo (imutável,
  // mesmo motivo do _v4) pra forçar recriação sem o som/comportamento
  // antigo grudado no aparelho de quem já tinha o app instalado.
  static const String _channelPedidoId = 'letsgo_novo_pedido_v5';
  static const String _channelPedidoName = 'Novo Pedido';
  static const String _channelPedidoDesc = 'Alerta de novo pedido disponível';

  static const String _channelRotaId = 'letsgo_nova_rota_v4';
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

  static const String _channelIndicacaoId = 'letsgo_indicacao';
  static const String _channelIndicacaoName = 'Indicação';
  static const String _channelIndicacaoDesc = 'Convite pra indicar motoboy/loja nova';

  // Canal genérico pros 10 cards de lembrete periódico (dia útil + horário
  // fixo, ver aba Disparar Notificações) — mesmo motivo/padrão neutro do
  // canal de avaliação: sem som customizado, sem insistência. É lembrete,
  // não "pedido chegando", nunca deve soar como alarme.
  static const String _channelPeriodicoId = 'letsgo_periodico';
  static const String _channelPeriodicoName = 'Lembretes';
  static const String _channelPeriodicoDesc = 'Lembretes periódicos (dia útil/horário fixo)';
  // wa.me com número já em formato internacional (55 + DDD 11 + número) —
  // mesmo (11) 99170-2772 usado em todo o resto do app pra contato/suporte.
  // Trocado de "abrir link de cadastro" pra "abrir WhatsApp" a pedido.
  static const String _whatsappIndicacao = '5511991702772';

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
        if (details.payload == 'indicacao') abrirLinkIndicacao();
        // App já rodando (foreground ou background-mas-vivo) quando o
        // fullScreenIntent trouxe a Activity de volta — cold start (app
        // morto) é tratado à parte, em main.dart, via
        // getNotificationAppLaunchDetails() (esse callback aqui não dispara
        // nesse caso porque o plugin ainda não tinha um listener registrado
        // no momento em que o Android lançou a Activity).
        if (details.payload == 'novo_pedido') {
          // App já vivo nesse caso (só pausado/background) — o engine
          // Flutter já existe, então já dá pra tocar o loop aqui, junto
          // com a navegação (cold-start de verdade é tratado à parte, ver
          // comentário acima e AuthGate em main.dart).
          // ignore: unawaited_futures
          AlertaPedidoService.instance.iniciar();
          _abrirTelaPedidosDisponiveis();
        }
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

      // Sem audioAttributesUsage customizado de propósito (v5) — cai no
      // padrão do pacote (USAGE_NOTIFICATION), o "uso" certo pra um toque
      // curto normal, não mais um alarme. enableVibration:true sem
      // vibrationPattern customizado = vibração padrão do sistema.
      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelPedidoId,
        _channelPedidoName,
        description: _channelPedidoDesc,
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('moeda_caindo'),
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
        audioAttributesUsage: AudioAttributesUsage.alarm,
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

      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelIndicacaoId,
        _channelIndicacaoName,
        description: _channelIndicacaoDesc,
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      ));

      await plugin?.createNotificationChannel(const AndroidNotificationChannel(
        _channelPeriodicoId,
        _channelPeriodicoName,
        description: _channelPeriodicoDesc,
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
        await showAvaliarAppLocal(
          titulo: msg.data['titulo']?.toString(),
          corpo: msg.data['corpo']?.toString(),
        );
      } else if (tipo == 'indicacao') {
        await showIndicacaoLocal(
          titulo: msg.data['titulo']?.toString(),
          corpo: msg.data['corpo']?.toString(),
        );
      } else if (tipo == 'periodico') {
        await showPeriodicoLocal(
          titulo: msg.data['titulo']?.toString(),
          corpo: msg.data['corpo']?.toString(),
        );
      } else if (tipo == 'nova_rota') {
        await showNovaRotaLocal();
        // ignore: unawaited_futures
        AlertaPedidoService.instance.iniciar();
      } else {
        // Vibração (dentro de iniciar())+ som de moeda (showNovoPedidoLocal,
        // canal já tem o som curto) + início do loop Let's Go disparados
        // juntos, sem esperar a navegação — requisito explícito de tudo
        // acontecer ao mesmo tempo, não em sequência. Sem await no
        // iniciar() de propósito: não faz sentido atrasar a navegação
        // esperando o player carregar o asset.
        // ignore: unawaited_futures
        AlertaPedidoService.instance.iniciar();
        await showNovoPedidoLocal();
        // App já em foreground de verdade — fullScreenIntent não faz nada
        // aqui (só age fora do foreground), então a navegação automática
        // pra Disponíveis precisa ser disparada direto, sem depender de
        // toque na notificação.
        _abrirTelaPedidosDisponiveis();
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
  // só trata 'avaliar_app' (Play Store) e 'indicacao' (link de cadastro);
  // pedido/rota já abrem a tela certa sozinhos porque o app inteiro é
  // sobre acompanhar pedidos, não precisa de deep link específico.
  static void _tratarTapNotificacao(Map<String, dynamic> data) {
    final tipo = data['tipo']?.toString() ?? '';
    if (tipo == 'avaliar_app') abrirAvaliacaoPlayStore();
    if (tipo == 'indicacao') abrirLinkIndicacao();
  }

  // Navega direto pra tela Disponíveis usando a rota nomeada '/pedidos'
  // (já registrada em main.dart) via o navigatorKey global — chamado tanto
  // daqui (toque/fullScreenIntent com app já vivo) quanto de
  // FirebaseMessaging.onMessage (app em foreground de verdade) abaixo.
  // pushNamed simples (não remove a pilha) — se o entregador já estava em
  // outra tela, some ao voltar/sair da tela Disponíveis, comportamento
  // aceitável pra esse caso de uso.
  static void _abrirTelaPedidosDisponiveis() {
    try {
      navigatorKey.currentState?.pushNamed('/pedidos');
    } catch (e) {
      debugPrint('[NotificationService] falha ao navegar pra /pedidos: $e');
    }
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

  // Abre o WhatsApp de contato (mesmo número usado no resto do app) com
  // uma mensagem pré-preenchida — pedido explícito do usuário no lugar do
  // link de cadastro/login que era aberto antes.
  static Future<void> abrirLinkIndicacao() async {
    final msg = Uri.encodeComponent(
        'Olá! Quero indicar um motoboy ou uma loja nova pra Let\'s Go Delivery.');
    try {
      await launchUrl(Uri.parse('https://wa.me/$_whatsappIndicacao?text=$msg'),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[indicacao] falhou ao abrir WhatsApp: $e');
    }
  }

  // ── Notificação local: pedir avaliação na Play Store ────────────────────
  // titulo/corpo vêm do data payload do FCM (texto editável pelo admin no
  // painel, mesma fonte usada pelo disparo automático e pelo manual — ver
  // lembrete-avaliacao/index.ts) — os literais abaixo são só o fallback
  // pra quando o payload não traz o campo (ex: versão antiga da function).
  static Future<void> showAvaliarAppLocal({String? titulo, String? corpo}) async {
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
      (titulo?.isNotEmpty ?? false) ? titulo! : 'Gostando do app? 💙🩵',
      (corpo?.isNotEmpty ?? false) ? corpo! : 'Deixa sua avaliação pra gente na Play Store!',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: 'avaliar_app',
    );
  }

  // ── Notificação local: convite pra indicar motoboy/loja nova ────────────
  // Mesma lógica de fallback de showAvaliarAppLocal — ver comentário acima.
  static const String _corpoIndicacaoPadrao =
      "Já tá gostando de faturar R\$2 por km rodado nas entregas? Indique um "
      "motoboy ou uma loja nova pra Let's Go Delivery e fature ainda mais — "
      "R\$150 de bônus por loja indicada! Chama (11) 99170-2772, time de "
      "expansão nacional Let's Go Delivery.";

  static Future<void> showIndicacaoLocal({String? titulo, String? corpo}) async {
    if (!_initialized) await initLocal();

    final tituloFinal = (titulo?.isNotEmpty ?? false) ? titulo! : '🛵 Ei, motoboy!';
    final corpoFinal = (corpo?.isNotEmpty ?? false) ? corpo! : _corpoIndicacaoPadrao;

    // BigTextStyleInformation: sem isso, o corpo (mais longo que o normal)
    // fica truncado numa linha só na notificação recolhida — com isso,
    // o Android mostra o texto completo ao expandir.
    final androidDetails = AndroidNotificationDetails(
      _channelIndicacaoId,
      _channelIndicacaoName,
      channelDescription: _channelIndicacaoDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(corpoFinal),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    await _localNotifications.show(
      3002,
      tituloFinal,
      corpoFinal,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: 'indicacao',
    );
  }

  // ── Notificação local: lembrete periódico (10 cards, dia útil/horário) ──
  // Diferente de avaliar_app/indicacao, esse tipo não tem texto padrão
  // hardcoded — os 10 cards nascem vazios no painel (texto é preenchido
  // depois, um por um) e a Edge Function (lembrete-periodico) já evita
  // mandar push com texto vazio. Essa guarda aqui é só reforço, cobre
  // qualquer chamada direta que escape dessa checagem.
  static Future<void> showPeriodicoLocal({String? titulo, String? corpo}) async {
    if (!_initialized) await initLocal();
    if (titulo == null || titulo.isEmpty || corpo == null || corpo.isEmpty) return;

    final androidDetails = AndroidNotificationDetails(
      _channelPeriodicoId,
      _channelPeriodicoName,
      channelDescription: _channelPeriodicoDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(corpo),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    await _localNotifications.show(
      3003,
      titulo,
      corpo,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: 'periodico',
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
  // v5: toque único (moeda caindo, ~1,5s) + vibração padrão, SEM
  // FLAG_INSISTENT — a insistência sonora agora é responsabilidade do loop
  // de "letsgo.wav" na tela Disponíveis (pedidos_disponiveis_screen.dart),
  // não da notificação em si. fullScreenIntent:true continua — é o que
  // abre o app sozinho (mesmo com ele fechado/em background). payload:
  // 'novo_pedido' é o que permite o app, ao abrir (cold start via
  // getNotificationAppLaunchDetails() em main.dart, ou já rodando via
  // onDidReceiveNotificationResponse abaixo), saber que deve navegar
  // direto pra tela Disponíveis em vez da tela padrão.
  static Future<void> showNovoPedidoLocal() async {
    if (!_initialized) await initLocal();

    const androidDetails = AndroidNotificationDetails(
      _channelPedidoId,
      _channelPedidoName,
      channelDescription: _channelPedidoDesc,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('moeda_caindo'),
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
      payload: 'novo_pedido',
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
