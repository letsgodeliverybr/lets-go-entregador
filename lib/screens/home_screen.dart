import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'confirmar_saque_screen.dart';
import 'drawer_screen.dart';
import 'entregador_home_screen.dart';
import 'cadastro_aprovacao_screen.dart';
import 'aguardo_aprovacao_screen.dart';
import '../services/location_permission_flow.dart';
import '../services/tracking_service.dart';
import '../services/premium_service.dart';
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
  Timer? _retryTimerCanal;
  int _retryContCanal = 0;

  String _nome = '';
  double _saldoDia = 0;
  int _entregasHoje = 0;
  double _saldoSemana = 0;
  bool _refreshing = false;

  // Reorganização da tela offline (2026-09-10): "Meu desempenho hoje" e
  // "Entregador Premium".
  int _aceitasHoje = 0;
  int _recusadasHoje = 0;
  int _entregas90Dias = 0;
  static const _metaPremium = PremiumService.metaEntregas90Dias;
  String? _turnoSelecionado;

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
    _retryTimerCanal?.cancel();
    _canal?.unsubscribe();
    _debounce?.cancel();
    super.dispose();
  }

  void _iniciarRealtime() {
    if (_eid.isEmpty) return;
    _canal = _supabase
        .channel('home_saldo_${_eid}_${DateTime.now().millisecondsSinceEpoch}')
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
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _retryTimerCanal?.cancel();
            _retryTimerCanal = null;
            _retryContCanal = 0;
            debugPrint('[Home] Realtime subscribed OK');
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('[Home] Realtime queda: status=$status — reconectando...');
            _agendarReconexaoCanal();
          }
        });
  }

  void _agendarReconexaoCanal() {
    if (!mounted) return;
    _retryTimerCanal?.cancel();
    final delayS = _retryContCanal < 6 ? (2 << _retryContCanal).clamp(2, 30) : 30;
    _retryContCanal++;
    debugPrint('[Home] Reconexão Realtime em ${delayS}s (tentativa $_retryContCanal)');
    _retryTimerCanal = Timer(Duration(seconds: delayS), () async {
      if (!mounted) return;
      if (_canal != null) {
        await _supabase.removeChannel(_canal!);
        _canal = null;
      }
      _iniciarRealtime();
      // Reload dados ao reconectar — pode ter perdido eventos durante a queda
      _agendarRecarregar();
    });
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
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return;

      // finalizado_em/aceito_em são gravados como hora local (sem offset),
      // então compara com meia-noite local.
      final now = DateTime.now();
      final inicioDia = DateTime(now.year, now.month, now.day).toIso8601String();

      final r = await Future.wait<dynamic>([
        _supabase.from('entregadores').select('nome').eq('id', _eid).single(),
        _supabase
            .from('pedidos')
            .select('taxa_motoboy,gorjeta')
            .eq('motoboy_id', uid)
            .eq('status', 'finalizado')
            .gte('finalizado_em', inicioDia),
        calcularSaldoSemana(),
        // Aceitas hoje: toda aceitação de hoje, independente do status atual
        // (pode já ter sido finalizada, cancelada ou ainda estar em
        // andamento) — por isso usa aceito_em, não finalizado_em. .or() com
        // os 2 campos (mesmo padrão de entregador_home_screen.dart) porque
        // pedidos antigos podem ter só motoboy_id preenchido.
        _supabase
            .from('pedidos')
            .select('id')
            .or('motoboy_id.eq.$uid,entregador_id.eq.$uid')
            .gte('aceito_em', inicioDia),
        // Recusadas hoje: tabela de log pedido_recusas (migrations/
        // add_pedido_recusas.sql) — gravada em aceitar_pedido_screen.dart e
        // rota_disponivel_screen.dart desde 2026-09-10.
        _supabase
            .from('pedido_recusas')
            .select('id')
            .eq('entregador_id', uid)
            .gte('recusado_em', inicioDia),
        // Entregas nos últimos 90 dias corridos — base do progresso pra
        // "Entregador Premium" (850 entregas vira Premium automático).
        // PremiumService (services/premium_service.dart) é a MESMA função
        // usada pelo selo no menu lateral (drawer_screen.dart) — fonte
        // única do cálculo, pra nunca divergir.
        PremiumService.entregas90Dias(uid),
      ]);

      final entregador = r[0] as Map<String, dynamic>;
      final pedidosHoje = List<Map<String, dynamic>>.from(r[1] as List);
      final saldoDisponivel = r[2] as double;
      final aceitasHoje = List<Map<String, dynamic>>.from(r[3] as List).length;
      final recusadasHoje = List<Map<String, dynamic>>.from(r[4] as List).length;
      final entregas90Dias = r[5] as int;

      final totalDia = pedidosHoje.fold<double>(
        0, (s, p) => s + _calcTaxaMotoboy(p),
      );

      debugPrint('[HOME] total_ganhos_hoje=$totalDia qtd_pedidos_hoje=${pedidosHoje.length}');
      debugPrint('[HOME] UID=$uid EID=$_eid match=${uid == _eid} saldoDisponivel=$saldoDisponivel');
      debugPrint('[HOME] aceitasHoje=$aceitasHoje recusadasHoje=$recusadasHoje entregas90Dias=$entregas90Dias');

      if (mounted) {
        setState(() {
          final nomeRaw = entregador['nome']?.toString() ?? '';
          _nome = nomeRaw.contains('@') ? '' : nomeRaw;
          _saldoDia = totalDia;
          _entregasHoje = pedidosHoje.length;
          _saldoSemana = saldoDisponivel;
          _aceitasHoje = aceitasHoje;
          _recusadasHoje = recusadasHoje;
          _entregas90Dias = entregas90Dias;
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

      if (!mounted) return;
      final permOk = await LocationPermissionFlow.garantir(context);
      if (!permOk) {
        if (mounted) setState(() => _carregando = false);
        return;
      }

      // Não escreve disponivel:true direto aqui (bug real encontrado em
      // auditoria, 2026-09-03: essa escrita bypassava por completo o gate
      // de bateria — mesmo com iniciar() lançando Exception logo depois
      // por bateria < 15%, o banco já tinha sido marcado online antes,
      // sem nenhum jeito de reverter no catch abaixo). iniciar() já marca
      // disponivel:true sozinho, DEPOIS de passar pelo gate — única fonte
      // de verdade, mesma usada em entregador_home_screen.dart/online_status_screen.dart.
      await TrackingService.iniciar(_uid);

      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const EntregadorHomeScreen()));
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF161820),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFf59e0b), size: 22),
            const SizedBox(width: 8),
            Text(msg.toLowerCase().contains('bateria') ? 'Bateria baixa' : 'Não foi possível continuar',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ]),
          content: Text(msg,
              style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido', style: TextStyle(color: Color(0xFF1A56DB))),
            ),
          ],
        ),
      );
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
            _buildCardSaldoDisponivel(),
            const SizedBox(height: 16),
            _buildLinhaAgendamentoDesempenho(),
            const SizedBox(height: 16),
            _buildLinhaPremiumMeiSeguro(),
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

    debugPrint('[HOME] _buildCardPrincipal: _entregasHoje=$_entregasHoje status=offline');

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
    debugPrint('[HOME] _buildCardOffline: _entregasHoje=$_entregasHoje status=offline');

    if (_entregasHoje > 0) {
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
                const SizedBox(height: 8),
                Text(
                  'Você já fez $_entregasHoje entrega${_entregasHoje > 1 ? 's' : ''} e ganhou R\$ ${_saldoDia.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Color(0xFF6B7280), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
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

  // Card "Saldo disponível" — largura total (2026-09-10, reorganização da
  // tela offline). Mesmo dado/estilo do card antigo (_buildCardSaldo, na
  // linha deslizável junto com "Demanda na sua região", removido — nunca
  // funcionou), só que agora sozinho, largura total, item 1 da nova ordem.
  Widget _buildCardSaldoDisponivel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
          const SizedBox(height: 8),
          Text(
            'R\$ ${_saldoSemana.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Color(0xFF10b981),
                fontSize: 30,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('Reset domingo 23:59',
              style: TextStyle(color: Color(0xFF4B5563), fontSize: 12)),
          const SizedBox(height: 16),
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
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Sacar',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // Linha deslizável 1: Agendamento + Meu desempenho hoje.
  Widget _buildLinhaAgendamentoDesempenho() {
    return SizedBox(
      height: 224,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCardAgendamento(),
          const SizedBox(width: 12),
          _buildCardDesempenho(),
        ],
      ),
    );
  }

  Widget _buildCardAgendamento() {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Agendamento',
              style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _botaoTurno('almoco', 'Almoço', '10:00–14:00'),
          const SizedBox(height: 8),
          _botaoTurno('jantar', 'Jantar', '18:00–23:59'),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _turnoSelecionado == null ? null : _confirmarTurno,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A56DB),
                disabledBackgroundColor: const Color(0xFF1A56DB).withOpacity(0.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Confirmar turno',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botaoTurno(String valor, String label, String horario) {
    final selecionado = _turnoSelecionado == valor;
    return GestureDetector(
      onTap: () => setState(() => _turnoSelecionado = valor),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selecionado
              ? const Color(0xFF1A56DB).withOpacity(0.15)
              : const Color(0xFF1E2130),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selecionado
                  ? const Color(0xFF1A56DB)
                  : const Color(0xFF2A2D35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: selecionado ? const Color(0xFF1A56DB) : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            Text(horario,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // Confirmação só visual por enquanto — não existe backend de agendamento
  // de turno hoje (investigado: não achei tabela/coluna nenhuma pra isso em
  // nenhum dos dois repos). Fica pra uma decisão futura se precisar
  // persistir de verdade.
  void _confirmarTurno() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Turno confirmado!'),
        backgroundColor: Color(0xFF10b981),
      ),
    );
  }

  Widget _buildCardDesempenho() {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Meu desempenho hoje',
              style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _linhaDesempenho('Aceitas', _aceitasHoje, const Color(0xFF1A56DB)),
          const SizedBox(height: 12),
          _linhaDesempenho('Finalizadas', _entregasHoje, const Color(0xFF10b981)),
          const SizedBox(height: 12),
          _linhaDesempenho('Recusadas', _recusadasHoje, const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  Widget _linhaDesempenho(String label, int valor, Color cor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
        Text('$valor',
            style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  // Linha deslizável 2: Entregador Premium + Seja um Entregador MEI +
  // Seguro do seu veículo.
  Widget _buildLinhaPremiumMeiSeguro() {
    return SizedBox(
      height: 236,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCardPremium(),
          const SizedBox(width: 12),
          _buildCardBeneficio(
            titulo: 'Seja um Entregador MEI',
            texto:
                'Aproveite as vantagens de ser um entregador qualificado como empreendedor.',
            botao: 'Saiba mais',
          ),
          const SizedBox(width: 12),
          _buildCardBeneficio(
            titulo: 'Seguro do seu veículo',
            texto:
                'Proteja seu meio de trabalho. Conheça opções pensadas pra entregadores.',
            botao: 'Conhecer',
          ),
        ],
      ),
    );
  }

  // Progresso automático rumo a "Premium" (850 entregas em 90 dias corridos)
  // — 2026-09-10, investigado: não existe hoje nenhuma tabela/flag de
  // "premium" nem no painel nem no app (o sistema de "clã" é outra coisa,
  // exclusividade de despacho por cidade, sem relação nenhuma). Por
  // enquanto só mostra o progresso calculado a partir de pedidos
  // finalizados — sem criar nenhum status/flag novo, sem lógica de bônus
  // (a pedido do usuário).
  Widget _buildCardPremium() {
    final progresso = (_entregas90Dias / _metaPremium).clamp(0.0, 1.0);
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.workspace_premium, color: Color(0xFFF59E0B), size: 18),
              SizedBox(width: 6),
              Expanded(
                child: Text('Entregador Premium',
                    style: TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
              '850 entregas nos últimos 90 dias corridos vira Premium automaticamente.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, height: 1.35)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 8,
              backgroundColor: const Color(0xFF1E2130),
              color: const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(height: 6),
          Text('$_entregas90Dias/$_metaPremium',
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('Bônus especial após 8 semanas no Premium',
              style: TextStyle(
                  color: Color(0xFF6B7280), fontSize: 11, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildCardBeneficio({
    required String titulo,
    required String texto,
    required String botao,
  }) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(texto,
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, height: 1.35)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1A56DB),
                side: const BorderSide(color: Color(0xFF1A56DB)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(botao, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
