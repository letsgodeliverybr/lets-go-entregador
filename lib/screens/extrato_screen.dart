import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExtratoScreen extends StatefulWidget {
  const ExtratoScreen({super.key});
  @override
  State<ExtratoScreen> createState() => _ExtratoScreenState();
}

class _ExtratoScreenState extends State<ExtratoScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pedidos = [];
  bool _carregando = true;
  String _filtro = 'mes';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  DateTime get _inicio {
    final now = DateTime.now();
    switch (_filtro) {
      case 'hoje':
        return DateTime(now.year, now.month, now.day);
      case 'semana':
        // Segunda-feira da semana atual (weekday: 1=seg … 7=dom)
        return DateTime(now.year, now.month, now.day - (now.weekday - 1));
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final uid = _supabase.auth.currentUser?.id;
      debugPrint('ExtratoScreen: uid=$uid filtro=$_filtro inicio=${_inicio.toIso8601String()}');
      if (uid == null) {
        if (mounted) setState(() => _carregando = false);
        return;
      }

      debugPrint('UID: $uid');

      final raw = await _supabase
          .from('pedidos')
          .select('id, numero, taxa_motoboy, gorjeta, distancia_km, updated_at, loja_id, lojas(nome)')
          .eq('motoboy_id', _supabase.auth.currentUser!.id)
          .eq('status', 'finalizado')
          .gte('updated_at', _inicio.toIso8601String())
          .order('updated_at', ascending: false);
      final lista = List<Map<String, dynamic>>.from(raw);
      debugPrint('Pedidos encontrados: ${lista.length}');

      if (mounted) setState(() { _pedidos = lista; _carregando = false; });
    } catch (e) {
      debugPrint('ExtratoScreen error: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  double _valor(Map<String, dynamic> p) {
    final taxa = (p['taxa_motoboy'] as num?)?.toDouble() ?? 0;
    final gorjeta = (p['gorjeta'] as num?)?.toDouble() ?? 0;
    return taxa + gorjeta;
  }

  double get _total => _pedidos.fold(0, (s, p) => s + _valor(p));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        title: const Text('Extrato', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2D35)),
        ),
      ),
      body: Column(
        children: [
          _buildFiltros(),
          _buildTotal(),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
                : _pedidos.isEmpty
                    ? const Center(child: Text('Nenhuma entrega no período',
                          style: TextStyle(color: Colors.white54)))
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        color: const Color(0xFF1A56DB),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _pedidos.length,
                          itemBuilder: (_, i) => _buildItem(_pedidos[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    final labels = {'hoje': 'Hoje', 'semana': 'Semana', 'mes': 'Mês'};
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: ['hoje', 'semana', 'mes'].map((f) {
          final ativo = _filtro == f;
          return Expanded(
            child: GestureDetector(
              onTap: () { setState(() => _filtro = f); _carregar(); },
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: ativo ? const Color(0xFF1A56DB) : const Color(0xFF161820),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ativo ? const Color(0xFF1A56DB) : const Color(0xFF2A2D35)),
                ),
                child: Text(labels[f]!, textAlign: TextAlign.center,
                    style: TextStyle(
                        color: ativo ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTotal() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total do período', style: TextStyle(color: Colors.white54, fontSize: 13)),
          Text('${_pedidos.length} entrega${_pedidos.length != 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        const Spacer(),
        Text('R\$ ${_total.toStringAsFixed(2)}',
            style: const TextStyle(color: Color(0xFF10b981), fontSize: 22, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _buildItem(Map<String, dynamic> p) {
    final data = p['updated_at'] != null
        ? DateTime.tryParse(p['updated_at'].toString())?.toLocal()
        : null;
    final dataStr = data != null
        ? '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year} às ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}'
        : '—';
    final nomeLoja = (p['lojas'] as Map?)?['nome']?.toString() ?? 'Loja desconhecida';
    final km = double.tryParse(p['distancia_km']?.toString() ?? '0') ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('#${p['numero'] ?? (p['id'] as String).substring(0, 6)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 3),
          Text(dataStr,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          const SizedBox(height: 2),
          Text(nomeLoja, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (km > 0)
            Text('${km.toStringAsFixed(1)} km',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        Text('R\$ ${_valor(p).toStringAsFixed(2)}',
            style: const TextStyle(color: Color(0xFF10b981), fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
    );
  }
}
