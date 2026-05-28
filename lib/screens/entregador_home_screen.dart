import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/location_service.dart';
import '../services/tracking_service.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'drawer_screen.dart';
import 'login_screen.dart';

class EntregadorHomeScreen extends StatefulWidget {
  const EntregadorHomeScreen({super.key});
  @override
  State<EntregadorHomeScreen> createState() => _EntregadorHomeScreenState();
}

class _EntregadorHomeScreenState extends State<EntregadorHomeScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _entregador;
  Timer? _statsTimer;
  bool _online = TrackingService.ativo;
  double _saldoDia = 0;
  int _entregasHoje = 0;
  LatLng? _posicaoAtual;
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Pedidos em andamento para pins no mapa
  List<Map<String, dynamic>> _pedidosEmAndamento = [];

  @override
  void initState() {
    super.initState();
    _carregarEntregador();
    _carregarStats();
    _carregarPedidosEmAndamento();
    _statsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _carregarStats();
      _carregarPedidosEmAndamento();
    });
    _iniciarLocalizacaoPassiva();
  }

  Future<void> _carregarEntregador() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final response = await _supabase.from('entregadores').select().eq('id', user.id).single();
      setState(() {
        _entregador = response;
        if (!TrackingService.ativo) _online = response['disponivel'] == true;
      });
      if (_online && !TrackingService.ativo) await TrackingService.iniciar(user.id);
    } catch (_) {}
  }

  Future<void> _carregarPedidosEmAndamento() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await _supabase
          .from('pedidos')
          .select('id, status, latitude, longitude, endereco, numero')
          .or('motoboy_id.eq.${user.id},entregador_id.eq.${user.id}')
          .inFilter('status', ['aceito', 'no_local', 'chegou_local', 'em_rota']);
      final lista = List<Map<String, dynamic>>.from(data)
          .where((p) => p['latitude'] != null && p['longitude'] != null)
          .toList();
      if (mounted) setState(() => _pedidosEmAndamento = lista);
    } catch (_) {}
  }

  Future<void> _carregarStats() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final hoje = DateTime.now();
      final inicioDia = DateTime(hoje.year, hoje.month, hoje.day).toIso8601String();
      final pedidos = await _supabase
          .from('pedidos')
          .select('taxa_entrega')
          .eq('motoboy_id', user.id)
          .eq('status', 'finalizado')
          .gte('finalizado_em', inicioDia);
      final lista = List<Map<String, dynamic>>.from(pedidos);
      double total = 0;
      for (final p in lista) {
        total += (double.tryParse(p['taxa_entrega']?.toString() ?? '0') ?? 0);
      }
      if (mounted) setState(() { _saldoDia = total; _entregasHoje = lista.length; });
    } catch (_) {}
  }

  void _iniciarLocalizacaoPassiva() {
    LocationService.getPositionStream().listen((pos) {
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => _posicaoAtual = ll);
      try { _mapController.move(ll, _mapController.camera.zoom); } catch (_) {}
    });
  }

  void _toggleOnline(bool value) async {
    setState(() => _online = value);
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    if (value) {
      await TrackingService.iniciar(user.id);
      final pos = await LocationService.getCurrentPosition();
      if (pos != null && mounted) {
        final ll = LatLng(pos.latitude, pos.longitude);
        setState(() => _posicaoAtual = ll);
        try { _mapController.move(ll, 15); } catch (_) {}
      }
    } else {
      await TrackingService.ficarOffline(user.id);
    }
  }

  Future<void> _logout() async {
    final user = _supabase.auth.currentUser;
    if (user != null) await TrackingService.ficarOffline(user.id);
    _statsTimer?.cancel();
    await _supabase.auth.signOut();
    if (mounted) Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nomeCompleto = _entregador?['nome']?.toString() ?? '';
    final nome = nomeCompleto.isNotEmpty ? nomeCompleto.split(' ').first : 'Motoboy';
    final pos = _posicaoAtual ?? const LatLng(-21.1775, -47.8103);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0D0F14),
      drawer: DrawerScreen(onLogout: _logout),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 0),
      body: Stack(
        children: [

          // MAPA
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: pos, initialZoom: 15),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),

              // Pins dos pedidos em andamento
              if (_pedidosEmAndamento.isNotEmpty)
                MarkerLayer(
                  markers: _pedidosEmAndamento
                      .where((p) => p['latitude'] != null && p['longitude'] != null)
                      .map((p) {
                        final lat = (p['latitude'] as num).toDouble();
                        final lng = (p['longitude'] as num).toDouble();
                        final numero = p['numero']?.toString() ?? '—';
                        return Marker(
                          point: LatLng(lat, lng),
                          width: 56, height: 60,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A56DB),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(.5), blurRadius: 6)],
                                ),
                                child: const Icon(Icons.location_on, color: Colors.white, size: 18),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A56DB),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('#$numero',
                                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                ),

              // Pin do motoboy
              if (_posicaoAtual != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _posicaoAtual!,
                    width: 64, height: 90,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: _online ? const Color(0xFF22c55e) : const Color(0xFF475569),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 8)],
                          ),
                          child: const Center(child: Text('🛵', style: TextStyle(fontSize: 22))),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _online ? const Color(0xFF22c55e) : const Color(0xFF475569),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(nome,
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ]),
            ],
          ),

          // OVERLAY ESCURO TOPO
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(.7), Colors.transparent],
                ),
              ),
            ),
          ),

          // TOPBAR
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(8)),
                    child: const Center(child: Text('🛵', style: TextStyle(fontSize: 16))),
                  ),
                  const SizedBox(width: 8),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Lets Go', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    Text('DELIVERY', style: TextStyle(color: Color(0xFFf97316), fontSize: 8, letterSpacing: 2, fontWeight: FontWeight.w600)),
                  ]),
                  const Spacer(),
                  _buildToggleCompacto(),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(.1), shape: BoxShape.circle),
                      child: const Icon(Icons.menu, color: Colors.white, size: 20),
                    ),
                  ),
                ]),
              ),
            ),
          ),

          // CARDS SALDO E ENTREGAS
          Positioned(
            top: 90, left: 16, right: 16,
            child: Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161820).withOpacity(.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2a2d3a)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Saldo do dia', style: TextStyle(color: Color(0xFF94a3b8), fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('R\$ ${_saldoDia.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161820).withOpacity(.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2a2d3a)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Entregas hoje', style: TextStyle(color: Color(0xFF94a3b8), fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('$_entregasHoje',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ]),
          ),

          // BOTÕES DIREITA: CHAT + CENTRALIZAR
          Positioned(
            bottom: 160, right: 16,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: _abrirChat,
                child: Stack(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22c55e),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(.3), blurRadius: 8)],
                    ),
                    child: const Icon(Icons.chat_bubble, color: Colors.white, size: 20),
                  ),
                  Positioned(
                    top: 0, right: 0,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(color: Color(0xFFef4444), shape: BoxShape.circle),
                      child: const Center(child: Text('1',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () { if (_posicaoAtual != null) _mapController.move(_posicaoAtual!, 15); },
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161820),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF2a2d3a)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(.3), blurRadius: 8)],
                  ),
                  child: const Icon(Icons.my_location, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCompacto() {
    final cor = _online ? const Color(0xFF22c55e) : const Color(0xFFef4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor, width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(_online ? 'Online' : 'Offline',
            style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w700)),
        SizedBox(
          height: 28,
          child: Transform.scale(
            scale: 0.8,
            child: Switch(
              value: _online,
              onChanged: _toggleOnline,
              activeColor: const Color(0xFF22c55e),
              inactiveThumbColor: const Color(0xFFef4444),
              inactiveTrackColor: const Color(0xFFef4444).withOpacity(0.3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ]),
    );
  }

  void _abrirChat() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161820),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFF2a2d3a), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Icon(Icons.chat_bubble_outline, color: Color(0xFF22c55e), size: 48),
          const SizedBox(height: 12),
          const Text('Chat', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Em breve', style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14)),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
