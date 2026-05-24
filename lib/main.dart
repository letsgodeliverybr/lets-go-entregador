import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/entregador_home_screen.dart';
import 'screens/adm_screen.dart';
import 'screens/cliente_screen.dart';

const supabaseUrl = 'SUA_URL_AQUI';
const supabaseAnonKey = 'SUA_CHAVE';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
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
          seedColor: const Color(0xFFFF6B00),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        '/entregador': (_) => const EntregadorHomeScreen(),
        '/adm': (_) => const AdmScreen(),
        '/cliente': (_) => const ClienteScreen(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Let's Go Delivery"),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delivery_dining, size: 80, color: Color(0xFFFF6B00)),
            const SizedBox(height: 16),
            const Text("Let's Go Delivery", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.delivery_dining),
              label: const Text('Entregador'),
              onPressed: () => Navigator.of(context).pushNamed('/entregador'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Painel ADM'),
              onPressed: () => Navigator.of(context).pushNamed('/adm'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.person),
              label: const Text('App Cliente'),
              onPressed: () => Navigator.of(context).pushNamed('/cliente'),
            ),
          ],
        ),
      ),
    );
  }
}
