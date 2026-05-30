import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/entregador_home_screen.dart';
import 'screens/pedidos_disponiveis_screen.dart';
import 'screens/extrato_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://astbkmpegcmqljltmdpx.supabase.co',
    anonKey: 'sb_publishable_8ocBGGO6EM8GYlg-6HBdmQ_LA6VDL9O',
  );

  await NotificationService.initLocal();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _resolverTelaInicial() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const LoginScreen();
    try {
      final e = await Supabase.instance.client
          .from('entregadores')
          .select('disponivel')
          .eq('id', session.user.id)
          .single();
      if (e['disponivel'] == true) return const EntregadorHomeScreen();
    } catch (_) {}
    return const HomeScreen();
  }

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
      home: FutureBuilder<Widget>(
        future: _resolverTelaInicial(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              backgroundColor: Color(0xFF0D0F14),
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF1A56DB)),
              ),
            );
          }
          return snap.data!;
        },
      ),
      routes: {
        '/pedidos': (context) => const PedidosDisponiveisScreen(),
        '/login': (context) => const LoginScreen(),
        '/extrato': (context) => const ExtratoScreen(),
      },
    );
  }
}
