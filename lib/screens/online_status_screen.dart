import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/tracking_service.dart';
import 'home_screen.dart';

class OnlineStatusScreen extends StatefulWidget {
  const OnlineStatusScreen({super.key});

  @override
  State<OnlineStatusScreen> createState() => _OnlineStatusScreenState();
}

class _OnlineStatusScreenState extends State<OnlineStatusScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  bool _online = TrackingService.ativo;
  bool _carregando = false;
  Map<String, dynamic>? _entregador;
  int _entregasHoje = 0;
  double _saldoDia = 0;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  String get _uid => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _carregar();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (_uid.isEmpty) return;
    try {
      final e = await _supabase
          .from('entregadores')
          .select()
          .eq('id', _uid)
          .single();

      final hoje = DateTime.now();
      final inicioDia =
          DateTime(hoje.year, hoje.month, hoje.day).toIso8601String();
      final pedidos = await _supabase
          .from('pedidos')
          .select('taxa_entrega')
          .eq('motoboy_id', _uid)
          .eq('status', 'finalizado')
          .gte('finalizado_em', inicioDia);

      final lista = List<Map<String, dynamic>>.from(pedidos);
      final total = lista.fold<double>(
        0,
        (s, p) =>
            s + (double.tryParse(p['taxa_entrega']?.toString() ?? '0') ?? 0),
      );

      if (mounted) {
        setState(() {
          _entregador = e;
          _online = e['disponivel'] == true;
          _entregasHoje = lista.length;
          _saldoDia = total;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_carregando || _uid.isEmpty) return;
    setState(() => _carregando = true);
    try {
      if (_online) {
        await TrackingService.ficarOffline(_uid);
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
        return;
      } else {
        await TrackingService.ficarOnline(_uid);
        await TrackingService.iniciar(_uid);
        if (mounted) setState(() => _online = true);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF161820),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFf59e0b), size: 22),
            SizedBox(width: 8),
            Text('Entrega em andamento',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ]),
          content: Text(msg,
              style:
                  const TextStyle(color: Color(0xFF94a3b8), fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido',
                  style: TextStyle(color: Color(0xFF1A56DB))),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _desde() {
    final raw = _entregador?['updated_at'];
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m > 0 ? 'há ${h}h ${m}min' : 'há ${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final corStatus =
        _online ? const Color(0xFF22c55e) : const Color(0xFF475569);
    final desde = _desde();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        title: const Text('Status',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2D35)),
        ),
      ),
      body: Column(
        children: [
          // ── Conteúdo central ────────────────────────────────────────────
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Indicador animado
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, child) => Transform.scale(
                    scale: _online ? _pulseAnim.value : 1.0,
                    child: child,
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    if (_online)
                      Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              const Color(0xFF22c55e).withOpacity(.10),
                        ),
                      ),
                    Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: corStatus.withOpacity(.12),
                        border: Border.all(color: corStatus, width: 3),
                        boxShadow: _online
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF22c55e)
                                      .withOpacity(.25),
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                )
                              ]
                            : null,
                      ),
                      child: const Center(
                        child: Text('🛵',
                            style: TextStyle(fontSize: 54)),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 28),

                // Status label
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _online ? 'Online' : 'Offline',
                    key: ValueKey(_online),
                    style: TextStyle(
                      color: corStatus,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
                ),

                if (desde.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(desde,
                      style: const TextStyle(
                          color: Color(0xFF64748b), fontSize: 13)),
                ],

                const SizedBox(height: 40),

                // Stats
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: [
                    _stat('Entregas hoje', '$_entregasHoje',
                        const Color(0xFF1A56DB)),
                    const SizedBox(width: 12),
                    _stat(
                      'Saldo do dia',
                      'R\$ ${_saldoDia.toStringAsFixed(2)}',
                      const Color(0xFF10b981),
                    ),
                  ]),
                ),
              ],
            ),
          ),

          // ── Botão toggle ────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _carregando ? null : _toggle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _online
                        ? const Color(0xFF1e293b)
                        : const Color(0xFF22c55e),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF1e293b),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                    side: BorderSide(
                      color: _online
                          ? const Color(0xFFef4444)
                          : const Color(0xFF22c55e),
                      width: 1.5,
                    ),
                  ),
                  child: _carregando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.power_settings_new,
                              size: 20,
                              color: _online
                                  ? const Color(0xFFef4444)
                                  : Colors.white,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _online ? 'Ficar Offline' : 'Ficar Online',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _online
                                    ? const Color(0xFFef4444)
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161820),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2D35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF64748b), fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: cor, fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
