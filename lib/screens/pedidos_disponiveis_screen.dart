import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'home_screen.dart';
import 'pedidos_aceitos_screen.dart';
import 'vagas_screen.dart';
import 'mapa_pedido_screen.dart';

class PedidosDisponiveisScreen extends StatefulWidget {
  const PedidosDisponiveisScreen({super.key});
  @override
  State<PedidosDisponiveisScreen> createState() => _PedidosDisponiveisScreenState();
}

class _PedidosDisponiveisScreenState extends State<PedidosDisponiveisScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pedidos = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  // Localização atual do entregador (atualize com geolocator se quiser precisão)
  double? _motoLatitude;
  double? _motoLongitude;

  @override
  void initState() {
    super.initState();
    _carregarLocalizacaoEntregador();
    _carregarPedidos();
    _assinarRealtime();
  }

  /// Busca a localização do entregador no banco (tabela entregadores)
  Future<void> _carregarLocalizacaoEntregador() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await _supabase
          .from('entregadores')
          .select('latitude, longitude')
          .eq('id', user.id)
          .maybeSingle();
      if (res != null) {
        setState(() {
          _motoLatitude = (res['latitude'] as num?)?.toDouble();
          _motoLongitude = (res['longitude'] as num?)?.toDouble();
        });
      }
    } catch (_) {}
  }

  /// Calcula distância em km entre dois pontos (fórmula Haversine)
  double? _calcularDistancia(Map<String, dynamic> pedido) {
    final lat2 = (pedido['latitude'] as num?)?.toDouble();
    final lon2 = (pedido['longitude'] as num?)?.toDouble();
    if (_motoLatitude == null || _motoLongitude == null || lat2 == null || lon2 == null) {
      return null;
    }
    const R = 6371.0; // Raio da Terra em km
    final dLat = _toRad(lat2 - _motoLatitude!);
    final dLon = _toRad(lon2 - _motoLongitude!);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(_motoLatitude!)) * cos(_toRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  Future<void> _carregarPedidos() async {
    setState(() => _loading = true);
    try {
      final response = await _supabase
          .from('pedidos')
          .select()
          .inFilter('status', ['pronto'])
          .order('created_at', ascending: false);
      setState(() {
        _pedidos = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _assinarRealtime() {
    _channel = _supabase.channel('pedidos-disp').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'pedidos',
      callback: (payload) => _carregarPedidos(),
    ).subscribe();
  }

  Future<void> _aceitarPedido(Map<String, dynamic> pedido) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _supabase.from('pedidos').update({
        'status': 'em_rota',
        'entregador_id': user.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', pedido['id']);
      await _supabase.from('entregadores').update({
        'disponivel': false,
        'status': 'ocupado',
      }).eq('id', user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pedido aceito! Boa entrega!'),
            backgroundColor: Color(0xFF1A56DB),
          ),
        );
        _carregarPedidos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Widget _buildBottomBar() {
    return Container(
      height: 64,
      color: const Color(0xFF161820),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white54),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (r) => false,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF1A56DB)),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.white54),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PedidosAceitosScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.work_outline, color: Colors.white54),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VagasScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPedidoCard(Map<String, dynamic> p) {
    final distancia = _calcularDistancia(p);
    final distanciaTexto = distancia != null
        ? '${distancia.toStringAsFixed(1)} km'
        : '-- km';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho: número do pedido + status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pedido #${p["numero"] ?? p["id"].toString().substring(0, 8)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2130),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2A2D35)),
                  ),
                  child: Text(
                    p['status'] ?? '',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ),
              ],
            ),

            const Divider(color: Color(0xFF2A2D35), height: 20),

            // Descrição
            if (p['descricao'] != null) ...[
              Row(children: [
                const Icon(Icons.receipt_long, color: Colors.white54, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p['descricao'],
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],

            // Endereço
            if (p['endereco'] != null) ...[
              Row(children: [
                const Icon(Icons.location_on, color: Color(0xFF1A56DB), size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p['endereco'],
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],

            // Valor + Distância + Botão de entrega
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Lado esquerdo: valor e distância
                Row(
                  children: [
                    const Icon(Icons.attach_money, color: Colors.greenAccent, size: 16),
                    Text(
                      'R\$ ${(p["valor"] ?? 0).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.straighten, color: Colors.white54, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      distanciaTexto,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                // Balão/ícone de entrega — clique para ir ao mapa e aceitar
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapaPedidoScreen(pedido: p),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A56DB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delivery_dining,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(children: [
          const Text(
            'Pedidos Disponíveis',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          if (_pedidos.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1A56DB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_pedidos.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _carregarPedidos,
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : _pedidos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inbox_outlined, color: Colors.white24, size: 72),
                      const SizedBox(height: 16),
                      const Text(
                        'Nenhum pedido disponível',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _carregarPedidos,
                        child: const Text('Atualizar', style: TextStyle(color: Color(0xFF1A56DB))),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF1A56DB),
                  onRefresh: _carregarPedidos,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pedidos.length,
                    itemBuilder: (context, index) => _buildPedidoCard(_pedidos[index]),
                  ),
                ),
    );
  }
}