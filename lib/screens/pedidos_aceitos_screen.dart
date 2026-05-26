import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';

class PedidosAceitosScreen extends StatefulWidget {
  const PedidosAceitosScreen({super.key});
  @override
  State<PedidosAceitosScreen> createState() => _PedidosAceitosScreenState();
}

class _PedidosAceitosScreenState extends State<PedidosAceitosScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pedidos = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() { super.initState(); _carregarPedidos(); _assinarRealtime(); }

  Future<void> _carregarPedidos() async {
    setState(() => _loading = true);
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final response = await _supabase.from('pedidos').select().eq('entregador_id', user.id).eq('status', 'em_rota').order('updated_at', ascending: false);
      setState(() { _pedidos = List<Map<String, dynamic>>.from(response); _loading = false; });
    } catch (e) { setState(() => _loading = false); }
  }

  void _assinarRealtime() {
    _channel = _supabase.channel('pedidos-aceitos').onPostgresChanges(
      event: PostgresChangeEvent.all, schema: 'public', table: 'pedidos',
      callback: (payload) => _carregarPedidos(),
    ).subscribe();
  }

  @override
  void dispose() { _channel?.unsubscribe(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        automaticallyImplyLeading: false,
        title: const Text('Pedidos Aceitos', style: TextStyle(color: Colors.white)),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 2),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : _pedidos.isEmpty
              ? const Center(child: Text('Nenhum pedido aceito', style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _pedidos.length,
                  itemBuilder: (context, index) {
                    final p = _pedidos[index];
                    return Card(
                      color: const Color(0xFF161820),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF2A2D35)),
                      ),
                      child: Padding(padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Pedido #${p["numero"] ?? p["id"]}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Row(children: [const Icon(Icons.location_on, color: Colors.white70, size: 14), const SizedBox(width: 4),
                            Expanded(child: Text(p['endereco'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 13)))]),
                          const SizedBox(height: 4),
                          Row(children: [const Icon(Icons.attach_money, color: Colors.greenAccent, size: 14),
                            Text('R\$ ${(p["valor"] ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))]),
                          const SizedBox(height: 4),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                            child: const Text('Em rota', style: TextStyle(color: Colors.orange, fontSize: 12))),
                        ]),
                      ),
                    );
                  }),
    );
  }
}
