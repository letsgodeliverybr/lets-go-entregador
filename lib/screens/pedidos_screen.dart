import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PedidosScreen extends StatelessWidget {
  const PedidosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entregadorId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text('Pedidos Disponíveis',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('pedidos')
            .where('status', isEqualTo: 'Recebido')
            .where('entregadorId', isEqualTo: '')
            .orderBy('criadoEm', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, color: Colors.white30, size: 64),
                  SizedBox(height: 16),
                  Text('Nenhum pedido disponível.',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                ],
              ),
            );
          }

          final pedidos = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: pedidos.length,
            itemBuilder: (_, i) {
              final p = pedidos[i].data() as Map<String, dynamic>;
              final docId = pedidos[i].id;
              return _CardPedido(pedido: p, docId: docId, entregadorId: entregadorId);
            },
          );
        },
      ),
    );
  }
}

class _CardPedido extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final String docId;
  final String? entregadorId;

  const _CardPedido({required this.pedido, required this.docId, this.entregadorId});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A56DB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.store, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pedido['estabelecimento'] ?? 'Estabelecimento',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(pedido['enderecoEstabelecimento'] ?? '',
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, color: Color(0xFF1A56DB), size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(pedido['enderecoEntrega'] ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.straighten, color: Color(0xFF1A56DB), size: 14),
                  const SizedBox(width: 4),
                  Text(pedido['distancia'] ?? '',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
              Text(pedido['valorEntregador'] != null
                  ? 'R\$ ${pedido['valorEntregador'].toStringAsFixed(2)}'
                  : '',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A56DB),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _aceitarPedido(context),
              child: const Text('Aceitar Pedido',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _aceitarPedido(BuildContext context) async {
    if (entregadorId == null) return;
    await FirebaseFirestore.instance.collection('pedidos').doc(docId).update({
      'status': 'Aceito',
      'entregadorId': entregadorId,
      'aceitoEm': FieldValue.serverTimestamp(),
    });
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _PedidoAtivoScreen(docId: docId, pedido: pedido),
      ));
    }
  }
}

class _PedidoAtivoScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> pedido;
  const _PedidoAtivoScreen({required this.docId, required this.pedido});

  @override
  State<_PedidoAtivoScreen> createState() => _PedidoAtivoScreenState();
}

class _PedidoAtivoScreenState extends State<_PedidoAtivoScreen> {
  Future<void> _atualizarStatus(String novoStatus) async {
    await FirebaseFirestore.instance
        .collection('pedidos')
        .doc(widget.docId)
        .update({'status': novoStatus, 'atualizadoEm': FieldValue.serverTimestamp()});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text('Pedido Ativo',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('pedidos')
            .doc(widget.docId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final p = snapshot.data!.data() as Map<String, dynamic>;
          final status = p['status'] ?? '';
          final codigoIfood = p['codigoIfood'];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoCard(p),
                const SizedBox(height: 16),
                _statusCard(status),
                const SizedBox(height: 16),
                if (codigoIfood != null && status == 'No Cliente')
                  _codigoIfoodCard(codigoIfood),
                const SizedBox(height: 16),
                _botoesAcao(status, codigoIfood),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoCard(Map<String, dynamic> p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p['estabelecimento'] ?? '',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _infoRow(Icons.location_on, 'Retirada: ${p['enderecoEstabelecimento'] ?? ''}'),
          const SizedBox(height: 4),
          _infoRow(Icons.home, 'Entrega: ${p['enderecoEntrega'] ?? ''}'),
          const SizedBox(height: 4),
          _infoRow(Icons.person, 'Cliente: ${p['clienteNome'] ?? ''}'),
          const SizedBox(height: 4),
          _infoRow(Icons.phone, p['clienteTelefone'] ?? ''),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String texto) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1A56DB), size: 14),
        const SizedBox(width: 6),
        Expanded(child: Text(texto, style: const TextStyle(color: Colors.white70, fontSize: 13))),
      ],
    );
  }

  Widget _statusCard(String status) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A56DB).withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1A56DB)),
      ),
      child: Text('Status: $status',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF1A56DB), fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }

  Widget _codigoIfoodCard(String codigo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: Column(
        children: [
          const Text('Código iFood', style: TextStyle(color: Colors.red, fontSize: 13)),
          const SizedBox(height: 8),
          Text(codigo,
              style: const TextStyle(
                  color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8)),
        ],
      ),
    );
  }

  Widget _botoesAcao(String status, String? codigoIfood) {
    if (status == 'Aceito') {
      return _botao('Cheguei no Local', Icons.store, () => _atualizarStatus('No Estabelecimento'));
    }
    if (status == 'No Estabelecimento') {
      return _botao('Sair para Entrega', Icons.delivery_dining, () => _atualizarStatus('Em Rota'));
    }
    if (status == 'Em Rota') {
      return _botao('Cheguei no Cliente', Icons.person_pin_circle, () => _atualizarStatus('No Cliente'));
    }
    if (status == 'No Cliente') {
      if (codigoIfood != null) {
        return _botao('Confirmar Código iFood', Icons.check_circle, () => _atualizarStatus('Finalizado'), cor: Colors.red);
      }
      return _botao('Finalizar Entrega', Icons.check_circle, () => _finalizarEntrega());
    }
    if (status == 'Finalizado') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Entrega Finalizada!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    return const SizedBox();
  }

  Widget _botao(String texto, IconData icon, VoidCallback onTap, {Color cor = const Color(0xFF1A56DB)}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: cor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(texto, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  Future<void> _finalizarEntrega() async {
    await _atualizarStatus('Finalizado');
    if (mounted) Navigator.pop(context);
  }
}
