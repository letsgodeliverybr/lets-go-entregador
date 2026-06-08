import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/entregador_home_screen.dart';
import 'screens/pedidos_disponiveis_screen.dart';
import 'screens/extrato_screen.dart';
import 'screens/aguardo_aprovacao_screen.dart';
import 'services/notification_service.dart';

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const LoginScreen();

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

      // Aprovado → home normal
      if (aprovado || status == 'ativo' || statusCadastro == 'aprovado') {
        if (e['disponivel'] == true) return const EntregadorHomeScreen();
        return const HomeScreen();
      }

      // Qualquer outro status → aguardo aprovação
      return const AguardoAprovacaoScreen();

    } catch (_) {
      // Sem registro → login
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