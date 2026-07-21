import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'services/som_pedido_service.dart';
import 'screens/login_screen.dart';
import 'screens/permissoes_screen.dart';
import 'screens/home_screen.dart';
import 'screens/entregador_home_screen.dart';
import 'screens/pedidos_disponiveis_screen.dart';
import 'screens/rota_disponivel_screen.dart';
import 'screens/extrato_screen.dart';
import 'screens/aguardo_aprovacao_screen.dart';
import 'services/notification_service.dart';
import 'widgets/pedido_card_widget.dart';
import 'utils/taxa_helper.dart' as th;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const _firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyCCPzZZWrLGmnUlzxo66h4tzn0I0HsV-10',
  appId: '1:935542418052:android:2e356ebfc7f8055f3eb0d1',
  messagingSenderId: '935542418052',
  projectId: 'lets-go-delivery-df74d',
  storageBucket: 'lets-go-delivery-df74d.firebasestorage.app',
);

// O payload agora sempre inclui um bloco `notification` (ver
// notify-novo-pedido/despacho-engine) — em background/killed o Android
// exibe a notificação sozinho, direto do sistema, sem invocar este
// handler. Ele só precisa existir e estar registrado (exigência do
// plugin); não deve mostrar nada aqui, senão duplica a notificação que o
// sistema já exibiu.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}

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
  RealtimeChannel? _channelDespachoFila;
  OverlayEntry? _overlayEntry;
  Timer? _overlayTimer;
  Set<String> _idsConhecidos = {};
  final Set<String> _despachoAtivos = {};
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
    _despachoAtivos.clear();
    _streamSub = _supabase
        .from('pedidos')
        .stream(primaryKey: ['id'])
        .eq('status', 'pronto')
        .listen(_onPedidosUpdate);
    _assinarRealtimeDespachoFila();
  }

  void _cancelarStream() {
    _streamSub?.cancel();
    _streamSub = null;
    _channelDespachoFila?.unsubscribe();
    _channelDespachoFila = null;
    SomPedidoService.pararLoop();
  }

  void _assinarRealtimeDespachoFila() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _channelDespachoFila = _supabase
        .channel('despacho-fila-global-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'despacho_fila',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'entregador_id',
            value: user.id,
          ),
          callback: (payload) {
            final status = payload.newRecord['status']?.toString() ?? '';
            final id = payload.newRecord['id']?.toString() ?? '';
            if (status == 'aguardando' && id.isNotEmpty) {
              _despachoAtivos.add(id);
              SomPedidoService.tocarLoop();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'despacho_fila',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'entregador_id',
            value: user.id,
          ),
          callback: (payload) {
            final status = payload.newRecord['status']?.toString() ?? '';
            final id = payload.newRecord['id']?.toString() ?? '';
            if (status != 'aguardando' && id.isNotEmpty) {
              _despachoAtivos.remove(id);
              _pararSomSeNadaDisponivel();
            }
          },
        )
        .subscribe();
  }

  // Loop só para quando não sobrar nenhum pedido/despacho ativo — evita
  // cortar o som se um pedido foi aceito/expirou mas outro ainda espera.
  void _pararSomSeNadaDisponivel() {
    if (_idsConhecidos.isEmpty && _despachoAtivos.isEmpty) {
      SomPedidoService.pararLoop();
    }
  }

  Future<void> _onPedidosUpdate(List<Map<String, dynamic>> lista) async {
    // Filter motoboy_id is null in Dart
    final disponiveis = lista
        .where((p) => (p['motoboy_id']?.toString() ?? '').isEmpty)
        .toList();

    final idsAtuais = disponiveis.map((p) => p['id'].toString()).toSet();

    if (_primeiraEmissao) {
      _idsConhecidos = idsAtuais;
      _primeiraEmissao = false;
      return;
    }

    final novosIds = idsAtuais.difference(_idsConhecidos);
    _idsConhecidos = idsAtuais;

    if (idsAtuais.isEmpty) {
      _pararSomSeNadaDisponivel();
      return;
    }

    if (novosIds.isEmpty) return;

    SomPedidoService.tocarLoop();

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

  Future<Widget> _resolverTela() async {
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
        if (e['disponivel'] == true) return const EntregadorHomeScreen();
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
