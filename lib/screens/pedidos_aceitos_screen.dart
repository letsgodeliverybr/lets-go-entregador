import 'package:flutter/material.dart';

class PedidosAceitosScreen extends StatefulWidget {
  const PedidosAceitosScreen({super.key});
  @override
  State<PedidosAceitosScreen> createState() => _PedidosAceitosScreenState();
}

class _PedidosAceitosScreenState extends State<PedidosAceitosScreen> {
  final List<Map<String, String>> _pedidos = [
    {'nome': 'McDonald\'s Consolação', 'enderecoLoja': 'Av. Paulista, 1000', 'enderecoCliente': 'Rua Oscar Freire, 900', 'distancia': '1,2 km', 'valor': 'R\$ 7,00', 'status': 'Em andamento', 'data': 'Hoje'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Pedidos Aceitos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _pedidos.isEmpty
          ? const Center(child: Text('Nenhum pedido aceito no momento.', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pedidos.length,
              itemBuilder: (context, i) {
                final p = _pedidos[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 44, height: 44,
                        decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.store, color: Colors.white, size: 24)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['nome']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 14),
                            const SizedBox(width: 4),
                            Text(p['status']!, style: const TextStyle(color: Color(0xFF22C55E), fontSize: 12)),
                            const SizedBox(width: 8),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFF2A2D35), borderRadius: BorderRadius.circular(6)),
                              child: Text(p['data']!, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                          ]),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Row(children: [
                              const Icon(Icons.straighten, color: Color(0xFF1A56DB), size: 14),
                              const SizedBox(width: 4),
                              Text(p['distancia']!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ]),
                            Text(p['valor']!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 10),
                          SizedBox(width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF22C55E),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0),
                              child: const Text('Confirmar entrega', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            )),
                        ],
                      )),
                    ],
                  ),
                );
              }),
    );
  }
}
