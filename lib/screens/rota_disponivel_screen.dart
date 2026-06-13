import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/location_service.dart';
import '../utils/taxa_helper.dart' as th;
import '../utils/status_utils.dart' as su;
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
  double _distMotoboyLoja = 0;
  double _precoDinamico = 0.0;

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
    th.carregarFaixas().then((_) { if (mounted) setState(() {}); });
    _obterPosicaoEntregador();
    Future.delayed(const Duration(milliseconds: 300), _ajustarMapa);
    _buscarPrecoDinamico();
  }

  Future<void> _buscarPrecoDinamico() async {
    try {
      final data = await _supabase
          .from('configuracoes')
          .select('valor')
          .eq('chave', 'preco_dinamico_entregador')
          .maybeSingle();
      final valor = double.tryParse(data?['valor']?.toString() ?? '0') ?? 0.0;
      if (mounted) setState(() => _precoDinamico = valor);
    } catch (_) {}
  }

  Future<void> _obterPosicaoEntregador() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null && mounted) {
        setState(() => _posicaoEntregador = LatLng(pos.latitude, pos.longitude));
        _calcularDistLoja(pos.latitude, pos.longitude);
        _ajustarMapa();
      }
    } catch (_) {}
  }

  void _calcularDistLoja(double lat, double lng) {
    if (_lojaLat == null || _lojaLng == null) return;
    const R = 6371.0;
    final dLat = (_lojaLat! - lat) * pi / 180;
    final dLng = (_lojaLng! - lng) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat * pi / 180) * cos(_lojaLat! * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    final dist = R * 2 * atan2(sqrt(a), sqrt(1 - a));
    if (mounted) setState(() => _distMotoboyLoja = dist);
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
    final numero = _pedido['numero']?.toString() ?? _pedido['id']?.toString().substring(0, 4) ?? '—';
    final nomeLoja = (_pedido['lojas']?['nome'] ?? 'Loja').toString();
    final nomeLabel = nomeLoja.length > 12 ? nomeLoja.substring(0, 12) : nomeLoja;

    // Capacete SVG azul
    if (_posicaoEntregador != null) {
      markers.add(Marker(
        point: _posicaoEntregador!,
        width: 64, height: 90,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48, height: 48,
              child: SvgPicture.string(
                su.svgHelmet('#1A56DB', '#0E3A99'),
                fit: BoxFit.contain,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1A56DB),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Você',
                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ));
    }

    // Loja — círculo azul + store icon
    if (_lojaLat != null && _lojaLng != null) {
      markers.add(Marker(
        point: LatLng(_lojaLat!, _lojaLng!),
        width: 64, height: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1A56DB),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 8)],
              ),
              child: const Icon(Icons.store, color: Colors.white, size: 22),
            ),
          ],
        ),
      ));
    }

    // Pedido — card azul com seta igual à home
    if (_clienteLat != null && _clienteLng != null) {
      markers.add(Marker(
        point: LatLng(_clienteLat!, _clienteLng!),
        width: 80, height: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A56DB),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 4)],
              ),
              child: Text('#$numero',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            CustomPaint(
              size: const Size(10, 6),
              painter: _TrianglePainter(const Color(0xFF1A56DB)),
            ),
          ],
        ),
      ));
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final centerLat = _lojaLat ?? _clienteLat ?? -21.1775;
    final centerLng = _lojaLng ?? _clienteLng ?? -47.8103;
    final nomeLoja = (_pedido['lojas']?['nome'] ?? 'Estabelecimento').toString();
    final endCliente = (_pedido['endereco'] ?? '—').toString();
    final endLoja = (_pedido['lojas']?['endereco'] ?? '—').toString();
    final km = double.tryParse(_pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final comRetorno = _pedido['com_retorno'] == true;
    final gorjeta = double.tryParse(_pedido['gorjeta']?.toString() ?? '0') ?? 0;
    final pontos = _pedido['pontos'] ?? 4;
    final taxaMotoboy = th.calcularTaxaMotoboy(km, comRetorno, th.faixasGlobais);
    final precoDinamico = _precoDinamico;
    final taxaTotal = taxaMotoboy + gorjeta + precoDinamico;
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
        // MAPA escuro
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

        // CARD INFERIOR com todas as infos
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          decoration: const BoxDecoration(
            color: Color(0xFF161820),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFF2a2d3a), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),

            // Linha 1: loja + número
            Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.store, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(nomeLoja,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text('#$numero', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
            const SizedBox(height: 10),

            // Endereço de coleta
            Row(children: [
              const Icon(Icons.store, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(endLoja,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),



            // Linha 3: endereço entrega
            Row(children: [
              const Icon(Icons.location_pin, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(endCliente, style: const TextStyle(color: Colors.white, fontSize: 13))),
            ]),
            const SizedBox(height: 8),

            // Linha 4: pontos
            Row(children: [
              const Icon(Icons.star_border, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text('$pontos pontos', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
            const SizedBox(height: 8),

            // Linha 5: bag térmica à esquerda
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white),
                ),
                child: const Text('Bag térmica', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 12),

            // Linha 6: distância percurso + taxa
            Row(children: [
              const Icon(Icons.route_outlined, color: Color(0xFFFFFFFF), size: 16),
              const SizedBox(width: 4),
              Text('${km.toStringAsFixed(2)} km', style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13)),
              const Spacer(),
              if (comRetorno) ...[
                Text('R\$ ${(th.calcularTaxaMotoboy(km, false, th.faixasGlobais) + precoDinamico + gorjeta).toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.red, fontSize: 14,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.red)),
                const SizedBox(width: 8),
              ] else if (precoDinamico > 0) ...[
                Text('R\$ ${taxaMotoboy.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.red, fontSize: 14,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.red)),
                const SizedBox(width: 8),
              ] else if (gorjeta > 0) ...[
                Text('R\$ ${taxaMotoboy.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 14,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.white38)),
                const SizedBox(width: 8),
              ],
              Text(
                precoDinamico > 0
                    ? 'R\$ ${(taxaMotoboy + precoDinamico).toStringAsFixed(2)}'
                    : 'R\$ ${taxaTotal.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ]),

            if (gorjeta > 0) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Text('🎁', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text('Gorjeta incluída: R\$ ${gorjeta.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFF1A56DB), fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ],

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