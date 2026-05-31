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

  @override
  void initState() {
    super.initState();
    th.carregarFaixas().then((_) { if (mounted) setState(() {}); });
    _obterPosicao();
  }

  Future<void> _obterPosicao() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) setState(() => _posicaoAtual = pos);
    } catch (_) {}
  }

  // Coordenadas do pedido (cliente)
  LatLng? get _latLngCliente {
    final lat = widget.pedido['latitude'];
    final lng = widget.pedido['longitude'];
    if (lat == null || lng == null) return null;
    return LatLng((lat as num).toDouble(), (lng as num).toDouble());
  }

  // Ribeirão Preto como centro padrão
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

      // Vai para aba Aceitos
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
    final numero = widget.pedido['numero'] ?? widget.pedido['id'].toString().substring(0, 6);
    final endereco = widget.pedido['endereco'] ?? '—';
    final km = double.tryParse(widget.pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final comRetorno = widget.pedido['com_retorno'] == true;
    final gorjeta = double.tryParse(widget.pedido['gorjeta']?.toString() ?? '0') ?? 0;
    final taxaMotoboy = th.calcularTaxaMotoboy(km, comRetorno, th.faixasGlobais);
    final taxaTotal = taxaMotoboy + gorjeta;
    final clienteLatLng = _latLngCliente;

    // Marcadores no mapa
    final markers = <Marker>[];

    // Marcador do motoboy — svgHelmet azul (copiado de entregador_home_screen)
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

    // Marcador do pedido — círculo azul + número (copiado de entregador_home_screen)
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

    // Marcador da loja — svgPinLoja (já fill="#1A56DB")
    markers.add(Marker(
      point: _centro,
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
            child: const Text('Loja',
                style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
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
          // Mapa
          SizedBox(
            height: 260,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: clienteLatLng ?? _centro,
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

          // Detalhes
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Endereço de entrega
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161820),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2A2D35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Coleta
                        Row(children: [
                          const Icon(Icons.store, color: Color(0xFF8b5cf6), size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('COLETA', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
                              const Text('Estabelecimento', style: TextStyle(color: Colors.white, fontSize: 14)),
                            ],
                          )),
                        ]),
                        const SizedBox(height: 4),
                        // Linha
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Column(children: [
                            SizedBox(height: 2, width: 2),
                            Icon(Icons.more_vert, color: Colors.white24, size: 16),
                          ]),
                        ),
                        // Entrega
                        Row(children: [
                          const Icon(Icons.location_on, color: Color(0xFFec4899), size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ENTREGA', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
                              Text(endereco, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            ],
                          )),
                        ]),
                        const SizedBox(height: 12),
                        const Text('SUA TAXA', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
                        Text('R\$ ${taxaTotal.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFF10b981), fontSize: 20, fontWeight: FontWeight.bold)),
                        if (gorjeta > 0) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            const Text('🎁', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text('+ R\$ ${gorjeta.toStringAsFixed(2)}',
                                style: const TextStyle(color: Color(0xFF1A56DB), fontSize: 14, fontWeight: FontWeight.w600)),
                          ]),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Botões
                  Row(children: [
                    // Recusar
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
                    // Aceitar
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