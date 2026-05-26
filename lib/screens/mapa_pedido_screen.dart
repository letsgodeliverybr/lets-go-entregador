import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pedidos_aceitos_screen.dart';
import 'pedidos_disponiveis_screen.dart';

class MapaPedidoScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;
  const MapaPedidoScreen({super.key, required this.pedido});

  @override
  State<MapaPedidoScreen> createState() => _MapaPedidoScreenState();
}

class _MapaPedidoScreenState extends State<MapaPedidoScreen> {
  final _supabase = Supabase.instance.client;
  bool _aceitando = false;
  LatLng? _motoLatLng;

  // Coordenadas da loja (origem da coleta)
  LatLng get _lojaLatLng => LatLng(
        (widget.pedido['loja_lat'] as num? ?? -21.1775).toDouble(),
        (widget.pedido['loja_lng'] as num? ?? -47.8103).toDouble(),
      );

  // Coordenadas do cliente (destino da entrega)
  LatLng get _clienteLatLng => LatLng(
        (widget.pedido['cliente_lat'] as num? ?? -21.1900).toDouble(),
        (widget.pedido['cliente_lng'] as num? ?? -47.8200).toDouble(),
      );

  @override
  void initState() {
    super.initState();
    _carregarPosicaoMotoboy();
  }

  Future<void> _carregarPosicaoMotoboy() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await _supabase
          .from('entregadores')
          .select('lat, lng')
          .eq('id', user.id)
          .maybeSingle();
      if (res != null && res['lat'] != null && res['lng'] != null) {
        setState(() {
          _motoLatLng = LatLng(
            (res['lat'] as num).toDouble(),
            (res['lng'] as num).toDouble(),
          );
        });
      }
    } catch (_) {}
  }

  /// Distância em km entre dois LatLng (Haversine)
  double _distanciaKm(LatLng a, LatLng b) {
    const R = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLon = _toRad(b.longitude - a.longitude);
    final x = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(a.latitude)) *
            cos(_toRad(b.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(x), sqrt(1 - x));
  }

  double _toRad(double deg) => deg * pi / 180;

  Future<void> _aceitarPedido() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    setState(() => _aceitando = true);
    try {
      await _supabase.from('pedidos').update({
        'status': 'em_rota',
        'entregador_id': user.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.pedido['id']);
      await _supabase.from('entregadores').update({
        'disponivel': false,
        'status': 'ocupado',
      }).eq('id', user.id);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PedidosAceitosScreen()),
          (r) => false,
        );
      }
    } catch (e) {
      setState(() => _aceitando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aceitar pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _rejeitarPedido() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PedidosDisponiveisScreen()),
      (r) => false,
    );
  }

  // Centro do mapa: ponto médio entre loja e cliente
  LatLng get _centro => LatLng(
        (_lojaLatLng.latitude + _clienteLatLng.latitude) / 2,
        (_lojaLatLng.longitude + _clienteLatLng.longitude) / 2,
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final loja = (p['loja_nome'] ?? p['estabelecimento'] ?? 'Loja').toString();
    final endereco = (p['endereco'] ?? 'Endereço não informado').toString();
    final descricao = (p['descricao'] as String?) ?? '';
    final valor = (p['valor'] as num? ?? 0).toStringAsFixed(2);
    final numero = p['numero'] != null
        ? '#${p["numero"]}'
        : '#${p["id"].toString().substring(0, 8).toUpperCase()}';

    final distLoja = _motoLatLng != null
        ? '${_distanciaKm(_motoLatLng!, _lojaLatLng).toStringAsFixed(1)} km até a loja'
        : null;
    final distEntrega =
        '${_distanciaKm(_lojaLatLng, _clienteLatLng).toStringAsFixed(1)} km de entrega';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loja.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Pedido $numero',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── MAPA ──────────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _centro,
                initialZoom: 13.5,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.letsgodelivery.entregador',
                ),

                // Polilinha loja → cliente
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_lojaLatLng, _clienteLatLng],
                      strokeWidth: 3.5,
                      color: const Color(0xFF1A56DB).withOpacity(0.8),
                    ),
                  ],
                ),

                // Polilinha motoboy → loja (linha fina laranja)
                if (_motoLatLng != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [_motoLatLng!, _lojaLatLng],
                        strokeWidth: 2.5,
                        color: Colors.orange.withOpacity(0.65),
                      ),
                    ],
                  ),

                MarkerLayer(
                  markers: [
                    // Marcador da loja (azul)
                    Marker(
                      point: _lojaLatLng,
                      width: 48,
                      height: 48,
                      child: Tooltip(
                        message: loja,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A56DB),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 6,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: const Icon(Icons.store,
                              color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                    // Marcador do cliente (vermelho)
                    Marker(
                      point: _clienteLatLng,
                      width: 48,
                      height: 48,
                      child: Tooltip(
                        message: endereco,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 6,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: const Icon(Icons.person_pin_circle,
                              color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                    // Marcador do motoboy (laranja)
                    if (_motoLatLng != null)
                      Marker(
                        point: _motoLatLng!,
                        width: 44,
                        height: 44,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 6,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: const Icon(Icons.delivery_dining,
                              color: Colors.white, size: 20),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── LEGENDA rápida ─────────────────────────────────────
          Container(
            color: const Color(0xFF0D0F14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendaDot(const Color(0xFF1A56DB), 'Loja'),
                const SizedBox(width: 16),
                _legendaDot(Colors.redAccent, 'Cliente'),
                if (_motoLatLng != null) ...[
                  const SizedBox(width: 16),
                  _legendaDot(Colors.orange, 'Você'),
                ],
              ],
            ),
          ),

          // ── PAINEL INFERIOR ────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF161820),
              border: Border(top: BorderSide(color: Color(0xFF2A2D35))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Loja
                _infoRow(Icons.store, const Color(0xFF1A56DB), loja),
                const SizedBox(height: 6),
                // Endereço cliente
                _infoRow(Icons.location_on, Colors.redAccent, endereco),
                if (descricao.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _infoRow(Icons.receipt_long, Colors.white38, descricao),
                ],
                const SizedBox(height: 8),
                // Distâncias + Valor
                Row(
                  children: [
                    // Dist motoboy→loja
                    if (distLoja != null)
                      _chip(Icons.near_me, Colors.orange, distLoja),
                    if (distLoja != null) const SizedBox(width: 8),
                    // Dist loja→cliente
                    _chip(Icons.straighten, Colors.white54, distEntrega),
                    const Spacer(flex: 1),
                    // Valor
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.greenAccent.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.attach_money,
                              color: Colors.greenAccent, size: 16),
                          Text(
                            'R\$ $valor',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Botões Rejeitar / Aceitar
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _aceitando ? null : _rejeitarPedido,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Rejeitar',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.red.shade900,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _aceitando ? null : _aceitarPedido,
                        icon: _aceitando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: Text(
                          _aceitando ? 'Aceitando...' : 'Aceitar',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A56DB),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              const Color(0xFF1A56DB).withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _legendaDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}
