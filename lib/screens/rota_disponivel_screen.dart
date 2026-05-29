import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'entrega_screen.dart';

class RotaDisponivelScreen extends StatefulWidget {
  final Map<String, dynamic> rota;
  const RotaDisponivelScreen({super.key, required this.rota});

  @override
  State<RotaDisponivelScreen> createState() => _RotaDisponivelScreenState();
}

class _RotaDisponivelScreenState extends State<RotaDisponivelScreen> {
  final _supabase = Supabase.instance.client;
  final _mapController = MapController();

  List<Map<String, dynamic>> _pedidos = [];
  Map<String, dynamic>? _loja;
  bool _carregando = true;
  bool _processando = false;
  Timer? _timerRestante;
  int _segundosRestantes = 60;

  @override
  void initState() {
    super.initState();
    _carregar();
    _timerRestante = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _segundosRestantes--);
      if (_segundosRestantes <= 0) {
        t.cancel();
        _recusar();
      }
    });
  }

  @override
  void dispose() {
    _timerRestante?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final rawIds = widget.rota['pedido_ids'];
      final pedidoIds = rawIds is List ? rawIds.map((e) => e.toString()).toList() : <String>[];

      if (pedidoIds.isNotEmpty) {
        final data = await _supabase
            .from('pedidos')
            .select('*, lojas(nome, latitude, longitude, endereco)')
            .inFilter('id', pedidoIds);
        _pedidos = List<Map<String, dynamic>>.from(data);
      }

      final lojaId = widget.rota['loja_id'];
      if (lojaId != null) {
        _loja = await _supabase.from('lojas').select().eq('id', lojaId.toString()).maybeSingle();
      }

      if (mounted) {
        setState(() => _carregando = false);
        Future.delayed(const Duration(milliseconds: 200), _ajustarMapa);
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _ajustarMapa() {
    final pontos = <LatLng>[];
    if (_loja?['latitude'] != null && _loja?['longitude'] != null) {
      pontos.add(LatLng((_loja!['latitude'] as num).toDouble(), (_loja!['longitude'] as num).toDouble()));
    }
    for (final p in _pedidos) {
      if (p['latitude'] != null && p['longitude'] != null) {
        pontos.add(LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble()));
      }
    }
    if (pontos.isEmpty) return;
    if (pontos.length == 1) {
      try { _mapController.move(pontos.first, 15); } catch (_) {}
      return;
    }
    final lats = pontos.map((p) => p.latitude);
    final lngs = pontos.map((p) => p.longitude);
    final sw = LatLng(lats.reduce(min), lngs.reduce(min));
    final ne = LatLng(lats.reduce(max), lngs.reduce(max));
    try {
      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(sw, ne),
        padding: const EdgeInsets.all(60),
      ));
    } catch (_) {
      final midLat = (sw.latitude + ne.latitude) / 2;
      final midLng = (sw.longitude + ne.longitude) / 2;
      try { _mapController.move(LatLng(midLat, midLng), 13); } catch (_) {}
    }
  }

  double get _taxaTotal {
    double total = 0;
    for (final p in _pedidos) {
      total += double.tryParse(p['taxa_entrega']?.toString() ?? '0') ?? 0;
      total += double.tryParse(p['gorjeta']?.toString() ?? '0') ?? 0;
    }
    return total;
  }

  Future<void> _aceitar() async {
    if (_processando) return;
    setState(() => _processando = true);
    _timerRestante?.cancel();
    final user = _supabase.auth.currentUser;
    if (user == null) { if (mounted) Navigator.pop(context); return; }
    try {
      final agora = DateTime.now().toIso8601String();
      final rotaId = widget.rota['id'].toString();
      final rawIds = widget.rota['pedido_ids'];
      final pedidoIds = rawIds is List ? rawIds.map((e) => e.toString()).toList() : <String>[];

      await _supabase.from('rotas').update({'status': 'aceita', 'updated_at': agora}).eq('id', rotaId);

      for (final id in pedidoIds) {
        await _supabase.from('pedidos').update({
          'status': 'aceito',
          'status_detalhado': 'aceito',
          'motoboy_id': user.id,
          'entregador_id': user.id,
          'aceito_em': agora,
          'updated_at': agora,
        }).eq('id', id);
      }

      await _supabase.from('entregadores').update({'notificacao_rota': null}).eq('id', user.id);

      if (!mounted) return;
      if (_pedidos.isNotEmpty) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EntregaScreen(pedido: _pedidos.first)));
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _recusar() async {
    if (_processando) return;
    setState(() => _processando = true);
    _timerRestante?.cancel();
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try { await _supabase.from('entregadores').update({'notificacao_rota': null}).eq('id', user.id); } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Loja — pino azul
    if (_loja?['latitude'] != null && _loja?['longitude'] != null) {
      markers.add(Marker(
        point: LatLng((_loja!['latitude'] as num).toDouble(), (_loja!['longitude'] as num).toDouble()),
        width: 52, height: 58,
        child: const _PinMarker(icon: Icons.store, color: Color(0xFF1A56DB), label: 'Loja'),
      ));
    }

    // Pedidos — pinos vermelhos
    for (var i = 0; i < _pedidos.length; i++) {
      final p = _pedidos[i];
      if (p['latitude'] == null || p['longitude'] == null) continue;
      final numStr = p['numero']?.toString() ?? '${i + 1}';
      final lat = (p['latitude'] as num).toDouble();
      final lng = (p['longitude'] as num).toDouble();
      markers.add(Marker(
        point: LatLng(lat, lng),
        width: 52, height: 58,
        child: _PinMarker(icon: Icons.location_on, color: const Color(0xFFef4444), label: '#$numStr'),
      ));
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final lojaLat = (_loja?['latitude'] as num?)?.toDouble() ?? -21.1775;
    final lojaLng = (_loja?['longitude'] as num?)?.toDouble() ?? -47.8103;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _recusar,
        ),
        title: const Text('Nova Rota', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _segundosRestantes <= 15 ? const Color(0xFFef4444) : const Color(0xFF1A56DB),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_segundosRestantes}s',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : Column(children: [
              // MAPA
              SizedBox(
                height: 260,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: LatLng(lojaLat, lojaLng), initialZoom: 13),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    MarkerLayer(markers: _buildMarkers()),
                  ],
                ),
              ),

              // PAINEL INFO
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Loja
                    if (_loja != null) _buildLojaRow(),
                    const SizedBox(height: 12),

                    // Pedidos
                    ...List.generate(_pedidos.length, (i) => _buildPedidoRow(i)),

                    // Total
                    Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A56DB).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1A56DB).withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Text('💰 Total da rota', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const Spacer(),
                        Text('R\$ ${_taxaTotal.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      ]),
                    ),
                  ]),
                ),
              ),

              // BOTÕES
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
                child: Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _processando ? null : _recusar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2a2d3a),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('RECUSAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _processando ? null : _aceitar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22c55e),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _processando
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('ACEITAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ]),
              ),
            ]),
    );
  }

  Widget _buildLojaRow() => Row(children: [
    Container(
      width: 38, height: 38,
      decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.store, color: Colors.white, size: 20),
    ),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_loja!['nome']?.toString() ?? 'Loja',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      if (_loja!['endereco'] != null)
        Text(_loja!['endereco'].toString(),
            style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
    ])),
  ]);

  Widget _buildPedidoRow(int i) {
    final p = _pedidos[i];
    final numero = p['numero']?.toString() ?? p['id']?.toString().substring(0, 6) ?? '—';
    final endereco = p['endereco']?.toString() ?? '—';
    final dist = double.tryParse(p['distancia_km']?.toString() ?? '0') ?? 0;
    final taxa = double.tryParse(p['taxa_entrega']?.toString() ?? '0') ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2d3a)),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: const BoxDecoration(color: Color(0xFFef4444), shape: BoxShape.circle),
          child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('#$numero', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          Text(endereco, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${dist.toStringAsFixed(1)} km', style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 11)),
          Text('R\$ ${taxa.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
      ]),
    );
  }
}

class _PinMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _PinMarker({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color, shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 6)],
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    ),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
    ),
  ]);
}
