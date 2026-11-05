import 'package:flutter/material.dart';
import '../services/agenda_service.dart';

/// Card "Agendamento" da Home (app 131). Mostra só o que o servidor devolve
/// (agenda_status): % de vagas, vaga do dia, barra de entregas com as duas
/// faixas de bônus e a chegada na base (18:30–19:00; a primeira entrega
/// aceita depois do registro ganha o bônus quando for finalizada).
/// Assina o Realtime só enquanto o card está na tela e o app está aberto.
class AgendaCard extends StatefulWidget {
  const AgendaCard({super.key});
  @override
  State<AgendaCard> createState() => _AgendaCardState();
}

class _AgendaCardState extends State<AgendaCard> with WidgetsBindingObserver {
  final _svc = AgendaService.instance;
  bool _ativo = false;
  bool _enviando = false;

  static const _azul = Color(0xFF1A56DB);
  static const _verde = Color(0xFF10b981);
  static const _cinza = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _svc.addListener(_mudou);
    _ligar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _svc.removeListener(_mudou);
    _desligar();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ligar();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _desligar();
    }
  }

  void _ligar() {
    if (_ativo) return;
    _ativo = true;
    _svc.ativar();
  }

  void _desligar() {
    if (!_ativo) return;
    _ativo = false;
    _svc.desativar();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  String _moeda(dynamic v) {
    final n = (v as num?)?.toDouble() ?? 0;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2).replaceAll('.', ',');
  }

  Future<void> _executar(Future<String> Function() acao) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    final msg = await acao();
    if (!mounted) return;
    setState(() => _enviando = false);
    if (msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _confirmarCancelar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161820),
        title: const Text('Cancelar a vaga de hoje?', style: TextStyle(color: Colors.white)),
        content: const Text('A vaga volta para os outros entregadores.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Manter')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar vaga')),
        ],
      ),
    );
    if (ok == true) _executar(_svc.cancelar);
  }

  @override
  Widget build(BuildContext context) {
    final e = _svc.estado;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Expanded(
              child: Text('Agendamento',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            if (e != null && e['tipo_dia'] != 'semana')
              _selo(e['tipo_dia'] == 'feriado' ? 'Feriado' : 'Fim de semana'),
          ]),
          const SizedBox(height: 10),
          if (e == null)
            Text(_svc.erro ?? 'Carregando…', style: const TextStyle(color: _cinza, fontSize: 12))
          else if (e['reservado'] == true)
            ..._reservado(e)
          else
            ..._semReserva(e),
          if (e != null && _svc.erro != null) ...[
            const SizedBox(height: 6),
            Text(_svc.erro!, style: const TextStyle(color: _cinza, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _selo(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: _azul.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: const TextStyle(color: _azul, fontSize: 10, fontWeight: FontWeight.w600)),
      );

  List<Widget> _semReserva(Map<String, dynamic> e) {
    final pct = (e['vagas_pct'] as num?)?.toInt() ?? 0;
    final cadastroOk = e['cadastro_ok'] == true;
    final esgotado = pct <= 0;
    return [
      Text(esgotado ? 'Vagas esgotadas hoje' : '$pct% das vagas disponíveis',
          style: TextStyle(
              color: esgotado ? const Color(0xFFef4444) : Colors.white,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(
          'Vaga do dia · ${e['inicio_contagem'] ?? '07:00'}–23:59\n'
          '${e['meta1']} entregas +R\$ ${_moeda(e['valor1'])} · ${e['meta2']} entregas +R\$ ${_moeda(e['valor2'])}',
          style: const TextStyle(color: _cinza, fontSize: 11)),
      if (!cadastroOk) ...[
        const SizedBox(height: 6),
        const Text('Seu cadastro precisa estar aprovado.',
            style: TextStyle(color: Color(0xFFf59e0b), fontSize: 11)),
      ],
      const SizedBox(height: 12),
      _botao(esgotado ? 'Esgotado' : 'Confirmar vaga de hoje',
          (esgotado || !cadastroOk || _enviando) ? null : () => _executar(_svc.reservar)),
    ];
  }

  List<Widget> _reservado(Map<String, dynamic> e) {
    final cont = (e['contagem'] as num?)?.toInt() ?? 0;
    final m1 = (e['meta1'] as num?)?.toInt() ?? 15;
    final m2 = (e['meta2'] as num?)?.toInt() ?? 30;
    final pagas = List<String>.from(e['faixas_pagas'] as List? ?? const []);
    return [
      const Text('Vaga de hoje confirmada',
          style: TextStyle(color: _verde, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text('${cont > m2 ? m2 : cont}/$m2 entregas',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      _barra(cont, m1, m2),
      const SizedBox(height: 6),
      Row(children: [
        _faixa('$m1 · +R\$ ${_moeda(e['valor1'])}', pagas.contains('faixa1')),
        const Spacer(),
        _faixa('$m2 · +R\$ ${_moeda(e['valor2'])}', pagas.contains('faixa2')),
      ]),
      ..._chegada(e),
      if (e['pode_cancelar'] == true) ...[
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _enviando ? null : _confirmarCancelar,
          child: const Text('Cancelar vaga',
              style: TextStyle(color: _cinza, fontSize: 11, decoration: TextDecoration.underline)),
        ),
      ],
    ];
  }

  // Barra 0..meta2 com marcas em meta1 e meta2. Sem LayoutBuilder (o card
  // fica dentro de IntrinsicHeight na Home): só FractionallySizedBox/Align.
  Widget _barra(int cont, int m1, int m2) {
    final frac = (cont / m2).clamp(0.0, 1.0);
    final marca1 = (m1 / m2) * 2 - 1; // Alignment.x de -1 a 1
    return SizedBox(
      height: 10,
      child: Stack(children: [
        Container(
            decoration: BoxDecoration(
                color: const Color(0xFF2A2D35), borderRadius: BorderRadius.circular(5))),
        FractionallySizedBox(
          widthFactor: frac,
          child: Container(
              decoration: BoxDecoration(
                  color: cont >= m1 ? _verde : _azul, borderRadius: BorderRadius.circular(5))),
        ),
        Align(
          alignment: Alignment(marca1, 0),
          child: Container(width: 2, height: 10, color: Colors.white54),
        ),
      ]),
    );
  }

  Widget _faixa(String t, bool paga) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (paga) const Icon(Icons.check_circle, color: _verde, size: 14),
        if (paga) const SizedBox(width: 3),
        Text(t,
            style: TextStyle(
                color: paga ? _verde : _cinza, fontSize: 11, fontWeight: paga ? FontWeight.w600 : FontWeight.normal)),
      ]);

  List<Widget> _chegada(Map<String, dynamic> e) {
    final ch = Map<String, dynamic>.from(e['chegada'] as Map? ?? {});
    if (ch['vale_hoje'] != true) return const [];
    final valor = _moeda(ch['valor']);
    final status = ch['status'] as String?;
    Widget linha(String t, Color c, {IconData? icone}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            if (icone != null) Icon(icone, color: c, size: 14),
            if (icone != null) const SizedBox(width: 4),
            Expanded(child: Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600))),
          ]),
        );
    switch (status) {
      case 'registrada':
        return [linha('Chegada registrada · a primeira entrega que você aceitar ganha +R\$ $valor', _verde, icone: Icons.check)];
      case 'paga':
        final n = ch['pedido_numero'];
        return [linha('+R\$ $valor de chegada recebido${n != null ? ' (entrega #$n)' : ''}', _verde, icone: Icons.check_circle)];
      case 'bloqueada':
        return [linha('Chegada bloqueada pelo ADM', const Color(0xFFef4444), icone: Icons.block)];
    }
    if (ch['janela_aberta'] != true) {
      return [linha('Chegada na base: das ${ch['inicio']} às ${ch['fim']} · a primeira entrega depois ganha +R\$ $valor', _cinza)];
    }
    final conf = _svc.chegadaConferida;
    if (conf != null && conf['ok'] == true) {
      return [
        const SizedBox(height: 10),
        Text('A primeira entrega depois da chegada ganha +R\$ $valor',
            style: const TextStyle(color: _cinza, fontSize: 11)),
        const SizedBox(height: 6),
        _botao('Registrar chegada', _enviando ? null : () => _executar(_svc.solicitarChegada), cor: _verde),
      ];
    }
    return [linha((conf?['msg'] as String?) ?? 'Conferindo sua posição…', _cinza)];
  }

  Widget _botao(String t, VoidCallback? onPressed, {Color cor = _azul}) => SizedBox(
        width: double.infinity,
        height: 40,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: cor,
            disabledBackgroundColor: cor.withOpacity(0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(t,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      );
}
