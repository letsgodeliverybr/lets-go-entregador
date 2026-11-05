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
    final reservado = e?['reservado'] == true;
    final valeMais = e != null && e['tipo_dia'] != 'semana';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      // Meia largura ao lado do "Meu Desempenho Hoje": todo texto quebra
      // dentro do card (sem Row com texto solto) e os selos usam Wrap.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Agendamento',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          if (reservado || valeMais) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (reservado) _selo('Vaga confirmada ✓', _verde),
              // Sábado, domingo e feriado: faixas com valor maior.
              if (valeMais) _selo('Hoje vale mais', _azul),
            ]),
          ],
          const SizedBox(height: 10),
          if (e == null)
            Text(_svc.erro ?? 'Carregando…', style: const TextStyle(color: _cinza, fontSize: 12))
          else if (reservado)
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

  Widget _selo(String t, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: cor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  // Faixas em duas linhas, uma abaixo da outra (cabem em meia tela).
  List<Widget> _faixas(Map<String, dynamic> e, List<String> pagas) => [
        _faixa('${e['meta1']} entregas', '+R\$ ${_moeda(e['valor1'])}', pagas.contains('faixa1')),
        const SizedBox(height: 4),
        _faixa('${e['meta2']} entregas', '+R\$ ${_moeda(e['valor2'])}', pagas.contains('faixa2')),
      ];

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
      Text('Vaga do dia · ${e['inicio_contagem'] ?? '07:00'}–23:59',
          style: const TextStyle(color: _cinza, fontSize: 11)),
      const SizedBox(height: 8),
      ..._faixas(e, const []),
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
      Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '${cont > m2 ? m2 : cont}',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.0)),
          TextSpan(
              text: ' de $m2 entregas',
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 8),
      _barra(cont, m1, m2),
      const SizedBox(height: 8),
      ..._faixas(e, pagas),
      ..._chegada(e),
      if (e['pode_cancelar'] == true) ...[
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _enviando ? null : _confirmarCancelar,
          child: const Text('Cancelar vaga',
              style: TextStyle(color: _cinza, fontSize: 11, decoration: TextDecoration.underline)),
        ),
      ],
    ];
  }

  // Barra 0..meta2 com marca na meta1. Sem LayoutBuilder (o card fica
  // dentro de IntrinsicHeight na Home): só FractionallySizedBox/Align.
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
          child: Container(width: 2, height: 10, color: Colors.white70),
        ),
      ]),
    );
  }

  Widget _faixa(String meta, String valor, bool paga) => Row(children: [
        Icon(paga ? Icons.check_circle : Icons.radio_button_unchecked,
            color: paga ? _verde : _cinza, size: 14),
        const SizedBox(width: 5),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$meta '),
              TextSpan(text: valor, style: TextStyle(color: paga ? _verde : Colors.white, fontWeight: FontWeight.w700)),
            ]),
            style: TextStyle(color: paga ? _verde : Colors.white70, fontSize: 12),
          ),
        ),
      ]);

  // Bloco "+R$ 10 de chegada", separado por uma linha fina.
  List<Widget> _chegada(Map<String, dynamic> e) {
    final ch = Map<String, dynamic>.from(e['chegada'] as Map? ?? {});
    if (ch['vale_hoje'] != true) return const [];
    final valor = _moeda(ch['valor']);
    final status = ch['status'] as String?;
    Widget texto(String t, {Color cor = Colors.white70, IconData? icone, FontWeight peso = FontWeight.normal}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icone != null) Padding(padding: const EdgeInsets.only(top: 1, right: 4), child: Icon(icone, color: cor, size: 14)),
            Expanded(child: Text(t, style: TextStyle(color: cor, fontSize: 11, fontWeight: peso))),
          ],
        );
    final corpo = <Widget>[];
    switch (status) {
      case 'registrada':
        corpo.add(texto('Chegada registrada. A 1ª entrega que você aceitar leva +R\$ $valor.', cor: _verde, icone: Icons.check));
        break;
      case 'paga':
        final n = ch['pedido_numero'];
        corpo.add(texto('+R\$ $valor de chegada recebido${n != null ? ' (entrega #$n)' : ''}.', cor: _verde, icone: Icons.check_circle));
        break;
      case 'bloqueada':
        corpo.add(texto('Chegada bloqueada pelo ADM.', cor: const Color(0xFFef4444), icone: Icons.block));
        break;
      default:
        if (ch['janela_aberta'] != true) {
          corpo.add(texto('Chegue na base entre ${ch['inicio']} e ${ch['fim']}. A 1ª entrega depois leva +R\$ $valor.'));
        } else {
          // Nome da base vem do painel: a base onde ele está (conferida
          // pelo servidor) ou, sem isso, as bases ativas cadastradas.
          final conf = _svc.chegadaConferida;
          final nomes = _svc.basesNomes;
          final base = (conf?['ok'] == true && conf?['base'] != null)
              ? conf!['base'].toString()
              : (nomes.isEmpty ? 'base' : nomes.join(' ou '));
          corpo.add(texto('Chegou na $base? Toque em Registrar chegada.', cor: Colors.white, peso: FontWeight.w600));
          if (conf != null && conf['ok'] == true) {
            corpo
              ..add(const SizedBox(height: 8))
              ..add(_botao('Registrar chegada', _enviando ? null : () => _executar(_svc.solicitarChegada), cor: _verde));
          } else {
            corpo
              ..add(const SizedBox(height: 4))
              ..add(texto((conf?['msg'] as String?) ?? 'Conferindo sua posição…', cor: _cinza));
          }
        }
    }
    return [
      const SizedBox(height: 10),
      const Divider(color: Color(0xFF2A2D35), height: 1, thickness: 1),
      const SizedBox(height: 8),
      Text('+R\$ $valor de chegada',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      ...corpo,
    ];
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
