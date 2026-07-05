import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'vaga_detalhe_screen.dart';

class VagasScreen extends StatefulWidget {
  const VagasScreen({super.key});
  @override
  State<VagasScreen> createState() => _VagasScreenState();
}

class _VagasScreenState extends State<VagasScreen> {
  final _supabase = Supabase.instance.client;

  bool _carregandoPerfil = true;
  bool _podeVerVagas = false;

  DateTime _diaSelecionado = DateTime.now();
  bool _carregandoVagas = false;
  List<Map<String, dynamic>> _vagas = [];

  @override
  void initState() {
    super.initState();
    _verificarModalVeiculo();
  }

  Future<void> _verificarModalVeiculo() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _carregandoPerfil = false);
      return;
    }
    try {
      final e = await _supabase
          .from('entregadores')
          .select('modal_veiculo')
          .eq('id', user.id)
          .maybeSingle();
      final modal = e?['modal_veiculo']?.toString() ?? 'moto';
      if (mounted) {
        setState(() {
          _podeVerVagas = modal == 'moto';
          _carregandoPerfil = false;
        });
      }
      if (_podeVerVagas) _buscarVagas(_diaSelecionado);
    } catch (_) {
      if (mounted) setState(() => _carregandoPerfil = false);
    }
  }

  Future<void> _buscarVagas(DateTime dia) async {
    setState(() => _carregandoVagas = true);
    final dataStr =
        '${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';
    try {
      final data = await _supabase
          .from('vagas_motoboy_fixo')
          .select('*, lojas(nome, endereco, telefone)')
          .eq('data', dataStr)
          .eq('status', 'disponivel')
          .order('horario_inicio');
      if (mounted) {
        setState(() { _vagas = List<Map<String, dynamic>>.from(data); _carregandoVagas = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _vagas = []; _carregandoVagas = false; });
    }
  }

  Future<void> _abrirCalendario() async {
    final novaData = await showDatePicker(
      context: context,
      initialDate: _diaSelecionado,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF1A56DB),
            onPrimary: Colors.white,
            surface: Color(0xFF161820),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF0D0F14),
        ),
        child: child!,
      ),
    );
    if (novaData != null) {
      setState(() => _diaSelecionado = novaData);
      _buscarVagas(novaData);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataFormatada =
        '${_diaSelecionado.day.toString().padLeft(2, '0')}/${_diaSelecionado.month.toString().padLeft(2, '0')}/${_diaSelecionado.year}';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Vagas de Motoboy Fixo', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 3),
      body: _carregandoPerfil
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : !_podeVerVagas
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.two_wheeler_outlined, color: Color(0xFF374151), size: 80),
                      SizedBox(height: 24),
                      Text('Disponível apenas para motos',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      SizedBox(height: 12),
                      Text(
                        'As vagas de motoboy fixo são exclusivas para entregadores cadastrados com veículo do tipo moto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.5),
                      ),
                    ]),
                  ),
                )
              : Column(children: [
                  GestureDetector(
                    onTap: _abrirCalendario,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161820),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2A2D35)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today, color: Color(0xFF1A56DB), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('Vagas de $dataFormatada',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: _carregandoVagas
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
                        : _vagas.isEmpty
                            ? Center(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.event_busy_outlined, color: Colors.white24, size: 64),
                                  const SizedBox(height: 16),
                                  Text('Nenhuma vaga disponível em $dataFormatada',
                                      style: const TextStyle(color: Colors.white54, fontSize: 15)),
                                ]),
                              )
                            : RefreshIndicator(
                                onRefresh: () => _buscarVagas(_diaSelecionado),
                                color: const Color(0xFF1A56DB),
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _vagas.length,
                                  itemBuilder: (_, i) => _buildCard(_vagas[i]),
                                ),
                              ),
                  ),
                ]),
    );
  }

  Widget _buildCard(Map<String, dynamic> vaga) {
    final loja = vaga['lojas'] as Map<String, dynamic>?;
    final nomeLoja = (loja?['nome'] ?? 'Loja').toString();
    final endereco = (loja?['endereco'] ?? '—').toString();
    final valor = (vaga['valor'] as num?)?.toDouble() ?? 0;
    final horarioInicio = (vaga['horario_inicio'] ?? '—').toString();
    final horarioFim = (vaga['horario_fim'] ?? '—').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.store, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(nomeLoja,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.location_on_outlined, color: Color(0xFF1A56DB), size: 14),
          const SizedBox(width: 4),
          Expanded(child: Text(endereco, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.attach_money, color: Color(0xFF1A56DB), size: 14),
          const SizedBox(width: 4),
          Text('R\$ ${valor.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.access_time, color: Color(0xFF22C55E), size: 14),
          const SizedBox(width: 4),
          Text('$horarioInicio - $horarioFim', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () async {
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => VagaDetalheScreen(vaga: vaga)),
              );
              if (resultado == true) _buscarVagas(_diaSelecionado);
            },
            child: const Text('Visualizar vaga',
                style: TextStyle(color: Color(0xFF1A56DB), fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}
