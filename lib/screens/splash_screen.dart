import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'entregador_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final results = await Future.wait([
      Future.delayed(const Duration(milliseconds: 2500)),
      _resolverTela(),
    ]);
    if (!mounted) return;
    final tela = results[1] as Widget;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => tela,
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<Widget> _resolverTela() async {
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
    return const Scaffold(
      backgroundColor: Color(0xFF009C3B),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🇧🇷', style: TextStyle(fontSize: 120)),
            SizedBox(height: 24),
            Text(
              'VAI BRASIL!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'HEXA VEM 2026! 🏆',
              style: TextStyle(
                color: Color(0xFFFFDF00),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
