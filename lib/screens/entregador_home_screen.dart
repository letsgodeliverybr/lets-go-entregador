import 'dart:async';
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
import 'home_screen.dart';
import 'login_screen.dart';
import 'online_status_screen.dart';
import 'cadastro_aprovacao_screen.dart';
import 'aguardo_aprovacao_screen.dart';
import 'rota_disponivel_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/status_utils.dart' as su;
import '../utils/taxa_helper.dart' as th;

class EntregadorHomeScreen extends StatefulWidget {
  const EntregadorHomeScreen({super.key});
  @override
  State<EntregadorHomeScreen> createState() => _EntregadorHomeScreenState();
}

class _EntregadorHomeScreenState extends State<EntregadorHomeScreen> {
  final _supabase = Supabase.instance.client;
  final AudioPlayer _audioPlayer = AudioPlayer();
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

  // Rota disponível
  Map<String, dynamic>? _rotaAtual;
  RealtimeChannel? _channelRota;
  Timer? _rotaAutorecusaTimer;

  @override
  void initState() {
    super.initState();
    th.carregarFaixas();
    _carregarEntregador();
    _carregarStats();
    _carregarPedidosEmAndamento();
    _statsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _carregarStats();
      _carregarPedidosEmAndamento();
    });
    _iniciarLocalizacaoPassiva();
    _assinarRealtimeRota();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centrarMapaNoMotoboy());
  }

  Future<void> _centrarMapaNoMotoboy() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null && mounted) {
        final ll = LatLng(pos.latitude, pos.longitude);
        setState(() => _posicaoAtual = ll);
        try { _mapController.move(ll, 15); } catch (_) {}
      }
    } catch (_) {}
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
          .select('distancia_km, com_retorno, gorjeta')
          .eq('entregador_id', user.id)
          .eq('status', 'finalizado')
          .gte('updated_at', inicioDia);
      final lista = List<Map<String, dynamic>>.from(pedidos);
      double total = 0;
      for (final p in lista) {
        final km = double.tryParse(p['distancia_km']?.toString() ?? '0') ?? 0;
        final comRetorno = p['com_retorno'] == true;
        final gorjeta = double.tryParse(p['gorjeta']?.toString() ?? '0') ?? 0;
        total += th.calcularTaxaMotoboy(km, comRetorno, th.faixasGlobais) + gorjeta;
      }
      if (mounted) setState(() { _saldoDia = total; _entregasHoje = lista.length; });
    } catch (e) {
      debugPrint('EntregadorHomeScreen _carregarStats error: $e');
    }
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
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    setState(() => _online = value);
    try {
      if (value) {
        final ent = await _supabase
            .from('entregadores')
            .select('aprovado, status_cadastro')
            .eq('id', user.id)
            .single();
        final aprovado = ent['aprovado'] == true;
        final statusCadastro = ent['status_cadastro']?.toString() ?? 'pendente';

        if (!aprovado) {
          if (!mounted) return;
          setState(() => _online = false);
          if (statusCadastro == 'em_analise') {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AguardoAprovacaoScreen()));
          } else {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CadastroAprovacaoScreen()));
          }
          return;
        }

        await TrackingService.iniciar(user.id);
        final pos = await LocationService.getCurrentPosition();
        if (pos != null && mounted) {
          final ll = LatLng(pos.latitude, pos.longitude);
          setState(() => _posicaoAtual = ll);
          try { _mapController.move(ll, 15); } catch (_) {}
        }
      } else {
        await TrackingService.ficarOffline(user.id);
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
        return;
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _online = !value); // reverte o switch
      final msg = e.toString().replaceFirst('Exception: ', '');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF161820),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFf59e0b), size: 22),
            SizedBox(width: 8),
            Text('Entrega em andamento',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ]),
          content: Text(msg,
              style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido',
                  style: TextStyle(color: Color(0xFF1A56DB))),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _logout() async {
    final user = _supabase.auth.currentUser;
    if (user != null) await TrackingService.ficarOffline(user.id);
    _statsTimer?.cancel();
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  void _assinarRealtimeRota() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    _channelRota = _supabase
        .channel('home-entregador-rota-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'entregadores',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: user.id,
          ),
          callback: (payload) async {
            final novaNotif = payload.newRecord['notificacao_rota'];
            final antigaNotif = payload.oldRecord['notificacao_rota'];
            if (novaNotif == null || novaNotif.toString() == antigaNotif?.toString()) return;
            try {
              final rota = await _supabase
                  .from('rotas')
                  .select()
                  .eq('id', novaNotif.toString())
                  .maybeSingle();
              if (!mounted || rota == null) return;
              // Tocar som 10x
              HapticFeedback.heavyImpact();
              try {
                await _audioPlayer.stop();
                await _audioPlayer.setAudioSource(ConcatenatingAudioSource(
                  children: List.generate(10, (_) => AudioSource.asset('assets/sounds/letsgo.wav')),
                ));
                await _audioPlayer.play();
              } catch (_) {}
              setState(() => _rotaAtual = rota);
              _rotaAutorecusaTimer?.cancel();
              _rotaAutorecusaTimer = Timer(const Duration(seconds: 60), _recusarRotaTimeout);
            } catch (_) {}
          },
        )
        .subscribe();
  }

  Future<void> _recusarRotaTimeout() async {
    if (_rotaAtual == null) return;
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try { await _supabase.from('entregadores').update({'notificacao_rota': null}).eq('id', user.id); } catch (_) {}
    }
    if (mounted) setState(() => _rotaAtual = null);
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _rotaAutorecusaTimer?.cancel();
    _channelRota?.unsubscribe();
    _audioPlayer.dispose();
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

          // MAPA em card arredondado
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              color: Colors.black,
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
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
                          width: 64, height: 100,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 48, height: 48,
                                child: SvgPicture.string(
                                  su.svgHelmet(
                                    _online ? '#10B981' : '#EF4444',
                                    _online ? '#065f46' : '#991b1b',
                                  ),
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _online ? const Color(0xFF22c55e) : const Color(0xFF475569),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(nome,
                                    textScaler: TextScaler.noScaling,
                                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                      ]),
                  ],
                ),

                // BOTÃO CHAT - canto inferior esquerdo do mapa
                Positioned(
                  bottom: 16, left: 16,
                  child: GestureDetector(
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
                ),

                // BOTÃO GPS - canto inferior direito do mapa
                Positioned(
                  bottom: 16, right: 16,
                  child: GestureDetector(
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
                ),
              ],
            ),
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
                  GestureDetector(
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(.1), shape: BoxShape.circle),
                      child: const Icon(Icons.menu, color: Colors.white, size: 20),
                    ),
                  ),
                  const Spacer(),
                  _buildToggleCompacto(),
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

          // CARD ROTA DISPONÍVEL
          if (_rotaAtual != null)
            Positioned(
              bottom: 160, left: 16, right: 16,
              child: _buildCardRota(),
            ),

        ],
      ),
    );
  }

  Widget _buildCardRota() {
    final rota = _rotaAtual!;
    final count = (rota['pedido_ids'] as List?)?.length ?? 0;
    return GestureDetector(
      onTap: () {
        _rotaAutorecusaTimer?.cancel();
        _audioPlayer.stop();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RotaDisponivelScreen(pedido: rota)),
        ).then((_) {
          if (mounted) setState(() => _rotaAtual = null);
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A56DB), Color(0xFF0E3A99)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFF1A56DB).withOpacity(.45), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          const Icon(Icons.route_outlined, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🛵 Nova Rota!', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text('$count ${count == 1 ? 'entrega' : 'entregas'} agrupadas — toque para ver',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
          const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
        ]),
      ),
    );
  }

  Widget _buildToggleCompacto() {
    final cor = _online ? const Color(0xFF22c55e) : const Color(0xFFef4444);
    return GestureDetector(
      onLongPress: () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const OnlineStatusScreen()));
        _carregarEntregador(); // recarrega estado ao voltar
      },
      child: Container(
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
      ), // Container
    ); // GestureDetector
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
