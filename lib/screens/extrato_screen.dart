import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';

class ExtratoScreen extends StatefulWidget {
  const ExtratoScreen({super.key});
  @override
  State<ExtratoScreen> createState() => _ExtratoScreenState();
}

class _ExtratoScreenState extends State<ExtratoScreen> {
  final _supabase = Supabase.instance.client;

  DateTimeRange? _periodo;
  List<Map<String, dynamic>> _pedidos = [];
  bool _carregando = false;
  bool _buscou = false;

  double get _totalGanho {
    double total = 0;
    for (final p in _pedidos) {
      final taxa =
          double.tryParse(p['taxa_entrega']?.toString() ?? '0') ?? 0;
      total += taxa;
    }
    return total;
  }

  // ── seleciona período com DateRangePicker ────────────────────────────────
  Future<void> _selecionarPeriodo() async {
    final hoje = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: hoje,
      initialDateRange: _periodo ??
          DateTimeRange(
            start: DateTime(hoje.year, hoje.month, 1),
            end: hoje,
          ),
      locale: const Locale('pt', 'BR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1A56DB),
              onPrimary: Colors.white,
              surface: Color(0xFF161820),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0D0F14),
          ),
          child: child!,
        );
      },
    );
    if (range != null) {
      setState(() => _periodo = range);
      await _buscar();
    }
  }

  // ── busca pedidos finalizados no período ─────────────────────────────────
  Future<void> _buscar() async {
    if (_periodo == null) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _carregando = true;
      _buscou = true;
    });

    try {
      // Inclui o dia final inteiro (até 23:59:59)
      final fimDia = DateTime(
        _periodo!.end.year,
        _periodo!.end.month,
        _periodo!.end.day,
        23,
        59,
        59,
      );

      final data = await _supabase
          .from('pedidos')
          .select('id, numero, valor, taxa_entrega, created_at, updated_at, endereco, descricao')
          .eq('motoboy_id', user.id)
          .eq('status', 'finalizado')
          .gte('updated_at', _periodo!.start.toIso8601String())
          .lte('updated_at', fimDia.toIso8601String())
          .order('updated_at', ascending: false);

      if (mounted) {
        setState(() {
          _pedidos = List<Map<String, dynamic>>.from(data);
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── formatação ────────────────────────────────────────────────────────────
  String _formatarData(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _formatarPeriodo() {
    if (_periodo == null) return 'Selecionar período';
    final s = _periodo!.start;
    final e = _periodo!.end;
    return '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}/${s.year}'
        '  →  '
        '${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}/${e.year}';
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 3),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Extrato',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // ── Seletor de período ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: GestureDetector(
              onTap: _selecionarPeriodo,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161820),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1A56DB)),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_month,
                      color: Color(0xFF1A56DB), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _formatarPeriodo(),
                      style: TextStyle(
                        color: _periodo == null
                            ? Colors.white54
                            : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down,
                      color: Color(0xFF1A56DB), size: 24),
                ]),
              ),
            ),
          ),

          // ── Card de total ───────────────────────────────────────────────
          if (_buscou && !_carregando)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A56DB), Color(0xFF0f3fa0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total ganho no período',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          'R\$ ${_totalGanho.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Entregas',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          '${_pedidos.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),

          // ── Lista de pedidos ────────────────────────────────────────────
          Expanded(
            child: _carregando
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1A56DB)))
                : !_buscou
                    ? _buildPlaceholder()
                    : _pedidos.isEmpty
                        ? _buildVazio()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _pedidos.length,
                            itemBuilder: (_, i) =>
                                _buildItemExtrato(_pedidos[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemExtrato(Map<String, dynamic> p) {
    final taxa =
        double.tryParse(p['taxa_entrega']?.toString() ?? '0') ?? 0;
    final numero = p['numero']?.toString() ??
        p['id'].toString().substring(0, 8).toUpperCase();
    final endereco = p['endereco']?.toString() ?? '—';
    final data = _formatarData(p['updated_at']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Row(
        children: [
          // Ícone
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_outline,
                color: Colors.greenAccent, size: 20),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pedido #$numero',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Text(endereco,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(data,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),

          // Valor
          Text(
            'R\$ ${taxa.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.calendar_today_outlined,
            color: Colors.white24, size: 64),
        const SizedBox(height: 16),
        const Text('Selecione um período',
            style: TextStyle(color: Colors.white54, fontSize: 16)),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _selecionarPeriodo,
          icon: const Icon(Icons.date_range, color: Color(0xFF1A56DB)),
          label: const Text('Escolher datas',
              style: TextStyle(color: Color(0xFF1A56DB))),
        ),
      ]),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.inbox_outlined, color: Colors.white24, size: 64),
        const SizedBox(height: 16),
        const Text('Nenhuma entrega finalizada',
            style: TextStyle(color: Colors.white54, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('neste período',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _selecionarPeriodo,
          icon: const Icon(Icons.calendar_month, color: Color(0xFF1A56DB)),
          label: const Text('Alterar período',
              style: TextStyle(color: Color(0xFF1A56DB))),
        ),
      ]),
    );
  }
}
