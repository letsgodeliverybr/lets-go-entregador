import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'confirmar_saque_screen.dart';
import 'mapa_calor_screen.dart';
import 'drawer_screen.dart';
import 'entregador_home_screen.dart';
import 'cadastro_aprovacao_screen.dart';
import 'aguardo_aprovacao_screen.dart';
import '../services/tracking_service.dart';
import '../utils/saldo_semana.dart';
import '../widgets/app_bottom_nav_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  bool _carregando = false;
  bool _loadingStats = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  RealtimeChannel? _canal;
  Timer? _debounce;

  String _nome = '';
  double _saldoDia = 0;
  int _entregasHoje = 0;
  double _saldoSemana = 0;
  bool _refreshing = false;

  String get _uid => _supabase.auth.currentUser?.id ?? '';
  String? _entregadorId;
  String get _eid => _entregadorId ?? _uid;

  double _calcTaxaMotoboy(Map<String, dynamic> p) {
    final taxa = (p['taxa_motoboy'] as num?)?.toDouble() ?? 0;
    final gorjeta = (p['gorjeta'] as num?)?.toDouble() ?? 0;
    return taxa + gorjeta;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inicializar();
  }

  Future<void> _inicializar() async {
    await _buscarEntregadorId();
    _carregarDados();
    _iniciarRealtime();
  }

  Future<void> _buscarEntregadorId() async {
    final authId = _supabase.auth.currentUser?.id;
    if (authId == null) return;
    try {
      final byUserId = await _supabase
          .from('entregadores')
          .select('id')
          .eq('user_id', authId)
          .maybeSingle();
      if (byUserId != null) {
        _entregadorId = byUserId['id'] as String?;
      } else {
        final byId = await _supabase
            .from('entregadores')
            .select('id')
            .eq('id', authId)
            .maybeSingle();
        _entregadorId = (byId?['id'] as String?) ?? authId;
      }
    } catch (_) {
      _entregadorId = authId;
    }
    debugPrint('[UID] auth.uid: $authId, entregador.id: $_entregadorId, match: ${authId == _entregadorId}');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _carregarDados(silencioso: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _canal?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  void _iniciarRealtime() {
    if (_eid.isEmpty) return;
    _canal = _supabase
        .channel('home_saldo_$_eid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'motoboy_id',
            value: _eid,
          ),
          callback: (_) => _agendarRecarregar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'saques',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'entregador_id',
            value: _eid,
          ),
          callback: (_) => _agendarRecarregar(),
        )
        .subscribe();
  }

  void _agendarRecarregar() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _carregarDados(silencioso: true),
    );
  }

  Future<void> _carregarDados({bool silencioso = false}) async {
    if (_eid.isEmpty || _refreshing) return;
    _refreshing = true;
    if (!silencioso) setState(() => _loadingStats = true);
    try {
      final agora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      final inicioDia = DateTime.utc(agora.year, agora.month, agora.day)
          .add(const Duration(hours: 3))
          .toIso8601String();
      final uid = _supabase.auth.currentUser!.id;

      final r = await Future.wait<dynamic>([
        _supabase.from('entregadores').select('nome').eq('id', _eid).single(),
        _supabase
            .from('pedidos')
            .select('taxa_motoboy,taxa_entrega,gorjeta,updated_at')
            .eq('motoboy_id', uid)
            .eq('status', 'finalizado'),
        calcularSaldoSemana(),
      ]);

      final entregador = r[0] as Map<String, dynamic>;
      final todosPedidos = List<Map<String, dynamic>>.from(r[1] as List);
      final saldoDisponivel = r[2] as double;

      final listaDia = todosPedidos.where((p) {
        final dt = DateTime.tryParse(p['updated_at']?.toString() ?? '');
        return dt != null && dt.isAfter(DateTime.parse(inicioDia));
      }).toList();

      final totalDia = listaDia.fold<double>(0, (s, p) => s + _calcTaxaMotoboy(p));

      debugPrint('[HOME] UID=$_uid EID=$_eid pedidosDia=${listaDia.length} totalDia=$totalDia saldoDisponivel=$saldoDisponivel');

      if (mounted) {
        setState(() {
          final nomeRaw = entregador['nome']?.toString() ?? '';
          _nome = nomeRaw.contains('@') ? '' : nomeRaw;
          _saldoDia = totalDia;
          _entregasHoje = listaDia.length;
          _saldoSemana = saldoDisponivel;
          _loadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen _carregarDados error: $e');
      if (mounted) setState(() => _loadingStats = false);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _toggleOnline(bool value) async {
    if (!value) return; // na HomeScreen só ativamos o online
    if (_uid.isEmpty) return;
    setState(() => _carregando = true);
    try {
      final ent = await _supabase
          .from('entregadores')
          .select('aprovado, status_cadastro')
          .eq('id', _uid)
          .single();
      final aprovado = ent['aprovado'] == true;
      final statusCadastro = ent['status_cadastro']?.toString() ?? 'pendente';

      if (!aprovado) {
        if (!mounted) return;
        setState(() => _carregando = false);
        if (statusCadastro == 'em_analise') {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AguardoAprovacaoScreen()));
        } else {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CadastroAprovacaoScreen()));
        }
        return;
      }

      await _supabase.from('entregadores').update({
        'disponivel': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _uid);
      await TrackingService.iniciar(_uid);

      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const EntregadorHomeScreen()));
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0D0F14),
      drawer: const DrawerScreen(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Bem vindo!',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              icon: const Icon(Icons.notifications_outlined, color: Colors.white),
              onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPerfilRow(),
            const SizedBox(height: 16),
            _buildCardPrincipal(),
            const SizedBox(height: 16),
            _buildCardsRow(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 0),
    );
  }

  Widget _buildPerfilRow() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 28,
          backgroundColor: Color(0xFF1A56DB),
          child: Icon(Icons.person, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nome.isNotEmpty ? 'Olá, ${_nome.split(' ').first}' : 'Olá!',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const Text('Lets Go Delivery',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
            ],
          ),
        ),
        _buildToggle(),
      ],
    );
  }

  Widget _buildToggle() {
    return GestureDetector(
      onTap: _carregando ? null : () => _toggleOnline(true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2130),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2A2D35)),
        ),
        child: Row(
          children: [
            const Text('OFFLINE',
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            _carregando
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF1A56DB)))
                : Switch(
                    value: false,
                    onChanged: (_) => _toggleOnline(true),
                    activeColor: const Color(0xFF1A56DB),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPrincipal() {
    if (_loadingStats) {
      return Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF161820),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A2D35)),
        ),
        child: const Center(
            child: CircularProgressIndicator(color: Color(0xFF1A56DB))),
      );
    }

    if (_entregasHoje > 0) {
      return _buildCardBomTrabalho();
    }
    return _buildCardOffline();
  }

  Widget _buildCardBomTrabalho() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        children: [
          Container(
            height: 120,
            decoration: const BoxDecoration(
              color: Color(0xFF1E2130),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Center(
              child: Text('🏆', style: TextStyle(fontSize: 60)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Text('Bom trabalho hoje!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: _statCard(
                    'Saldo do dia',
                    'R\$ ${_saldoDia.toStringAsFixed(2)}',
                    const Color(0xFF10b981),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    'Entregas hoje',
                    '$_entregasHoje',
                    const Color(0xFF10b981),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _carregando ? null : () => _toggleOnline(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2130),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2A2D35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Voltar online',
                        style: TextStyle(
                            color: Color(0xFF1A56DB),
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    _carregando
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF1A56DB)))
                        : Switch(
                            value: false,
                            onChanged: (_) => _toggleOnline(true),
                            activeColor: const Color(0xFF1A56DB),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                  ]),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color cor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2130),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF64748b), fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: cor,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _buildCardOffline() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        children: [
          Container(
            height: 160,
            decoration: const BoxDecoration(
              color: Color(0xFF1E2130),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Center(
              child: Icon(Icons.inventory_2_outlined,
                  size: 72, color: Colors.white24),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Text('Você ainda não faturou hoje',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              const Text('Fique online para receber pedidos!',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _carregando ? null : () => _toggleOnline(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2130),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2A2D35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('OFFLINE',
                          style: TextStyle(
                              color: Colors.white60,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      _carregando
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF1A56DB)))
                          : Switch(
                              value: false,
                              onChanged: (_) => _toggleOnline(true),
                              activeColor: const Color(0xFF1A56DB),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildCardsRow() {
    return SizedBox(
      height: 180,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCardDemanda(),
          const SizedBox(width: 12),
          _buildCardSaldo(),
        ],
      ),
    );
  }

  Widget _buildCardDemanda() {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Demanda na sua região',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
          const SizedBox(height: 8),
          const Text(
              'No Mapa de Calor você pode ver as áreas da região em que há mais pedidos pra você',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MapaCalorScreen())),
              icon:
                  const Icon(Icons.local_fire_department, color: Colors.white),
              label: const Text('Abrir mapa de calor >',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A56DB),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSaldo() {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saldo disponível',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            'R\$ ${_saldoSemana.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Color(0xFF10b981),
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('Reset Domingo às 23:59',
              style: TextStyle(color: Color(0xFF4B5563), fontSize: 10)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ConfirmarSaqueScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A56DB),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Sacar', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

}
