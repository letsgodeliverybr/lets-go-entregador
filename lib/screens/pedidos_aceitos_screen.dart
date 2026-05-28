import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/pedido_card_widget.dart';
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

  @override
  void initState() {
    super.initState();
    _buscar();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
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
      final data = await _supabase
          .from('pedidos')
          .select('*, lojas(nome, latitude, longitude)')
          .eq('motoboy_id', user.id)
          .inFilter('status', ['aceito', 'chegou_local', 'em_rota', 'retornando'])
          .not('status', 'in', '("finalizado","cancelado")')
          .order('aceito_em', ascending: false);
      if (mounted) setState(() {
        _pedidos = List<Map<String, dynamic>>.from(data);
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
  Color _cor(String s) => const Color(0xFF1A56DB);

  String _label(String s) {
    switch (s) {
      case 'aceito':       return 'Aceito';
      case 'chegou_local': return 'No local';
      case 'em_rota':      return 'Em rota';
      case 'retornando':   return 'Retornando';
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
                      return PedidoCardWidget(
                        pedido: p,
                        statusLabel: _label(status),
                        statusCor: _cor(status),
                        botaoCor: _cor(status),
                        isRetornando: isRetornando,
                        onTap: () => _abrirEntrega(p),
                      );
                    },
                  ),
                ),
    );
  }
}
