import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'services/volume_service.dart';
import 'screens/login_screen.dart';
import 'screens/permissoes_screen.dart';
import 'screens/home_screen.dart';
import 'screens/entregador_home_screen.dart';
import 'screens/pedidos_disponiveis_screen.dart';
import 'screens/rota_disponivel_screen.dart';
import 'screens/extrato_screen.dart';
import 'screens/aguardo_aprovacao_screen.dart';
import 'services/notification_service.dart';
import 'services/alerta_pedido_service.dart';
import 'screens/device_setup_screen.dart';
import 'screens/fullscreen_intent_reprompt_screen.dart';
import 'services/fullscreen_intent_permission_service.dart';
import 'widgets/pedido_card_widget.dart';
import 'utils/taxa_helper.dart' as th;
import 'utils/cla_helper.dart' as cla;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const _firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyCCPzZZWrLGmnUlzxo66h4tzn0I0HsV-10',
  appId: '1:935542418052:android:2e356ebfc7f8055f3eb0d1',
  messagingSenderId: '935542418052',
  projectId: 'lets-go-delivery-df74d',
  storageBucket: 'lets-go-delivery-df74d.firebasestorage.app',
);

// O payload do despacho-engine agora é data-only, de propósito (sem bloco
// `notification`) — exatamente pra SEMPRE cair aqui, mesmo com o app em
// background ou morto, em vez de deixar o Android renderizar a
// notificação sozinho (esse caminho não suporta fullScreenIntent nem dá
// pra controlar o som, e foi como um channel_id desatualizado foi parar em
// produção sem ninguém notar). Roda num isolate novo e separado do app
// principal — precisa inicializar Flutter/Firebase de novo aqui dentro
// (mesmo padrão de main(), é um entry point próprio, daí o
// @pragma('vm:entry-point')). Usa as mesmas notificações locais do
// NotificationService (fullScreenIntent + som insistente) que o app usa
// quando está em foreground — canais já existem, criar de novo é no-op.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // O Android pode reaproveitar o mesmo isolate de background pra mais de
    // uma mensagem seguida sem matá-lo — Firebase.initializeApp() de novo
    // nesse caso derruba com "[core/duplicate-app]" (app "[DEFAULT]" já
    // existe), e como isso corre sem try/catch nenhum ao redor, a exceção
    // mata a função inteira ANTES de chegar em showNovoPedidoLocal() — som
    // e notificação simplesmente não acontecem, em silêncio. Guarda padrão
    // recomendada pelo FlutterFire pra background handler.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _firebaseOptions);
    }
    final tipo = message.data['tipo']?.toString() ?? '';
    if (tipo != 'avaliar_app' && tipo != 'indicacao' && tipo != 'periodico') {
      // Cobre 'nova_rota', 'novo_pedido' e qualquer tipo desconhecido —
      // mesmo fallback de sempre (else final antigo).
      //
      // Vibração + som curto de moeda vêm daqui (canal da notificação,
      // showNovoPedidoLocal/showNovaRotaLocal — sem FLAG_INSISTENT, toca
      // uma vez só). Volume forçado (Mídia E Alarme, ver
      // VolumeService/MainActivity.kt) ANTES de mostrar, pro canal já
      // tocar no máximo.
      //
      // O loop "Let's Go Let's Go" (AlertaPedidoService) NÃO é iniciado
      // aqui de propósito: esse handler roda num isolate Dart separado da
      // UI (entry point próprio, ver @pragma acima) — o singleton
      // AlertaPedidoService.instance daqui seria uma instância DIFERENTE
      // da que a tela realmente usa, morta junto com esse isolate.
      // iniciar() só é chamado onde o isolate principal já está de
      // verdade rodando: AuthGate (cold start via fullScreenIntent) ou
      // onDidReceiveNotificationResponse (app só pausado/background) — ver
      // notification_service.dart.
      await VolumeService.forcarVolumeMidiaMaximo();
      if (tipo == 'nova_rota') {
        await NotificationService.showNovaRotaLocal();
      } else {
        await NotificationService.showNovoPedidoLocal();
      }
    } else if (tipo == 'avaliar_app') {
      await NotificationService.showAvaliarAppLocal(
        titulo: message.data['titulo']?.toString(),
        corpo: message.data['corpo']?.toString(),
      );
    } else if (tipo == 'indicacao') {
      await NotificationService.showIndicacaoLocal(
        titulo: message.data['titulo']?.toString(),
        corpo: message.data['corpo']?.toString(),
      );
    } else if (tipo == 'periodico') {
      await NotificationService.showPeriodicoLocal(
        titulo: message.data['titulo']?.toString(),
        corpo: message.data['corpo']?.toString(),
      );
    }
  } catch (e, st) {
    // Nunca deixar isso morrer em silêncio de novo — se voltar a falhar,
    // pelo menos fica rastro em `adb logcat` (grep por "_firebaseBackgroundHandler").
    debugPrint('[_firebaseBackgroundHandler] erro: $e\n$st');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: _firebaseOptions);
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  await NotificationService.initLocal();
  await NotificationService.initFCM();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _supabase = Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _streamSub;
  StreamSubscription<AuthState>? _authSub;
  OverlayEntry? _overlayEntry;
  Timer? _overlayTimer;
  Set<String> _idsConhecidos = {};
  bool _primeiraEmissao = true;

  @override
  void initState() {
    super.initState();
    th.carregarFaixas();

    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        _iniciarStream();
      } else {
        _cancelarStream();
        _fecharOverlay();
      }
    });

    if (_supabase.auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _iniciarStream());
    }
  }

  void _iniciarStream() {
    _cancelarStream();
    _primeiraEmissao = true;
    _idsConhecidos = {};
    _streamSub = _supabase
        .from('pedidos')
        .stream(primaryKey: ['id'])
        .eq('status', 'pronto')
        .listen(_onPedidosUpdate);
  }

  void _cancelarStream() {
    _streamSub?.cancel();
    _streamSub = null;
  }

  Future<void> _onPedidosUpdate(List<Map<String, dynamic>> lista) async {
    // Exclusividade de clã: recarrega sempre (não fica em cache permanente)
    // porque o admin pode mudar o clã com o app já aberto — precisa valer
    // pro próximo pedido que aparecer nesse mesmo stream, não só depois de
    // reabrir o app. Tabelas de clã são pequenas, custo desprezível.
    await cla.carregarCla();

    // Filter motoboy_id is null in Dart, e exclusividade de clã
    final disponiveis = lista
        .where((p) => (p['motoboy_id']?.toString() ?? '').isEmpty)
        .where((p) => cla.pedidoElegivelParaMeuCla(p['loja_id']?.toString()))
        .toList();

    final idsAtuais = disponiveis.map((p) => p['id'].toString()).toSet();

    if (_primeiraEmissao) {
      _idsConhecidos = idsAtuais;
      _primeiraEmissao = false;
      // Sem som aqui de propósito — tela Disponíveis é silenciosa agora
      // (decisão de produto: o alerta sonoro já acontece na notificação/
      // alarme de pedido novo, que é suficiente; ver _firebaseBackgroundHandler
      // e notification_service.dart). Esse bloco só continua existindo pra
      // manter _idsConhecidos correto (usado no diff de novosIds abaixo) e
      // pro overlay visual (_mostrarOverlay), que continuam funcionando.
      return;
    }

    final novosIds = idsAtuais.difference(_idsConhecidos);
    _idsConhecidos = idsAtuais;

    if (idsAtuais.isEmpty) return;

    if (novosIds.isEmpty) return;

    // Fetch the first new pedido with lojas join (só pro overlay visual)
    try {
      final data = await _supabase
          .from('pedidos')
          .select('*, lojas(nome, endereco, latitude, longitude)')
          .eq('id', novosIds.first)
          .eq('status', 'pronto')
          .maybeSingle();
      if (data == null) return;
      _mostrarOverlay(data);
    } catch (_) {}
  }

  void _mostrarOverlay(Map<String, dynamic> pedido) {
    _fecharOverlay();
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (_) => _PedidoOverlay(
        pedido: pedido,
        onRejeitar: _fecharOverlay,
      ),
    );
    overlay.insert(_overlayEntry!);
    _overlayTimer = Timer(const Duration(seconds: 30), _fecharOverlay);
  }

  void _fecharOverlay() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cancelarStream();
    _fecharOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Lets Go Delivery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A56DB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
      routes: {
        '/pedidos': (context) => const PedidosDisponiveisScreen(),
        '/login': (context) => const LoginScreen(),
        '/extrato': (context) => const ExtratoScreen(),
      },
    );
  }
}

// ─── Overlay Widget ───────────────────────────────────────────────────────────

class _PedidoOverlay extends StatefulWidget {
  final Map<String, dynamic> pedido;
  final VoidCallback onRejeitar;

  const _PedidoOverlay({
    required this.pedido,
    required this.onRejeitar,
  });

  @override
  State<_PedidoOverlay> createState() => _PedidoOverlayState();
}

class _PedidoOverlayState extends State<_PedidoOverlay> {
  final _supabase = Supabase.instance.client;
  double? _distMotoboyLojaKm;
  double _precoDinamico = 0;
  int _segundos = 30;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _segundos = (_segundos - 1).clamp(0, 30));
    });
    _carregarDados();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      final loja = widget.pedido['lojas'];
      if (loja != null &&
          loja['latitude'] != null &&
          loja['longitude'] != null) {
        final distM = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          (loja['latitude'] as num).toDouble(),
          (loja['longitude'] as num).toDouble(),
        );
        if (mounted) setState(() => _distMotoboyLojaKm = distM / 1000);
      }
    } catch (_) {}

    try {
      final data = await _supabase
          .from('configuracoes')
          .select('valor')
          .eq('chave', 'preco_dinamico_entregador')
          .maybeSingle();
      final v =
          double.tryParse((data as Map?)?['valor']?.toString() ?? '0') ?? 0;
      if (mounted) setState(() => _precoDinamico = v);
    } catch (_) {}
  }

  void _abrirDetalhes() {
    widget.onRejeitar();
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => RotaDisponivelScreen(pedido: widget.pedido),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0F14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1A56DB), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header: label + countdown
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A56DB),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                      ),
                    ),
                    child: Row(children: [
                      const Icon(Icons.notifications_active,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Novo Pedido Disponível!',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(12)),
                        child: Text('${_segundos}s',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ),
                    ]),
                  ),

                  // PedidoCardWidget — toque navega para detalhes
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                    child: PedidoCardWidget(
                      pedido: widget.pedido,
                      distMotoboyLojaKm: _distMotoboyLojaKm,
                      precoDinamico: _precoDinamico,
                      onTap: _abrirDetalhes,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── AuthGate ─────────────────────────────────────────────────────────────────

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _verificarAuth();
  }

  Future<void> _verificarAuth() async {
    final tela = await _resolverTela();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => tela),
    );
  }

  // Wrapper fino: aplica o gate obrigatório de DeviceSetupScreen (bateria +
  // autoinício MIUI) por cima de qualquer resultado — vale tanto pra quem
  // ainda vai logar quanto pra quem reabre o app com sessão já existente
  // (esse segundo caminho pula direto pra EntregadorHomeScreen/HomeScreen
  // sem passar por PermissoesScreen nenhuma, então sem esse wrapper aqui o
  // gate nunca apareceria de novo depois do primeiro login). Só mostra uma
  // vez — DeviceSetupScreen.jaConcluido() vira true depois da 1ª conclusão.
  Future<Widget> _resolverTela() async {
    final tela = await _resolverTelaSemSetup();
    if (!await DeviceSetupScreen.jaConcluido()) {
      return DeviceSetupScreen(next: tela);
    }
    // Entregador já concluiu o setup obrigatório ANTES da etapa de
    // Full-Screen-Intent existir (jaConcluido() é uma flag única e global
    // — quem já passou por ela nunca mais vê DeviceSetupScreen, e por
    // consequência nunca seria perguntado sobre essa permissão
    // especificamente). Achado em auditoria 2026-09-02: pra apps não
    // classificados como chamada/alarme (nosso caso), o Google NÃO
    // concede essa permissão automaticamente desde 22/01/2025 — sem
    // perguntar ativamente, boa parte da base instalada nunca teria essa
    // permissão, mesmo com todo o resto do fluxo (som/vibração/loop)
    // funcionando normal. Não-bloqueante — "Agora não" sempre disponível,
    // ver fullscreen_intent_reprompt_screen.dart. Só perguntado uma vez
    // (jaFoiPerguntado()), independente de session != null aqui porque
    // não faz sentido perguntar antes do login existir.
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null &&
        !await FullScreenIntentPermissionService.isGranted() &&
        !await FullScreenIntentPermissionService.jaFoiPerguntado()) {
      return FullScreenIntentRepromptScreen(next: tela);
    }
    return tela;
  }

  Future<Widget> _resolverTelaSemSetup() async {
    final locPerm = await Geolocator.checkPermission();
    final locFaltando = locPerm == LocationPermission.denied ||
        locPerm == LocationPermission.deniedForever;

    final notifOk = await FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled() ??
        true;
    final notifFaltando = !notifOk;

    bool bateriaFaltando = false;
    try {
      final ignorandoOtimizacao =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      bateriaFaltando = !ignorandoOtimizacao;
    } catch (_) {}

    final precisaPermissoes = locFaltando || notifFaltando || bateriaFaltando;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      if (precisaPermissoes) return PermissoesScreen(next: const LoginScreen());
      return const LoginScreen();
    }

    await NotificationService.saveFcmToken(session.user.id);

    // Assinatura realtime do alerta sonoro (nível de app, não de tela) —
    // precisa existir desde já, independente de qual tela vai ser mostrada
    // a seguir, senão o loop nunca saberia sozinho quando "não sobra mais
    // pedido disponível" se o entregador estiver em Home/Aceitos/Vagas no
    // momento em que o último pedido expira. Idempotente, seguro chamar
    // toda vez que o AuthGate resolve a tela.
    // ignore: unawaited_futures
    AlertaPedidoService.instance.escutar(session.user.id);

    try {
      final e = await Supabase.instance.client
          .from('entregadores')
          .select('disponivel, status_cadastro, aprovado, status')
          .eq('id', session.user.id)
          .single();

      final statusCadastro = e['status_cadastro']?.toString() ?? '';
      final aprovado = e['aprovado'] == true;
      final status = e['status']?.toString() ?? '';

      if (aprovado || status == 'ativo' || statusCadastro == 'aprovado') {
        if (e['disponivel'] == true) {
          // App estava fechado/morto e foi aberto pelo fullScreenIntent da
          // notificação de novo pedido (não por toque manual) — nesse caso
          // onDidReceiveNotificationResponse (notification_service.dart)
          // não dispara, porque o plugin de notificações locais ainda não
          // tinha listener registrado no momento em que o Android lançou a
          // Activity. getNotificationAppLaunchDetails() é o jeito
          // documentado do flutter_local_notifications de recuperar esse
          // dado depois, direto no cold start.
          try {
            final detalhes = await FlutterLocalNotificationsPlugin()
                .getNotificationAppLaunchDetails();
            if (detalhes?.didNotificationLaunchApp == true &&
                detalhes?.notificationResponse?.payload == 'novo_pedido') {
              // App estava morto/background e só ficou "vivo" de verdade
              // agora — é aqui, o mais cedo possível, que dá pra iniciar o
              // loop (antes disso não existia engine Flutter rodando pra
              // tocar nada). Sem await: não atrasa a navegação esperando o
              // player carregar.
              // ignore: unawaited_futures
              AlertaPedidoService.instance.iniciar();
              return const PedidosDisponiveisScreen();
            }
          } catch (_) {}
          return const EntregadorHomeScreen();
        }
        return const HomeScreen();
      }

      return const AguardoAprovacaoScreen();
    } catch (_) {
      return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
