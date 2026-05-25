import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'mapa_pedido_screen.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});
  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  final List<Map<String, dynamic>> _pedidos = [
    {'nome': 'ARMAZEM DA CERVEJA - CENTRO', 'distancia': '1,777km', 'valor': 'R\$ 8,19', 'data': '24/05/2025', 'status': 'Disponível'},
    {'nome': 'PIZZARIA BOA MESA - CENTRO', 'distancia': '2,312km', 'valor': 'R\$ 12,50', 'data': '24/05/2025', 'status': 'Disponível'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text('Pedidos Disponíveis', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _pedidos.isEmpty
          ? const Center(child: Text('Nenhum pedido disponível.', style: TextStyle(color: Colors.white70)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pedidos.length,
              itemBuilder: (_, i) {
                final p = _pedidos[i];
                return Dismissible(
                  key: ValueKey(i),
                  direction: DismissDirection.horizontal,
                  background: Container(color: Colors.red.shade900, margin: const EdgeInsets.only(bottom: 12), alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), child: const Icon(Icons.close, color: Colors.white)),
                  secondaryBackground: Container(color: Colors.red.shade900, margin: const EdgeInsets.only(bottom: 12), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.close, color: Colors.white)),
                  onDismissed: (_) => setState(() => _pedidos.removeAt(i)),
                  child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MapaPedidoScreen(nomeLoja: p['nome'], localLoja: const LatLng(-21.1775, -47.8100), localPedido: const LatLng(-21.1800, -47.8150)))),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.store, color: Colors.white, size: 24)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p['nome'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Row(children: [const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 14), const SizedBox(width: 4), Text(p['status'], style: const TextStyle(color: Color(0xFF22C55E), fontSize: 12))]),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF2A2D35), borderRadius: BorderRadius.circular(6)), child: Text(p['data'], style: const TextStyle(color: Colors.white70, fontSize: 12))),
                            ]),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Row(children: [const Icon(Icons.straighten, color: Color(0xFF1A56DB), size: 14), const SizedBox(width: 4), Text(p['distancia'], style: const TextStyle(color: Colors.white, fontSize: 13))]),
                              Text(p['valor'], style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            ]),
                          ])),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}