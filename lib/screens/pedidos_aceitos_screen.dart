import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/pedido_card_widget.dart';
import '../utils/status_utils.dart' as su;
import '../utils/taxa_helper.dart' as th;
import 'entrega_screen.dart';

class PedidosAceitosScreen extends StatefulWidget {
  const PedidosAceitosScreen({super.key});
  @override
  State<PedidosAceitosScreen> createState() => _State();
}

class _State extends State<PedidosAceitosScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pedidos = [];
  bool _carregando = true;
  Timer? _timer;
  Position? _posicaoAtual;
  double _precoDinamico = 0.0;

  @override
  void initState() {
    super.initState();
    th.carregarFaixas().then((_) { if (mounted) setState(() {}); });
    _buscar();
    _obterPosicao();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
  }

  Future<void> _obterPosicao() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) setState(() => _posicaoAtual = last);
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _posicaoAtual = pos);
    } catch (_) {}
  }

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
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _buscar() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait([
        _supabase
            .from('pedidos')
            .select('*, lojas(nome, endereco, latitude, longitude)')
            .or('motoboy_id.eq.${user.id},entregador_id.eq.${user.id}')
            .inFilter('status', ['aceito', 'no_local', 'chegou_local', 'em_rota', 'chegou_destino', 'retornando'])
            .order('aceito_em', ascending: false),
        _supabase
            .from('configuracoes')
            .select('valor')
            .eq('chave', 'preco_dinamico_entregador')
            .maybeSingle(),
      ]);
      final precoDinamico = double.tryParse(
              (results[1] as Map<String, dynamic>?)?['valor']?.toString() ?? '0') ??
          0.0;
      if (mounted) setState(() {
        _pedidos = List<Map<String, dynamic>>.from(results[0] as List);
        _precoDinamico = precoDinamico;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirEntrega(Map<String, dynamic> pedido) async {
    _timer?.cancel();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EntregaScreen(pedido: pedido)));
    await _buscar();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
  }

  // Borda sempre azul independente do status
  Color _cor(String s) => su.statusColor(s);

  String _label(String s) {
    switch (s) {
      case 'aceito':       return 'Aceito';
      case 'no_local':
      case 'chegou_local': return 'No local';
      case 'em_rota':         return 'Em rota';
      case 'chegou_destino':  return 'Chegou no destino';
      case 'retornando':      return 'Retornando';
      default:             return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        automaticallyImplyLeading: false,
        title: Row(children: [
          const Text('Minhas entregas',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          if (_pedidos.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(20)),
              child: Text('${_pedidos.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _buscar)],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : _pedidos.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline, color: Colors.grey.shade700, size: 72),
                  const SizedBox(height: 16),
                  const Text('Nenhuma entrega em andamento', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('Aceite um pedido na aba Disponíveis',
                      style: TextStyle(color: Color(0xFF555), fontSize: 13)),
                ]))
              : RefreshIndicator(
                  onRefresh: _buscar,
                  color: const Color(0xFF1A56DB),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pedidos.length,
                    itemBuilder: (_, i) {
                      final p = _pedidos[i];
                      final status = p['status_detalhado'] ?? p['status'] ?? 'aceito';
                      final isRetornando = status == 'retornando';
                      final isChegouDestino = status == 'chegou_destino';
                      double? distMotoboyLoja;
                      if (_posicaoAtual != null) {
                        final loja = p['lojas'];
                        final lat = (loja?['lat'] ?? loja?['latitude']) as num?;
                        final lng = (loja?['lng'] ?? loja?['longitude']) as num?;
                        if (lat != null && lng != null) {
                          distMotoboyLoja = _calcularDistancia(
                            _posicaoAtual!.latitude, _posicaoAtual!.longitude,
                            lat.toDouble(), lng.toDouble(),
                          );
                        }
                      }
                      return PedidoCardWidget(
                        pedido: p,
                        statusLabel: _label(status),
                        statusCor: _cor(status),
                        botaoCor: _cor(status),
                        isRetornando: isRetornando,
                        isChegouDestino: isChegouDestino,
                        distMotoboyLojaKm: distMotoboyLoja,
                        precoDinamico: _precoDinamico,
                        onTap: () => _abrirEntrega(p),
                      );
                    },
                  ),
                ),
    );
  }
}
