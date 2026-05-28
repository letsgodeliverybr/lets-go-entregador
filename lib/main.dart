import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/entregador_home_screen.dart';
import 'screens/pedidos_disponiveis_screen.dart';
import 'screens/extrato_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://astbkmpegcmqljltmdpx.supabase.co',
    anonKey: 'sb_publishable_8ocBGGO6EM8GYlg-6HBdmQ_LA6VDL9O',
  );

  // Firebase/NotificationService desativados até google-services.json ser configurado
  // await NotificationService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
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
      // Rota inicial
      home: session != null
          ? const EntregadorHomeScreen()
          : const LoginScreen(),
      // Rotas nomeadas
      routes: {
        '/pedidos': (context) => const PedidosDisponiveisScreen(),
        '/login':   (context) => const LoginScreen(),
        '/extrato': (context) => const ExtratoScreen(),
      },
    );
  }
}
