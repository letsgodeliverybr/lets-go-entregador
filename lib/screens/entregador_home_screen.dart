import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/location_service.dart';
import '../services/tracking_service.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'drawer_screen.dart';
import 'login_screen.dart';
import 'pedidos_aceitos_screen.dart';

class EntregadorHomeScreen extends StatefulWidget {
  const EntregadorHomeScreen({super.key});
  @override
  State<EntregadorHomeScreen> createState() => _EntregadorHomeScreenState();
}

class _EntregadorHomeScreenState extends State<EntregadorHomeScreen> {
  final _supabase = Supabase.instance.client;
  final _audioPlayer = AudioPlayer();
  Map<String, dynamic>? _entregador;
  Timer? _statsTimer;
  RealtimeChannel? _pedidosChannel;
  bool _online = TrackingService.ativo;
  double _saldoDia = 0;
  int _entregasHoje = 0;
  LatLng? _posicaoAtual;
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Card de novo pedido
  Map<String, dynamic>? _pedidoPendente;
  bool _temPedidoEmAndamento = false;
  bool _aceitando = false;

  // Pedidos em andamento para pins no mapa
  List<Map<String, dynamic>> _pedidosEmAndamento = [];

  @override
  void initState() {
    super.initState();
    _carregarEntregador(); // chama _buscarPedidoPendenteInicial ao final
    _carregarStats();
    _verificarPedidoEmAndamento();
    _carregarPedidosEmAndamento();
    _statsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _carregarStats();
      _carregarPedidosEmAndamento();
    });
    _iniciarLocalizacaoPassiva();
    _assinarPedidosRealtime();
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
      // Depois de saber se está online, busca pedido pendente inicial
      _buscarPedidoPendenteInicial();
    } catch (_) {}
  }

  // Busca pedido pronto/disponível já existente ao abrir a tela
  Future<void> _buscarPedidoPendenteInicial() async {
    if (!_online) return;
    await _verificarPedidoEmAndamento();
    if (_temPedidoEmAndamento || _pedidoPendente != null) return;
    try {
      final data = await _supabase
          .from('pedidos')
          .select('*, lojas(nome, endereco, latitude, longitude)')
          .inFilter('status', ['pronto', 'disponivel'])
          .order('pronto_em', ascending: true)
          .limit(1)
          .maybeSingle();
      if (data != null && mounted && _pedidoPendente == null) {
        setState(() => _pedidoPendente = data);
      }
    } catch (_) {}
  }

  // Busca pedidos em andamento para exibir pins no mapa
  Future<void> _carregarPedidosEmAndamento() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      // Filtra estritamente por motoboy_id OU entregador_id do usuário logado
      final data = await _supabase
          .from('pedidos')
          .select('id, status, latitude, longitude, endereco, numero')
          .or('motoboy_id.eq.${user.id},entregador_id.eq.${user.id}')
          .inFilter('status', ['aceito', 'no_local', 'chegou_local', 'em_rota']);
      // Filtra null de lat/lng no lado do cliente para evitar syntax issue no PostgREST
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

  Future<void> _verificarPedidoEmAndamento() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await _supabase
          .from('pedidos')
          .select('id')
          .or('motoboy_id.eq.${user.id},entregador_id.eq.${user.id}')
          .inFilter('status', ['aceito', 'no_local', 'chegou_local', 'em_rota', 'retornando'])
          .limit(1);
      if (mounted) setState(() => _temPedidoEmAndamento = data.isNotEmpty);
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
      if (mounted) setState(() => _pedidoPendente = null);
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

  // ── Realtime ─────────────────────────────────────────────────────────────────

  void _assinarPedidosRealtime() {
    _pedidosChannel = _supabase
        .channel('home-pedidos-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pedidos',
          callback: (payload) {
            final s = payload.newRecord['status']?.toString() ?? '';
            if (s == 'pronto' || s == 'disponivel') {
              _buscarEMostrarPedido(payload.newRecord['id'].toString());
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pedidos',
          callback: (payload) {
            final novo = payload.newRecord['status']?.toString() ?? '';
            final antigo = payload.oldRecord['status']?.toString() ?? '';
            if ((novo == 'pronto' || novo == 'disponivel') && antigo != novo) {
              _buscarEMostrarPedido(payload.newRecord['id'].toString());
            }
          },
        )
        .subscribe();
  }

  Future<void> _buscarEMostrarPedido(String pedidoId) async {
    if (!_online || _temPedidoEmAndamento || _pedidoPendente != null) return;
    try {
      final data = await _supabase
          .from('pedidos')
          .select('*, lojas(nome, endereco, latitude, longitude)')
          .eq('id', pedidoId)
          .inFilter('status', ['pronto', 'disponivel'])
          .maybeSingle();
      if (data == null || !mounted) return;
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setAsset('assets/sounds/novo_pedido.mp3');
        await _audioPlayer.play();
      } catch (_) {}
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 300));
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _pedidoPendente = data);
    } catch (_) {}
  }

  // Toque no card = aceitar
  Future<void> _aceitarPedido() async {
    final pedido = _pedidoPendente;
    if (pedido == null || _aceitando) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _aceitando = true);
    try {
      final result = await _supabase
          .from('pedidos')
          .update({
            'status': 'aceito',
            'status_detalhado': 'aceito',
            'aceito_em': DateTime.now().toIso8601String(),
            'motoboy_id': user.id,
            'entregador_id': user.id,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', pedido['id'])
          .inFilter('status', ['pronto', 'disponivel'])
          .select();

      if (!mounted) return;

      if (result.isEmpty) {
        setState(() { _pedidoPendente = null; _aceitando = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pedido já foi aceito por outro entregador'),
          backgroundColor: Colors.orange,
        ));
        return;
      }

      setState(() { _pedidoPendente = null; _temPedidoEmAndamento = true; _aceitando = false; });
      HapticFeedback.heavyImpact();
      _carregarPedidosEmAndamento();

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PedidosAceitosScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _aceitando = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // Swipe horizontal = recusar
  void _recusarPedido() => setState(() => _pedidoPendente = null);

  double _calcularDistancia(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _pedidosChannel?.unsubscribe();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

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
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
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
                        final status = p['status']?.toString() ?? '';
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

          // OVERLAY ESCURO quando card está visível
          if (_pedidoPendente != null && _online)
            Positioned.fill(
              child: GestureDetector(
                onTap: _recusarPedido,
                child: Container(color: Colors.black.withOpacity(0.55)),
              ),
            ),

          // CARD NOVO PEDIDO — centralizado, toque aceita, swipe recusa
          if (_pedidoPendente != null && _online)
            Positioned(
              left: 16, right: 16,
              top: 0, bottom: 0,
              child: Center(
                child: Dismissible(
                  key: ValueKey(_pedidoPendente!['id']),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) => _recusarPedido(),
                  background: _buildSwipeBackground(Alignment.centerLeft),
                  secondaryBackground: _buildSwipeBackground(Alignment.centerRight),
                  child: GestureDetector(
                    onTap: _aceitando ? null : _aceitarPedido,
                    child: _buildCardPedidoPendente(_pedidoPendente!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────────

  Widget _buildSwipeBackground(Alignment align) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFef4444).withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFef4444).withOpacity(0.4)),
      ),
      child: Align(
        alignment: align,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.close, color: Color(0xFFef4444), size: 24),
              SizedBox(width: 6),
              Text('Recusar', style: TextStyle(color: Color(0xFFef4444), fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardPedidoPendente(Map<String, dynamic> pedido) {
    final taxa = double.tryParse(pedido['taxa_entrega']?.toString() ?? '0') ?? 0;
    final taxaBase = taxa;
    final taxaReal = taxa * 1.20;
    final numero = pedido['numero'] ?? pedido['id'].toString().substring(0, 6);
    final pontos = pedido['pontos'] ?? 4;
    final distanciaKm = double.tryParse(pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final loja = pedido['lojas'];
    final nomeLoja = loja?['nome']?.toString() ?? pedido['nome_loja']?.toString() ?? 'Estabelecimento';

    double distMotoboyLoja = 0;
    if (_posicaoAtual != null && loja != null) {
      final lat = (loja['latitude'] ?? loja['lat']) as num?;
      final lng = (loja['longitude'] ?? loja['lng']) as num?;
      if (lat != null && lng != null) {
        distMotoboyLoja = _calcularDistancia(
          _posicaoAtual!.latitude, _posicaoAtual!.longitude,
          lat.toDouble(), lng.toDouble(),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D35)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 24)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Dica de interação
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.swipe, color: Colors.white38, size: 14),
              const SizedBox(width: 4),
              const Text('Toque para aceitar · Deslize para recusar',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
            const SizedBox(height: 10),

            // Linha 1: ícone loja + nome + número
            Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A56DB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.store, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(nomeLoja,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('#$numero', style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ]),
            const SizedBox(height: 10),

            // Linha 2: km de onde você está
            Row(children: [
              const Icon(Icons.location_on, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                distMotoboyLoja > 0
                    ? '${distMotoboyLoja.toStringAsFixed(2)} km de onde você está'
                    : '— km de onde você está',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ]),
            const SizedBox(height: 8),

            // Linha 3: pontos
            Row(children: [
              const Icon(Icons.star_border, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text('$pontos pontos', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
            const SizedBox(height: 8),

            // Linha 4: tag Bag térmica
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white),
              ),
              child: const Text('Bag térmica', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
            const SizedBox(height: 12),

            // Linha 5: rota + km | preços
            Row(children: [
              const Icon(Icons.route_outlined, color: Colors.white70, size: 16),
              const SizedBox(width: 4),
              Text('${distanciaKm.toStringAsFixed(2)} km',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              if (taxaBase > 0) ...[
                Text('R\$${taxaBase.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.red, fontSize: 13,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.red,
                    )),
                const SizedBox(width: 8),
              ],
              Text('R\$${taxaReal.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),

            // Loading ao aceitar
            if (_aceitando) ...[
              const SizedBox(height: 14),
              const Center(
                child: SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Color(0xFF1A56DB), strokeWidth: 2.5)),
              ),
            ],
          ],
        ),
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
