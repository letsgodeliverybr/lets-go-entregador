import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: _firebaseOptions);
  await NotificationService.initLocal();
  final tipo = message.data['tipo']?.toString() ?? '';
  if (tipo == 'nova_rota') {
    await NotificationService.showNovaRotaLocal();
  } else {
    await NotificationService.showNovoPedidoLocal();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: _firebaseOptions);
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  await Supabase.initialize(
    url: 'https://astbkmpegcmqljltmdpx.supabase.co',
    anonKey: 'sb_publishable_8ocBGGO6EM8GYlg-6HBdmQ_LA6VDL9O',
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
  final _audioPlayer = AudioPlayer();
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

    if (novosIds.isEmpty) return;

    // Fetch the first new pedido with lojas join
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
    _tocarSom();
  }

  Future<void> _tocarSom() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setAudioSource(
        ConcatenatingAudioSource(
          children: List.generate(
            2,
            (_) => AudioSource.asset('assets/sounds/letsgo.wav'),
          ),
        ),
      );
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('[Overlay] Áudio falhou: $e');
    }
  }

  void _fecharOverlay() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _audioPlayer.stop();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cancelarStream();
    _fecharOverlay();
    _audioPlayer.dispose();
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
    final precisaPermissoes = locPerm == LocationPermission.denied;

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
