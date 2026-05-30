import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExtratoScreen extends StatefulWidget {
  const ExtratoScreen({super.key});
  @override
  State<ExtratoScreen> createState() => _ExtratoScreenState();
}

class _ExtratoScreenState extends State<ExtratoScreen> {
  final _supabase = Supabase.instance.client;
  static const _tabelaPagamentoId = '7bf1cf41-b3f2-4694-b326-d4e830dae8e1';

  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _faixas = [];
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
        return now.subtract(const Duration(days: 7));
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return;

      final futures = <Future>[
        _supabase
            .from('pedidos')
            .select('id, numero, updated_at, distancia_km, taxa_entrega_motoboy, taxa_entrega, gorjeta, com_retorno, lojas(nome)')
            .eq('entregador_id', uid)
            .eq('status', 'finalizado')
            .gte('updated_at', _inicio.toIso8601String())
            .order('updated_at', ascending: false),
        if (_faixas.isEmpty)
          _supabase
              .from('tabelas_preco_faixas')
              .select('km_ate, valor_sem_retorno, valor_com_retorno')
              .eq('tabela_id', _tabelaPagamentoId)
              .order('km_ate'),
      ];

      final results = await Future.wait(futures);
      final lista = List<Map<String, dynamic>>.from(results[0] as List);
      if (results.length > 1) {
        _faixas = List<Map<String, dynamic>>.from(results[1] as List);
      }

      if (mounted) setState(() { _pedidos = lista; _carregando = false; });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  double _valor(Map<String, dynamic> p) {
    if (p['taxa_entrega_motoboy'] != null) {
      return double.tryParse(p['taxa_entrega_motoboy'].toString()) ?? 0;
    }
    if (_faixas.isEmpty) {
      return double.tryParse(p['taxa_entrega']?.toString() ?? '0') ?? 0;
    }
    final km = double.tryParse(p['distancia_km']?.toString() ?? '0') ?? 0;
    final temRetorno = p['com_retorno'] == true;
    final faixa = km <= 0
        ? _faixas.first
        : _faixas.firstWhere(
            (f) => km <= (double.tryParse(f['km_ate']?.toString() ?? '0') ?? 0),
            orElse: () => _faixas.last);
    final campo = temRetorno ? 'valor_com_retorno' : 'valor_sem_retorno';
    double base = double.tryParse(faixa[campo]?.toString() ?? '0') ?? 0;
    base += double.tryParse(p['gorjeta']?.toString() ?? '0') ?? 0;
    return base;
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
    final nomeLoja = (p['lojas'] as Map?)?['nome'] as String? ?? '—';
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
