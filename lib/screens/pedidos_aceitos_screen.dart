import 'package:flutter/material.dart';

class PedidosAceitosScreen extends StatelessWidget {
  const PedidosAceitosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos Aceitos'),
        backgroundColor: const Color(0xFFE8380D),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Nenhum pedido aceito no momento.'),
      ),
    );
  }
}
