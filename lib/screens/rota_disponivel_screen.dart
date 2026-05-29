import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/location_service.dart';
import 'entrega_screen.dart';
import 'pedidos_disponiveis_screen.dart';

class RotaDisponivelScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;
  const RotaDisponivelScreen({super.key, required this.pedido});

  @override
  State<RotaDisponivelScreen> createState() => _RotaDisponivelScreenState();
}

class _RotaDisponivelScreenState extends State<RotaDisponivelScreen> {
  final _supabase = Supabase.instance.client;
  final _mapController = MapController();
  bool _processando = false;
  LatLng? _posicaoEntregador;

  Map<String, dynamic> get _pedido => widget.pedido;

  double? get _lojaLat {
    final l = _pedido['lojas'];
    return (l?['latitude'] as num?)?.toDouble();
  }

  double? get _lojaLng {
    final l = _pedido['lojas'];
    return (l?['longitude'] as num?)?.toDouble();
  }

  double? get _clienteLat => (_pedido['latitude'] as num?)?.toDouble();
  double? get _clienteLng => (_pedido['longitude'] as num?)?.toDouble();

  @override
  void initState() {
    super.initState();
    _obterPosicaoEntregador();
    Future.delayed(const Duration(milliseconds: 300), _ajustarMapa);
  }

  Future<void> _obterPosicaoEntregador() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null && mounted) {
        setState(() => _posicaoEntregador = LatLng(pos.latitude, pos.longitude));
        _ajustarMapa();
      }
    } catch (_) {}
  }

  void _ajustarMapa() {
    final pontos = <LatLng>[];
    if (_posicaoEntregador != null) pontos.add(_posicaoEntregador!);
    if (_lojaLat != null && _lojaLng != null) pontos.add(LatLng(_lojaLat!, _lojaLng!));
    if (_clienteLat != null && _clienteLng != null) pontos.add(LatLng(_clienteLat!, _clienteLng!));
    if (pontos.length < 2) {
      if (pontos.isNotEmpty) {
        try { _mapController.move(pontos.first, 15); } catch (_) {}
      }
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
      try { _mapController.move(LatLng((sw.latitude + ne.latitude) / 2, (sw.longitude + ne.longitude) / 2), 13); } catch (_) {}
    }
  }

  Future<void> _aceitar() async {
    if (_processando) return;
    setState(() => _processando = true);
    final user = _supabase.auth.currentUser;
    if (user == null) { Navigator.pop(context); return; }
    try {
      final agora = DateTime.now().toIso8601String();
      final result = await _supabase.from('pedidos').update({
        'status': 'aceito',
        'status_detalhado': 'aceito',
        'motoboy_id': user.id,
        'entregador_id': user.id,
        'aceito_em': agora,
        'updated_at': agora,
      }).eq('status', 'pronto').eq('id', _pedido['id']).select();

      if (!mounted) return;
      if (result.isEmpty) {
        setState(() => _processando = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pedido já foi aceito por outro entregador'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EntregaScreen(pedido: _pedido)));
    } catch (e) {
      if (mounted) {
        setState(() => _processando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _rejeitar() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PedidosDisponiveisScreen()));
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Entregador — capacete azul (mesmo padrão do painel adm)
    if (_posicaoEntregador != null) {
      markers.add(Marker(
        point: _posicaoEntregador!,
        width: 64, height: 72,
        child: _HelmetMarker(),
      ));
    }

    // Loja — pino GPS azul (mesmo padrão do painel adm)
    if (_lojaLat != null && _lojaLng != null) {
      markers.add(Marker(
        point: LatLng(_lojaLat!, _lojaLng!),
        width: 44, height: 54,
        child: _GpsPinMarker(color: const Color(0xFF1A56DB), icon: Icons.store),
      ));
    }

    // Cliente — etiqueta vermelha com número (mesmo padrão do painel adm)
    if (_clienteLat != null && _clienteLng != null) {
      final numero = _pedido['numero_loja']?.toString() ?? _pedido['numero']?.toString() ?? _pedido['id']?.toString().substring(0, 4) ?? '—';
      markers.add(Marker(
        point: LatLng(_clienteLat!, _clienteLng!),
        width: 64, height: 36,
        child: _LabelMarker(numero: numero, color: const Color(0xFFEF4444)),
      ));
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final centerLat = _lojaLat ?? _clienteLat ?? -21.1775;
    final centerLng = _lojaLng ?? _clienteLng ?? -47.8103;
    final nomeLoja = (_pedido['lojas']?['nome'] ?? 'Estabelecimento').toString();
    final endLoja = (_pedido['lojas']?['endereco'] ?? '—').toString();
    final endCliente = (_pedido['endereco'] ?? '—').toString();
    final taxa = double.tryParse(_pedido['taxa_entrega']?.toString() ?? '0') ?? 0;
    final gorjeta = double.tryParse(_pedido['gorjeta']?.toString() ?? '0') ?? 0;
    final taxaTotal = taxa + gorjeta;
    final numero = _pedido['numero']?.toString() ?? '—';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _rejeitar,
        ),
        title: Text('Pedido #$numero', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: Column(children: [
        // MAPA
        Expanded(
          flex: 3,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: LatLng(centerLat, centerLng), initialZoom: 14),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
        ),

        // CARD INFERIOR
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          decoration: const BoxDecoration(
            color: Color(0xFF161820),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFF2a2d3a), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),

            // Loja
            _InfoRow(icon: Icons.store, color: const Color(0xFF1A56DB), title: nomeLoja, subtitle: endLoja),
            const SizedBox(height: 10),

            // Cliente
            _InfoRow(icon: Icons.location_on, color: const Color(0xFFEF4444), title: 'Endereço de entrega', subtitle: endCliente),
            const SizedBox(height: 14),

            // Taxa
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF22c55e).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF22c55e).withOpacity(0.3)),
              ),
              child: Row(children: [
                const Text('💰 Taxa de entrega', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const Spacer(),
                Text('R\$ ${taxaTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
            ),
            const SizedBox(height: 16),

            // Botões
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _processando ? null : _rejeitar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFef4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('REJEITAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _processando ? null : _aceitar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A56DB),
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
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ]),
        ),
      ]),
    );
  }
}

// Capacete SVG simplificado — mesmo estilo do painel adm
class _HelmetMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1A56DB),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.45), blurRadius: 8)],
        ),
        child: const Center(child: Text('🛵', style: TextStyle(fontSize: 22))),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: Colors.black.withOpacity(.6), borderRadius: BorderRadius.circular(4)),
        child: const Text('Você', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
      ),
    ],
  );
}

// Pino GPS — mesmo estilo azul do painel adm
class _GpsPinMarker extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _GpsPinMarker({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 6)],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
      CustomPaint(size: const Size(10, 8), painter: _TrianglePainter(color)),
    ],
  );
}

// Etiqueta vermelha com número — mesmo estilo dos pedidos no painel adm
class _LabelMarker extends StatelessWidget {
  final String numero;
  final Color color;
  const _LabelMarker({required this.numero, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.5), blurRadius: 6)],
        ),
        child: Text('#$numero', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      ),
      CustomPaint(size: const Size(10, 7), painter: _TrianglePainter(color)),
    ],
  );
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = ui.Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _InfoRow({required this.icon, required this.color, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 18),
    ),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(height: 2),
      Text(subtitle, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
    ])),
  ]);
}
