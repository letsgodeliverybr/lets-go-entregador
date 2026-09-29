import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import '../utils/vagas_utils.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'vaga_detalhe_screen.dart';

// Duas abas: "Disponíveis" (vagas abertas do dia escolhido) e "Minhas vagas"
// (as que o entregador aceitou — hoje em destaque, próximas e histórico).
//
// vagas_motoboy_fixo NÃO está na publicação do Realtime (só pedidos), então
// mudanças feitas pelo painel (cancelar/desatribuir/finalizar) chegam por:
// troca de aba, volta do app pro primeiro plano, puxar pra atualizar, timer de
// 30s enquanto a tela está aberta e, na hora, pelo push da notify-vaga
// (NotificationService.vagasAtualizadas).
class VagasScreen extends StatefulWidget {
  const VagasScreen({super.key});
  @override
  State<VagasScreen> createState() => _VagasScreenState();
}

class _VagasScreenState extends State<VagasScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _azul = Color(0xFF1A56DB);
  static const _fundo = Color(0xFF0D0F14);
  static const _card = Color(0xFF161820);
  static const _borda = Color(0xFF2A2D35);

  final _supabase = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 2, vsync: this);
  Timer? _timer;

  bool _carregandoPerfil = true;
  bool _podeVerVagas = false;

  DateTime _diaSelecionado = DateTime.now();
  bool _carregandoVagas = false;
  List<Map<String, dynamic>> _vagas = [];

  bool _carregandoMinhas = false;
  List<Map<String, dynamic>> _minhas = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _recarregar();
    });
    NotificationService.vagasAtualizadas.addListener(_recarregar);
    _verificarModalVeiculo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.vagasAtualizadas.removeListener(_recarregar);
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recarregar();
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
      if (_podeVerVagas) {
        _buscarVagas(_diaSelecionado);
        _buscarMinhas();
        _timer = Timer.periodic(const Duration(seconds: 30), (_) => _recarregar(silencioso: true));
      }
    } catch (_) {
      if (mounted) setState(() => _carregandoPerfil = false);
    }
  }

  void _recarregar({bool silencioso = false}) {
    if (!mounted || !_podeVerVagas) return;
    _buscarVagas(_diaSelecionado, silencioso: silencioso);
    _buscarMinhas(silencioso: silencioso);
  }

  Future<void> _buscarVagas(DateTime dia, {bool silencioso = false}) async {
    if (!silencioso) setState(() => _carregandoVagas = true);
    try {
      final data = await _supabase
          .from('vagas_motoboy_fixo')
          .select('*, lojas(nome, endereco, telefone)')
          .eq('data', dataIso(dia))
          .eq('status', 'disponivel')
          .order('horario_inicio');
      if (mounted) {
        setState(() { _vagas = List<Map<String, dynamic>>.from(data); _carregandoVagas = false; });
      }
    } catch (e) {
      if (mounted && !silencioso) setState(() { _vagas = []; _carregandoVagas = false; });
    }
  }

  Future<void> _buscarMinhas({bool silencioso = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    if (!silencioso) setState(() => _carregandoMinhas = true);
    try {
      // Histórico dos últimos 30 dias + tudo que vem pela frente.
      final desde = dataIso(DateTime.now().subtract(const Duration(days: 30)));
      final data = await _supabase
          .from('vagas_motoboy_fixo')
          .select('*, lojas(nome, endereco, telefone)')
          .eq('entregador_id', user.id)
          .gte('data', desde)
          .order('data');
      if (mounted) {
        setState(() { _minhas = List<Map<String, dynamic>>.from(data); _carregandoMinhas = false; });
      }
    } catch (e) {
      if (mounted && !silencioso) setState(() { _minhas = []; _carregandoMinhas = false; });
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
            primary: _azul,
            onPrimary: Colors.white,
            surface: _card,
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: _fundo,
        ),
        child: child!,
      ),
    );
    if (novaData != null) {
      setState(() => _diaSelecionado = novaData);
      _buscarVagas(novaData);
    }
  }

  Future<void> _abrirDetalhe(Map<String, dynamic> vaga) async {
    final aceitou = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VagaDetalheScreen(vaga: vaga)),
    );
    if (!mounted) return;
    _recarregar();
    // Aceitou: a vaga sai de Disponíveis e aparece em Minhas vagas.
    if (aceitou == 'aceita') _tabs.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final ativas = agruparMinhasVagas(_minhas, DateTime.now());
    final qtdAtivas = ativas.destaque.length + ativas.proximas.length;

    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _fundo,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Vagas de Motoboy Fixo', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: _podeVerVagas
            ? TabBar(
                controller: _tabs,
                indicatorColor: _azul,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                tabs: [
                  const Tab(text: 'Disponíveis'),
                  Tab(text: qtdAtivas > 0 ? 'Minhas vagas ($qtdAtivas)' : 'Minhas vagas'),
                ],
              )
            : null,
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 3),
      body: _carregandoPerfil
          ? const Center(child: CircularProgressIndicator(color: _azul))
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
              : TabBarView(controller: _tabs, children: [_abaDisponiveis(), _abaMinhas()]),
    );
  }

  // ── Aba Disponíveis ──────────────────────────────────────────────────────
  Widget _abaDisponiveis() {
    final dataFormatada = dataBr(dataIso(_diaSelecionado));
    return Column(children: [
      GestureDetector(
        onTap: _abrirCalendario,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borda),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today, color: _azul, size: 18),
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
            ? const Center(child: CircularProgressIndicator(color: _azul))
            : RefreshIndicator(
                onRefresh: () => _buscarVagas(_diaSelecionado),
                color: _azul,
                child: _vagas.isEmpty
                    ? _vazio(Icons.event_busy_outlined, 'Nenhuma vaga disponível em $dataFormatada')
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _vagas.length,
                        itemBuilder: (_, i) => _buildCard(_vagas[i]),
                      ),
              ),
      ),
    ]);
  }

  // ── Aba Minhas vagas ─────────────────────────────────────────────────────
  Widget _abaMinhas() {
    if (_carregandoMinhas && _minhas.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _azul));
    }
    final g = agruparMinhasVagas(_minhas, DateTime.now());
    final vazio = g.destaque.isEmpty && g.proximas.isEmpty && g.historico.isEmpty;
    return RefreshIndicator(
      onRefresh: () => _buscarMinhas(),
      color: _azul,
      child: vazio
          ? _vazio(Icons.event_available_outlined, 'Você ainda não aceitou nenhuma vaga',
              sub: 'As vagas que você aceitar aparecem aqui.')
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (g.destaque.isNotEmpty) ...[
                  _secao('Hoje'),
                  ...g.destaque.map((v) => _buildCard(v, destaque: true)),
                ],
                if (g.proximas.isNotEmpty) ...[
                  _secao('Próximas'),
                  ...g.proximas.map(_buildCard),
                ],
                if (g.historico.isNotEmpty) ...[
                  _secao('Histórico (30 dias)'),
                  ...g.historico.map(_buildCard),
                ],
              ],
            ),
    );
  }

  Widget _secao(String titulo) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 0, 10),
        child: Text(titulo.toUpperCase(),
            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6)),
      );

  // ListView pra o RefreshIndicator funcionar também com a lista vazia.
  Widget _vazio(IconData icone, String texto, {String? sub}) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(icone, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 15)),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ],
      );

  Widget _buildCard(Map<String, dynamic> vaga, {bool destaque = false}) {
    final loja = vaga['lojas'] as Map<String, dynamic>?;
    final nomeLoja = (loja?['nome'] ?? 'Loja').toString();
    final endereco = (loja?['endereco'] ?? '—').toString();
    final selo = seloSituacao(situacaoVaga(vaga, DateTime.now()));
    final encerrada = selo.rotulo == 'Finalizada' || selo.rotulo == 'Cancelada';

    return GestureDetector(
      onTap: () => _abrirDetalhe(vaga),
      child: Opacity(
        opacity: encerrada ? .6 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: destaque ? const Color(0xFF12241A) : _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: destaque ? selo.cor : _borda, width: destaque ? 1.5 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: _azul, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.store, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(nomeLoja,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              _selo(selo.rotulo, selo.cor),
            ]),
            const SizedBox(height: 12),
            _info(Icons.calendar_today, dataBr(vaga['data']?.toString())),
            _info(Icons.access_time, periodo(vaga)),
            _info(Icons.location_on_outlined, endereco),
            _info(Icons.attach_money, valorBr(vaga['valor'])),
            const SizedBox(height: 2),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('Ver detalhes', style: TextStyle(color: _azul, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _info(IconData icone, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icone, color: _azul, size: 14),
          const SizedBox(width: 6),
          Expanded(child: Text(texto, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        ]),
      );

  Widget _selo(String texto, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cor.withOpacity(0.5)),
        ),
        child: Text(texto, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
