import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/location_service.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'login_screen.dart';

class EntregadorHomeScreen extends StatefulWidget {
  const EntregadorHomeScreen({super.key});
  @override
  State<EntregadorHomeScreen> createState() => _EntregadorHomeScreenState();
}

class _EntregadorHomeScreenState extends State<EntregadorHomeScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _entregador;
  StreamSubscription? _locationSub;
  Timer? _locationTimer;
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _carregarEntregador();
  }

  Future<void> _carregarEntregador() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final response = await _supabase.from('entregadores').select().eq('id', user.id).single();
      setState(() => _entregador = response);
    } catch (_) {}
  }

  void _toggleOnline(bool value) {
    setState(() => _online = value);
    if (value) {
      _iniciarLocalizacao();
    } else {
      _pararLocalizacao();
    }
  }

  /// Envia lat/lng para a tabela entregadores
  Future<void> _enviarLocalizacao(String userId, double lat, double lng) async {
    try {
      await _supabase.from('entregadores').update({
        'lat': lat,
        'lng': lng,
        'disponivel': true, 'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (_) {}
  }

  void _iniciarLocalizacao() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // Stream de distância (dispara ao mover >= 5 m)
    _locationSub = LocationService.getPositionStream().listen((pos) {
      _enviarLocalizacao(user.id, pos.latitude, pos.longitude);
    });

    // Timer periódico garante envio a cada 10 segundos mesmo sem movimento
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        await _enviarLocalizacao(user.id, pos.latitude, pos.longitude);
      }
    });
  }

  void _pararLocalizacao() async {
    _locationSub?.cancel();
    _locationSub = null;
    _locationTimer?.cancel();
    _locationTimer = null;

    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase.from('entregadores').update({
        'disponivel': false, 'status': 'offline',
      }).eq('id', user.id);
    } catch (_) {}
  }

  Future<void> _logout() async {
    _pararLocalizacao();
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nome = _entregador?['nome'] ?? 'Entregador';
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        automaticallyImplyLeading: false,
        title: const Text('Home', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 0),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Olá, $nome!', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Lets Go Delivery', style: TextStyle(color: Color(0xFFF5A623), fontSize: 16)),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_online ? '🟢 Online' : '🔴 Offline',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_online ? 'Localização sendo enviada (10s)' : 'Ative para receber pedidos',
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                  Switch(
                    value: _online,
                    onChanged: _toggleOnline,
                    activeColor: const Color(0xFFFF6B00),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
