import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/taxa_helper.dart' as th;
import '../utils/status_utils.dart' as su;
import 'pedidos_aceitos_screen.dart';

class AceitarPedidoScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;
  const AceitarPedidoScreen({super.key, required this.pedido});
  @override
  State<AceitarPedidoScreen> createState() => _State();
}

class _State extends State<AceitarPedidoScreen> {
  final _supabase = Supabase.instance.client;
  bool _aceitando = false;
  Position? _posicaoAtual;
  double _distMotoboyLoja = 0;

  @override
  void initState() {
    super.initState();
    th.carregarFaixas().then((_) { if (mounted) setState(() {}); });
    _obterPosicao();
  }

  Future<void> _obterPosicao() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() => _posicaoAtual = pos);
        _calcularDistLoja(pos);
      }
      final current = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) {
        setState(() => _posicaoAtual = current);
        _calcularDistLoja(current);
      }
    } catch (_) {}
  }

  void _calcularDistLoja(Position pos) {
    final loja = widget.pedido['lojas'];
    final lat = (loja?['latitude'] ?? loja?['lat']) as num?;
    final lng = (loja?['longitude'] ?? loja?['lng']) as num?;
    if (lat == null || lng == null) return;
    const R = 6371.0;
    final dLat = (lat.toDouble() - pos.latitude) * pi / 180;
    final dLng = (lng.toDouble() - pos.longitude) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(pos.latitude * pi / 180) * cos(lat.toDouble() * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    final dist = R * 2 * atan2(sqrt(a), sqrt(1 - a));
    if (mounted) setState(() => _distMotoboyLoja = dist);
  }

  LatLng? get _latLngCliente {
    final lat = widget.pedido['latitude'];
    final lng = widget.pedido['longitude'];
    if (lat == null || lng == null) return null;
    return LatLng((lat as num).toDouble(), (lng as num).toDouble());
  }

  LatLng? get _latLngLoja {
    final loja = widget.pedido['lojas'];
    final lat = (loja?['latitude'] ?? loja?['lat']) as num?;
    final lng = (loja?['longitude'] ?? loja?['lng']) as num?;
    if (lat == null || lng == null) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  LatLng? get _latLngColeta {
    final lat = widget.pedido['latitude_coleta'];
    final lng = widget.pedido['longitude_coleta'];
    if (lat == null || lng == null) return null;
    return LatLng((lat as num).toDouble(), (lng as num).toDouble());
  }

  static const _centro = LatLng(-21.1775, -47.8103);

  Future<void> _aceitar() async {
    setState(() => _aceitando = true);
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final result = await _supabase
          .from('pedidos')
          .update({
            'status': 'aceito',
            'status_detalhado': 'aceito',
            'aceito_em': DateTime.now().toIso8601String(),
            'motoboy_id': user.id,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .or('status.eq.pronto,status_detalhado.eq.pronto')
          .eq('id', widget.pedido['id'])
          .select();

      if (!mounted) return;
      if (result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pedido já foi aceito por outro entregador'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
        return;
      }
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const PedidosAceitosScreen(),
          transitionDuration: Duration.zero,
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
        setState(() => _aceitando = false);
      }
    }
  }

  void _recusar() => Navigator.pop(context);


  @override
  Widget build(BuildContext context) {
    print('[ACEITAR_COLETA] lat=${widget.pedido['latitude_coleta']} lng=${widget.pedido['longitude_coleta']}');
    final numero = widget.pedido['numero'] ?? widget.pedido['id'].toString().substring(0, 6);
    final endereco = widget.pedido['endereco'] ?? '—';
    final km = double.tryParse(widget.pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final comRetorno = widget.pedido['com_retorno'] == true;
    final gorjeta = double.tryParse(widget.pedido['gorjeta']?.toString() ?? '0') ?? 0;
    final pontos = widget.pedido['pontos'] ?? 4;
    final taxaBase = th.calcularTaxaMotoboy(km, comRetorno, th.faixasGlobais);
    final taxaMotoboySalvo = (widget.pedido['taxa_motoboy'] as num?)?.toDouble() ?? taxaBase;
    final taxaMotoboy = taxaBase;
    final rawPd = taxaMotoboySalvo - taxaBase;
    final precoDinamico = rawPd >= 0.05 ? rawPd : 0.0;
    debugPrint('[Aceitar] #${widget.pedido['numero']} taxa_motoboy_salvo=${taxaMotoboySalvo.toStringAsFixed(2)} taxa_base=${taxaBase.toStringAsFixed(2)} pd_detectado=${precoDinamico.toStringAsFixed(2)}');
    final taxaTotal = taxaMotoboy + gorjeta + precoDinamico;
    final loja = widget.pedido['lojas'];
    final nomeLoja = loja?['nome']?.toString() ?? 'Estabelecimento';
    final endColeta = widget.pedido['endereco_coleta']?.toString() ?? '';
    final clienteLatLng = _latLngCliente;
    final lojaLatLng = _latLngLoja ?? _centro;
    final coletaLatLng = _latLngColeta;
    debugPrint('[ACEITAR] lat_coleta=${widget.pedido['latitude_coleta']} lng_coleta=${widget.pedido['longitude_coleta']} endereco_coleta=${widget.pedido['endereco_coleta']} preco_dinamico=${widget.pedido['preco_dinamico']}');

    final markers = <Marker>[];

    // Marcador do motoboy — capacete azul
    if (_posicaoAtual != null) {
      markers.add(Marker(
        point: LatLng(_posicaoAtual!.latitude, _posicaoAtual!.longitude),
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

    // Marcador do pedido — círculo azul + número
    if (clienteLatLng != null) {
      markers.add(Marker(
        point: clienteLatLng,
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
      ));
    }

    // Marcador preto — ponto de coleta
    if (coletaLatLng != null) {
      markers.add(Marker(
        point: coletaLatLng,
        width: 56, height: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.45), blurRadius: 6)],
              ),
              child: Text('#$numero',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            const CustomPaint(size: Size(12, 8), painter: _TrianglePainter(Colors.black)),
          ],
        ),
      ));
    }

    // Marcador da loja — pin da loja
    markers.add(Marker(
      point: lojaLatLng,
      width: 56, height: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44, height: 44,
            child: SvgPicture.string(su.svgPinLoja, fit: BoxFit.contain),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1A56DB),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(nomeLoja.length > 8 ? nomeLoja.substring(0, 8) : nomeLoja,
                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        title: Text('Pedido #$numero',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Mapa escuro
          SizedBox(
            height: 240,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: clienteLatLng ?? lojaLatLng,
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),

          // Card com todas as infos
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Card principal igual ao card de disponíveis
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161820),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2A2D35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

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
                          Text('#$numero',
                              style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        ]),
                        const SizedBox(height: 10),

                        // Linha 2: km de onde você está
                        Row(children: [
                          const Icon(Icons.location_on, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            _distMotoboyLoja > 0
                                ? '${_distMotoboyLoja.toStringAsFixed(2)} km de onde você está'
                                : '— km de onde você está',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ]),
                        const SizedBox(height: 8),

                        // Linha 3: coleta (se houver) e entrega
                        if (endColeta.isNotEmpty) ...[
                          Row(children: [
                            const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(endColeta,
                                  style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ),
                          ]),
                          const SizedBox(height: 6),
                        ],
                        Row(children: [
                          const Icon(Icons.location_pin, color: Color(0xFFec4899), size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(endereco,
                                style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ),
                        ]),
                        const SizedBox(height: 8),

                        // Linha 4: pontos
                        Row(children: [
                          const Icon(Icons.star_border, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text('$pontos pontos',
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ]),
                        const SizedBox(height: 8),

                        // Linha 5: tag Bag térmica
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white),
                          ),
                          child: const Text('Bag térmica',
                              style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),

                        // Linha 6: distância percurso + taxa
                        Row(children: [
                          const Icon(Icons.route_outlined, color: Color(0xFFFFFFFF), size: 16),
                          const SizedBox(width: 4),
                          Text('${km.toStringAsFixed(2)} km',
                              style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13)),
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
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                        ]),

                        // Gorjeta
                        if (gorjeta > 0) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            const Text('🎁', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text('Gorjeta incluída: R\$ ${gorjeta.toStringAsFixed(2)}',
                                style: const TextStyle(color: Color(0xFF1A56DB), fontSize: 13, fontWeight: FontWeight.w600)),
                          ]),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Botões
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Color(0xFF2A2D35)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _aceitando ? null : _recusar,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.close, size: 18),
                            SizedBox(width: 6),
                            Text('Recusar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFec4899),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: _aceitando ? null : _aceitar,
                        child: _aceitando
                            ? const SizedBox(height: 20, width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle, size: 18),
                                  SizedBox(width: 6),
                                  Text('Aceitar pedido', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                ],
                              ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
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
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}