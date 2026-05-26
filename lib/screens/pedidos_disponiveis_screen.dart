import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'entrega_screen.dart';

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
          .or('status.eq.pronto,status_detalhado.eq.pronto')
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

  Future<void> _aceitar(Map<String, dynamic> pedido) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final result = await _supabase
          .from('pedidos')
          .update({
            'status': 'aceito',
            'status_detalhado': 'aceito',
            'aceito_em': DateTime.now().toIso8601String(),
            'motoboy_id': user.id,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .or('status.eq.pronto,status_detalhado.eq.pronto')
          .eq('id', pedido['id'])
          .select();

      if (!mounted) return;

      if (result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido já foi aceito por outro entregador'), backgroundColor: Colors.red),
        );
        _buscar();
        return;
      }

      _timer?.cancel();
      await Navigator.push(context, MaterialPageRoute(builder: (_) => EntregaScreen(pedido: pedido)));
      _buscar();
      _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        title: Row(
          children: [
            const Text('Pedidos disponíveis',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            if (_pedidos.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFec4899),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_pedidos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _buscar),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFec4899)))
          : _pedidos.isEmpty
              ? _buildVazio()
              : RefreshIndicator(
                  onRefresh: _buscar,
                  color: const Color(0xFFec4899),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pedidos.length,
                    itemBuilder: (_, i) => _CardPedido(
                      pedido: _pedidos[i],
                      onAceitar: () => _aceitar(_pedidos[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.moped_outlined, color: Colors.grey.shade700, size: 72),
          const SizedBox(height: 16),
          const Text('Nenhum pedido disponível',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Novos pedidos aparecerão aqui automaticamente',
              style: TextStyle(color: Color(0xFF555), fontSize: 13)),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _buscar,
            icon: const Icon(Icons.refresh, color: Color(0xFFec4899)),
            label: const Text('Atualizar', style: TextStyle(color: Color(0xFFec4899))),
          ),
        ],
      ),
    );
  }
}

class _CardPedido extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final VoidCallback onAceitar;
  const _CardPedido({required this.pedido, required this.onAceitar});

  @override
  Widget build(BuildContext context) {
    final valor = double.tryParse(pedido['valor']?.toString() ?? '0') ?? 0;
    final numero = pedido['numero'] ?? pedido['id'].toString().substring(0, 6);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        border: Border.all(color: const Color(0xFFec4899), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFec489915),
                  border: Border.all(color: const Color(0xFFec4899)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('#$numero',
                    style: const TextStyle(color: Color(0xFFec4899), fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFec489920), borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFFec4899), size: 8),
                    SizedBox(width: 4),
                    Text('Pronto', style: TextStyle(color: Color(0xFFec4899), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on, color: Color(0xFFec4899), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(pedido['endereco'] ?? '—',
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('R\$ ${valor.toStringAsFixed(2)}',
              style: const TextStyle(color: Color(0xFF10b981), fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFec4899),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: onAceitar,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 18),
                  SizedBox(width: 8),
                  Text('Aceitar pedido', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}