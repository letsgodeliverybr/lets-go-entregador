import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _carregarPedidos();
    _assinarRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _carregarPedidos() async {
    setState(() => _loading = true);
    final data = await _supabase
        .from('pedidos')
        .select()
        .eq('status', 'aguardando')
        .order('created_at', ascending: false);
    setState(() {
      _pedidos = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  void _assinarRealtime() {
    _channel = _supabase
        .channel('pedidos-disponiveis')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          callback: (payload) => _carregarPedidos(),
        )
        .subscribe();
  }

  Future<void> _aceitarPedido(Map<String, dynamic> pedido) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
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
        SnackBar(
          content: Text('✅ Pedido ${pedido['numero']} aceito!'),
          backgroundColor: const Color(0xFFF5A623),
        ),
      );
      _carregarPedidos();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Pedidos Disponíveis', style: TextStyle(color: Color(0xFFF5A623), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFFF5A623)),
            onPressed: _carregarPedidos,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5A623)))
          : _pedidos.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Nenhum pedido disponível', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      Text('Aguarde novos pedidos...', style: TextStyle(color: Colors.grey54, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregarPedidos,
                  color: const Color(0xFFF5A623),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _pedidos.length,
                    itemBuilder: (context, index) {
                      final p = _pedidos[index];
                      return Card(
                        color: const Color(0xFF222222),
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(p['numero'] ?? '', style: const TextStyle(color: Color(0xFFF5A623), fontWeight: FontWeight.bold, fontSize: 16)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: const Color(0xFF3D2800), borderRadius: BorderRadius.circular(20)),
                                    child: const Text('Disponível', style: TextStyle(color: Color(0xFFF5A623), fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(children: [
                                const Icon(Icons.location_on, color: Colors.grey, size: 14),
                                const SizedBox(width: 4),
                                Expanded(child: Text(p['endereco'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.shopping_bag, color: Colors.grey, size: 14),
                                const SizedBox(width: 4),
                                Text(p['item'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.attach_money, color: Color(0xFFF5A623), size: 14),
                                Text('R\$ ${(p['valor'] ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFF5A623), fontWeight: FontWeight.bold, fontSize: 13)),
                              ]),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF5A623),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  onPressed: () => _aceitarPedido(p),
                                  child: const Text('ACEITAR PEDIDO', fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
