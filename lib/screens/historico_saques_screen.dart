import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricoSaquesScreen extends StatefulWidget {
  const HistoricoSaquesScreen({super.key});
  @override
  State<HistoricoSaquesScreen> createState() => _HistoricoSaquesScreenState();
}

class _HistoricoSaquesScreenState extends State<HistoricoSaquesScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _saques = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) { if (mounted) setState(() => _carregando = false); return; }
      final data = await _supabase
          .from('saques')
          .select('id, valor, status, created_at')
          .eq('entregador_id', uid)
          .order('created_at', ascending: false);
      if (mounted) setState(() { _saques = List<Map<String, dynamic>>.from(data); _carregando = false; });
    } catch (e) {
      if (mounted) setState(() { _saques = []; _carregando = false; });
    }
  }

  Color _corStatus(String? s) {
    switch (s) {
      case 'pago': return const Color(0xFF10b981);
      case 'recusado': return const Color(0xFFef4444);
      default: return const Color(0xFFf59e0b);
    }
  }

  String _labelStatus(String? s) {
    switch (s) {
      case 'pago': return 'Pago';
      case 'recusado': return 'Recusado';
      default: return 'Pendente';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        title: const Text('Histórico de Saques', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2D35)),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : _saques.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.history, color: Colors.white24, size: 64),
                    const SizedBox(height: 16),
                    const Text('Nenhum saque realizado',
                        style: TextStyle(color: Colors.white54, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text('Seus saques aparecerão aqui',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: _carregar,
                      icon: const Icon(Icons.refresh, color: Color(0xFF1A56DB)),
                      label: const Text('Atualizar', style: TextStyle(color: Color(0xFF1A56DB))),
                    ),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  color: const Color(0xFF1A56DB),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _saques.length,
                    itemBuilder: (_, i) {
                      final s = _saques[i];
                      final data = s['created_at'] != null
                          ? DateTime.tryParse(s['created_at'].toString())
                          : null;
                      final dataStr = data != null
                          ? '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}  ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}'
                          : '—';
                      final valor = double.tryParse(s['valor']?.toString() ?? '0') ?? 0;
                      final cor = _corStatus(s['status']?.toString());
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161820),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2A2D35)),
                        ),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(dataStr, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text('R\$ ${valor.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: cor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: cor.withOpacity(0.4)),
                            ),
                            child: Text(_labelStatus(s['status']?.toString()),
                                style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
