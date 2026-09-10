import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/volume_service.dart';
import 'screens/login_screen.dart';
import 'screens/pedidos_disponiveis_screen.dart';
import 'screens/rota_disponivel_screen.dart';
import 'screens/extrato_screen.dart';
import 'services/notification_service.dart';
import 'services/tela_pos_login_service.dart';
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
    if (tipo != 'avaliar_app' &&
        tipo != 'indicacao' &&
        tipo != 'periodico' &&
        tipo != 'pedido_realocado') {
      // Cobre 'nova_rota', 'novo_pedido' e qualquer tipo desconhecido —
      // mesmo fallback de sempre (else final antigo).
      //
      // Volume forçado (Mídia E Alarme, ver VolumeService/MainActivity.kt)
      // ANTES de mostrar, pro canal já tocar no máximo.
      //
      // MUDANÇA DE ARQUITETURA (2026-09-03): som/vibração/insistência são
      // 100% responsabilidade do CANAL nativo agora (FLAG_INSISTENT +
      // AudioAttributesUsage.alarm, ver notification_service.dart v8) —
      // toca sozinho, sem depender de nenhum processo de app vivo pra
      // manter o alerta soando. AlertaPedidoService (loop de app via
      // just_audio) foi removido do projeto por causa disso — não existe
      // mais loop nenhum pra iniciar aqui nem em lugar nenhum.
      // showNovoPedidoLocal()/showNovaRotaLocal() cobrem o alerta inteiro
      // sozinhas, incluindo com o app morto (é exatamente pra isso que
      // esse handler existe).
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
    } else if (tipo == 'pedido_realocado') {
      // Aviso (bug real corrigido 2026-09-10), não alarme — sem
      // VolumeService.forcarVolumeMidiaMaximo(), diferente do ramo padrão
      // acima (novo_pedido/nova_rota são ofertas reais pra aceitar).
      await NotificationService.showPedidoRealocadoLocal(
        message.data['numero']?.toString() ?? '',
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

      // Filtro de raio (bug real, 2026-09-05): esse overlay é um segundo
      // caminho de "novo pedido disponível", totalmente separado da tela
      // Disponíveis (pedidos_disponiveis_screen.dart, já corrigida) —
      // reage a QUALQUER pedido pronto do sistema, sem checar distância
      // nenhuma (a distância calculada em _PedidoOverlayState é só pra
      // EXIBIR "X km", nunca filtrou nada). Mesma config/fórmula usada lá
      // (despacho_raio_busca_km via Geolocator.distanceBetween). Fail-
      // closed: sem lat/lng do pedido ou sem posição própria resolvida,
      // não mostra o overlay.
      final lat = double.tryParse(data['latitude']?.toString() ?? '');
      final lng = double.tryParse(data['longitude']?.toString() ?? '');
      if (lat == null || lng == null) return;

      final Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium);
      } catch (_) {
        return;
      }

      double raioBuscaKm = 32.0;
      try {
        final cfg = await _supabase
            .from('configuracoes')
            .select('valor')
            .eq('chave', 'despacho_raio_busca_km')
            .maybeSingle();
        raioBuscaKm =
            double.tryParse((cfg as Map?)?['valor']?.toString() ?? '32') ??
                32.0;
      } catch (_) {}

      final distKm =
          Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng) /
              1000;
      if (distKm > raioBuscaKm) return;

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

class _AuthGateState extends State<AuthGate> with SingleTickerProviderStateMixin {
  // Sequência da Fase 2 (2026-09-09, ajuste de duração a pedido do
  // usuário): a Fase 1 nativa (flutter_native_splash) foi removida por
  // completo — volta ao padrão do Flutter, ver commit "revert" de
  // 2026-09-08 — aqui, sob controle total do Flutter, mostramos a marca
  // em 2 imagens: Imagem A (logo_splash.png, ícone + @pedeletsgo +
  // #CadaKmUmSonho) por 2s, uma transição combinada (A esmaece enquanto B
  // aparece crescendo) e Imagem B (logo_parceiro_letsgo.png, "PARCEIRO
  // LET'S GO DELIVERY") por 2s.
  //
  // Total de 4.4s: 2s + 0.4s de transição própria + 2s — a transição
  // continua consumindo tempo À PARTE dos 2 holds (mesmo critério já
  // usado antes: descontar do hold encurtaria o tempo de leitura de cada
  // imagem). Testado com captura de frames em tempo real nesses tempos
  // maiores antes de reportar como pronto.
  static const _holdA = Duration(milliseconds: 2000);
  static const _transicao = Duration(milliseconds: 400);
  // holdB = 2000ms: não precisa de campo próprio, é o que sobra de
  // duracaoTotalFase2 depois de _t2 (ver build()).
  static const duracaoTotalFase2 = Duration(
    milliseconds: 2000 + 400 + 2000, // holdA + transicao + holdB
  );

  static const _escalaInicialB = 0.72;

  late final AnimationController _splashController;
  bool _iniciouSequenciaVisual = false;
  // Resolve só quando a sequência visual de fato TERMINA de tocar na tela
  // (não um timer fixo contado desde initState) — ver _iniciarSequenciaVisual.
  final Completer<void> _sequenciaVisualCompleta = Completer<void>();

  double get _t1 =>
      _holdA.inMilliseconds / duracaoTotalFase2.inMilliseconds;
  double get _t2 =>
      (_holdA.inMilliseconds + _transicao.inMilliseconds) /
      duracaoTotalFase2.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _splashController = AnimationController(
      vsync: this,
      duration: duracaoTotalFase2,
    );
    _verificarAuth();
  }

  // precacheImage precisa de BuildContext válido (Theme/MediaQuery já
  // resolvidos) — não dá pra chamar em initState(), por isso aqui.
  // _iniciouSequenciaVisual evita disparar de novo em rebuilds.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_iniciouSequenciaVisual) {
      _iniciouSequenciaVisual = true;
      _iniciarSequenciaVisual();
    }
  }

  @override
  void dispose() {
    _splashController.dispose();
    super.dispose();
  }

  // Decodificar logo_splash.png (730KB) + logo_parceiro_letsgo.png (564KB)
  // pode levar tempo perceptível num aparelho mais fraco / 1ª abertura. O
  // AnimationController roda no relógio real desde que forward() é
  // chamado, independente de a imagem já estar pintável — se o decode
  // atrasar, a Imagem A pode nunca chegar a ser exibida (confirmado em
  // teste local: sem esse precache, o 1º frame pintado já mostrava a
  // Imagem B pronta, com a fase A inteira "pulada"). Por isso: só chama
  // forward() depois que as duas imagens já estão prontas pra pintar.
  Future<void> _iniciarSequenciaVisual() async {
    await Future.wait([
      precacheImage(const AssetImage('assets/images/logo_splash.png'), context),
      precacheImage(
          const AssetImage('assets/images/logo_parceiro_letsgo.png'), context),
    ]);
    if (!mounted) {
      _sequenciaVisualCompleta.complete();
      return;
    }
    try {
      await _splashController.forward().orCancel;
    } on TickerCanceled {
      // widget foi descartado (dispose) antes da animação terminar - ok.
    }
    if (!_sequenciaVisualCompleta.isCompleted) {
      _sequenciaVisualCompleta.complete();
    }
  }

  // Duração mínima = duração real da sequência visual (2026-09-08): garante
  // que as 2 imagens + transição sejam sempre exibidas por inteiro, mesmo
  // quando resolverTelaPosLogin() termina quase instantaneamente (sessão
  // já em cache) — e também quando o PRÓPRIO precache das imagens atrasa
  // o início da animação (ver _iniciarSequenciaVisual). Future.wait espera
  // o MAIOR dos dois tempos — a checagem real de auth/permissões nunca
  // fica mais lenta por causa disso, só a exibição da marca é que nunca
  // corta a sequência pela metade.
  //
  // resolverTelaPosLogin() (services/tela_pos_login_service.dart, extraído
  // em 2026-09-09) é a MESMA função usada por LoginScreen depois de um
  // login ativo — fonte única do gate de cadastro/permissões, pra cold
  // start e login ativo nunca poderem divergir de novo.
  Future<void> _verificarAuth() async {
    final resultados = await Future.wait([
      resolverTelaPosLogin(),
      _sequenciaVisualCompleta.future,
    ]);
    final tela = resultados[0] as Widget;
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => tela),
    );
  }

  // Fundo preto igual ao splash nativo (flutter_native_splash) — sem isso,
  // o usuário veria a logo por uma fração de segundo e depois um spinner
  // genérico enquanto _verificarAuth() resolve (sessão + permissões +
  // setup de dispositivo, pode levar mais que só o tempo do splash
  // nativo). Sem indicador de progresso nenhum de propósito — a transição
  // pra tela final deve parecer contínua, não "logo, depois loading".
  //
  // Imagem A e Imagem B ficam as duas sempre montadas (Opacity, não
  // condicional) desde o 1º frame — evita um "pop-in" de decodificação no
  // meio da transição, e faz o precache de ambas acontecer em paralelo com
  // a Fase 1 nativa.
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: AnimatedBuilder(
          animation: _splashController,
          builder: (context, _) {
            final v = _splashController.value;
            double opacidadeA;
            double opacidadeB;
            double escalaB;
            if (v <= _t1) {
              opacidadeA = 1;
              opacidadeB = 0;
              escalaB = _escalaInicialB;
            } else if (v >= _t2) {
              opacidadeA = 0;
              opacidadeB = 1;
              escalaB = 1;
            } else {
              final p = Curves.easeOut.transform((v - _t1) / (_t2 - _t1));
              opacidadeA = 1 - p;
              opacidadeB = p;
              escalaB = _escalaInicialB + (1 - _escalaInicialB) * p;
            }
            return Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: opacidadeA,
                  child: const Image(
                    image: AssetImage('assets/images/logo_splash.png'),
                    width: 260,
                  ),
                ),
                Opacity(
                  opacity: opacidadeB,
                  child: Transform.scale(
                    scale: escalaB,
                    child: const Image(
                      image: AssetImage('assets/images/logo_parceiro_letsgo.png'),
                      width: 260,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
