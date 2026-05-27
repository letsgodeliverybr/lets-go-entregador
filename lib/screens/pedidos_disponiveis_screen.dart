import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/pedido_card_widget.dart';
import 'aceitar_pedido_screen.dart';

class PedidosDisponiveisScreen extends StatefulWidget {
  const PedidosDisponiveisScreen({super.key});
  @override
  State<PedidosDisponiveisScreen> createState() => _State();
}

class _State extends State<PedidosDisponiveisScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pedidos = [];
  bool _carregando = true;
  Timer? _timer;
  final Set<String> _idsNotificados = {};

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
    try {
      final data = await _supabase
          .from('pedidos')
          .select()
          .eq('status', 'pronto').or('motoboy_id.is.null,motoboy_id.eq.${user.id}')
          .order('pronto_em', ascending: true);

      final lista = List<Map<String, dynamic>>.from(data);

      for (final p in lista) {
        final id = p['id'].toString();
        if (!_idsNotificados.contains(id)) {
          _idsNotificados.add(id);
          HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 300));
          HapticFeedback.heavyImpact();
        }
      }

      if (mounted) setState(() { _pedidos = lista; _carregando = false; });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirConfirmacao(Map<String, dynamic> pedido) async {
    _timer?.cancel();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AceitarPedidoScreen(pedido: pedido)));
    await _buscar();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        automaticallyImplyLeading: false,
        title: Row(children: [
          const Text('Pedidos disponíveis',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          if (_pedidos.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFec4899), borderRadius: BorderRadius.circular(20)),
              child: Text('${_pedidos.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _buscar)],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFec4899)))
          : _pedidos.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.moped_outlined, color: Colors.grey.shade700, size: 72),
                  const SizedBox(height: 16),
                  const Text('Nenhum pedido disponível', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('Novos pedidos aparecerão aqui automaticamente',
                      style: TextStyle(color: Color(0xFF555), fontSize: 13)),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: _buscar,
                    icon: const Icon(Icons.refresh, color: Color(0xFFec4899)),
                    label: const Text('Atualizar', style: TextStyle(color: Color(0xFFec4899))),
                  ),
                ]))
              : RefreshIndicator(
                  onRefresh: _buscar,
                  color: const Color(0xFFec4899),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pedidos.length,
                    itemBuilder: (_, i) => PedidoCardWidget(
                      pedido: _pedidos[i],
                      statusLabel: 'Pronto',
                      statusCor: const Color(0xFFec4899),
                      // sem botão — card clicável
                      
                      botaoCor: const Color(0xFFec4899),
                      onTap: () => _abrirConfirmacao(_pedidos[i]),
                    ),
                  ),
                ),
    );
  }
}