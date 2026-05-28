import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'pedidos_aceitos_screen.dart';

enum EtapaEntrega { aceito, chegouLocal, emRota, retornando, aguardandoPagamento, finalizado }

class EntregaScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;
  const EntregaScreen({super.key, required this.pedido});
  @override
  State<EntregaScreen> createState() => _EntregaScreenState();
}

class _EntregaScreenState extends State<EntregaScreen> {
  final _supabase = Supabase.instance.client;
  final _codigoCtrl = TextEditingController();
  EtapaEntrega _etapa = EtapaEntrega.aceito;
  bool _carregando = false;
  String? _erro;

  Position? _posicaoAtual;
  double? _distanciaLojaKm;
  String? _enderecoLoja;
  String? _nomeLoja;

  String get _pedidoId => widget.pedido['id'].toString();

  @override
  void initState() {
    super.initState();
    final status = widget.pedido['status_detalhado'] ?? widget.pedido['status'] ?? '';
    switch (status) {
      case 'aceito':               _etapa = EtapaEntrega.aceito; break;
      case 'no_local':
      case 'chegou_local':         _etapa = EtapaEntrega.chegouLocal; break;
      case 'em_rota':              _etapa = EtapaEntrega.emRota; break;
      case 'retornando':           _etapa = EtapaEntrega.retornando; break;
      case 'aguardando_pagamento': _etapa = EtapaEntrega.aguardandoPagamento; break;
      default:                     _etapa = EtapaEntrega.aceito;
    }
    if (_etapa == EtapaEntrega.retornando || _etapa == EtapaEntrega.aguardandoPagamento) {
      _iniciarPollingPagamento();
    }
    _obterPosicao();
    _buscarInfoLoja();
  }

  Future<void> _buscarInfoLoja() async {
    // 1. Tenta a partir do join já carregado
    final loja = widget.pedido['lojas'];
    if (loja != null) {
      final nome = loja['nome']?.toString() ?? '';
      final end = loja['endereco']?.toString() ?? loja['logradouro']?.toString() ?? '';
      if (nome.isNotEmpty || end.isNotEmpty) {
        if (mounted) setState(() { _nomeLoja = nome.isNotEmpty ? nome : null; _enderecoLoja = end.isNotEmpty ? end : null; });
        if (end.isNotEmpty) return;
      }
    }
    // 2. Tenta campos diretos do pedido
    final endPedido = widget.pedido['endereco_loja']?.toString() ?? widget.pedido['endereco_coleta']?.toString() ?? '';
    if (endPedido.isNotEmpty) {
      if (mounted) setState(() => _enderecoLoja = endPedido);
      return;
    }
    // 3. Busca na tabela lojas usando loja_id
    final lojaId = widget.pedido['loja_id']?.toString();
    if (lojaId == null || lojaId.isEmpty) return;
    try {
      final data = await _supabase.from('lojas').select('nome, endereco, logradouro').eq('id', lojaId).maybeSingle();
      if (data != null && mounted) {
        final nome = data['nome']?.toString() ?? '';
        final end = data['endereco']?.toString() ?? data['logradouro']?.toString() ?? '';
        setState(() {
          if (nome.isNotEmpty) _nomeLoja = nome;
          if (end.isNotEmpty) _enderecoLoja = end;
        });
      }
    } catch (_) {}
  }

  Future<void> _obterPosicao() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() => _posicaoAtual = pos);
      final loja = widget.pedido['lojas'];
      if (loja != null) {
        final lat = (loja['lat'] ?? loja['latitude']) as num?;
        final lng = (loja['lng'] ?? loja['longitude']) as num?;
        if (lat != null && lng != null) {
          final dist = _calcularDistancia(pos.latitude, pos.longitude, lat.toDouble(), lng.toDouble());
          if (mounted) setState(() => _distanciaLojaKm = dist);
        }
      }
    } catch (_) {}
  }

  double _calcularDistancia(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void _iniciarPollingPagamento() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return false;
      try {
        final data = await _supabase
            .from('pedidos')
            .select('pagamento_confirmado, status_detalhado')
            .eq('id', _pedidoId)
            .single();
        if (data['pagamento_confirmado'] == true) {
          if (mounted) setState(() => _etapa = EtapaEntrega.finalizado);
          return false;
        }
      } catch (_) {}
      return mounted && (_etapa == EtapaEntrega.retornando || _etapa == EtapaEntrega.aguardandoPagamento);
    });
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _avancar() async {
    setState(() { _carregando = true; _erro = null; });
    try {
      switch (_etapa) {

        case EtapaEntrega.aceito:
          await _supabase.from('pedidos').update({
            'status': 'no_local',
            'status_detalhado': 'no_local',
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.chegouLocal);
          HapticFeedback.mediumImpact();
          break;

        case EtapaEntrega.chegouLocal:
          await _supabase.from('pedidos').update({
            'status': 'em_rota',
            'status_detalhado': 'em_rota',
            'em_rota_em': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.emRota);
          HapticFeedback.mediumImpact();
          break;

        case EtapaEntrega.emRota:
          final codigo = _codigoCtrl.text.trim();
          if (codigo.length != 4 || int.tryParse(codigo) == null) {
            setState(() { _erro = 'Digite os 4 dígitos do código'; _carregando = false; });
            return;
          }
          await _supabase.from('pedidos').update({
            'status': 'finalizado',
            'status_detalhado': 'finalizado',
            'finalizado_em': DateTime.now().toIso8601String(),
            'codigo_confirmacao': codigo,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.finalizado);
          HapticFeedback.heavyImpact();
          break;

        case EtapaEntrega.finalizado:
          if (mounted) Navigator.pop(context);
          break;

        default: break;
      }
    } catch (e) {
      setState(() => _erro = 'Erro de conexão. Tente novamente.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _marcarRetornando() async {
    setState(() => _carregando = true);
    try {
      await _supabase.from('pedidos').update({
        'status': 'retornando',
        'status_detalhado': 'retornando',
        'retornando_em': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _pedidoId);
      setState(() => _etapa = EtapaEntrega.retornando);
      HapticFeedback.mediumImpact();
      _iniciarPollingPagamento();
    } catch (e) {
      setState(() => _erro = 'Erro ao marcar retorno.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final numero = widget.pedido['numero'] ?? _pedidoId.substring(0, 6);
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        leading: (_etapa != EtapaEntrega.finalizado && _etapa != EtapaEntrega.retornando && _etapa != EtapaEntrega.aguardandoPagamento)
            ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))
            : null,
        title: Text('Pedido #$numero',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildProgresso(),
            const SizedBox(height: 28),
            _buildCardPedido(),
            const SizedBox(height: 28),

            if (_etapa == EtapaEntrega.retornando) ...[
              _buildRetornando(),
            ]
            else if (_etapa == EtapaEntrega.finalizado) ...[
              _buildFinalizado(),
            ]
            else ...[
              // Para emRota: sem ícone/instrução, só campo de código
              if (_etapa != EtapaEntrega.emRota) ...[
                _buildInstrucao(),
                const SizedBox(height: 24),
              ],

              if (_etapa == EtapaEntrega.emRota) ...[
                _buildCampoCodigo(),
                const SizedBox(height: 8),
                if (_erro != null)
                  Text(_erro!, style: const TextStyle(color: Color(0xFFef4444), fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A56DB),
                    side: const BorderSide(color: Color(0xFF1A56DB)),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _carregando ? null : _marcarRetornando,
                  icon: const Icon(Icons.keyboard_return, size: 18),
                  label: const Text('Preciso retornar (maquininha/troco)', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 16),
              ],

              if (_erro != null && _etapa != EtapaEntrega.emRota)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_erro!, style: const TextStyle(color: Color(0xFFef4444), fontSize: 13), textAlign: TextAlign.center),
                ),

              _buildBotao(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgresso() {
    final etapas = ['Aceito', 'No local', 'Em rota', 'Entregue'];
    final atual = _etapa == EtapaEntrega.retornando ? 2 :
                  _etapa == EtapaEntrega.aguardandoPagamento ? 2 :
                  _etapa == EtapaEntrega.finalizado ? 3 : _etapa.index;
    return Row(
      children: List.generate(etapas.length, (i) {
        final feito = i <= atual;
        final isRetornando = _etapa == EtapaEntrega.retornando && i == 2;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: isRetornando ? const Color(0xFFf59e0b) :
                               feito ? const Color(0xFF1A56DB) : const Color(0xFF2a2a3e),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isRetornando
                            ? const Icon(Icons.keyboard_return, color: Colors.white, size: 14)
                            : feito && i < atual
                                ? const Icon(Icons.check, color: Colors.white, size: 14)
                                : Text('${i + 1}',
                                    style: TextStyle(
                                        color: feito ? Colors.white : Colors.grey,
                                        fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(isRetornando ? 'Retorno' : etapas[i],
                        style: TextStyle(
                            color: isRetornando ? const Color(0xFFf59e0b) :
                                   feito ? Colors.white : Colors.grey,
                            fontSize: 10)),
                  ],
                ),
              ),
              if (i < etapas.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 20),
                    color: i < atual ? const Color(0xFF1A56DB) : const Color(0xFF2a2a3e),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildCardPedido() {
    final numero = widget.pedido['numero'] ?? _pedidoId.substring(0, 6);
    if (_etapa == EtapaEntrega.aceito || _etapa == EtapaEntrega.chegouLocal) {
      return _buildCardTela1(numero);
    }
    return _buildCardTela2(numero);
  }

  Widget _buildCardTela1(dynamic numero) {
    final loja = widget.pedido['lojas'];
    final nomeLoja = _nomeLoja ?? loja?['nome']?.toString() ?? widget.pedido['nome_loja']?.toString() ?? 'Loja';
    final enderecoColeta = _enderecoLoja ?? widget.pedido['endereco_loja']?.toString() ?? widget.pedido['endereco_coleta']?.toString() ?? '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.receipt_outlined, color: Colors.white54, size: 16),
            const SizedBox(width: 6),
            Text('Pedido #$numero',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.store, color: Color(0xFF1A56DB), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(nomeLoja,
                style: const TextStyle(color: Colors.white, fontSize: 14))),
          ]),
          const SizedBox(height: 10),
          const Text('Endereço de coleta:',
              style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on, color: Color(0xFF1A56DB), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(enderecoColeta,
                style: const TextStyle(color: Colors.white, fontSize: 14))),
          ]),
          if (_distanciaLojaKm != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.route_outlined, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              Text('${_distanciaLojaKm!.toStringAsFixed(2)} km até a loja',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildCardTela2(dynamic numero) {
    final endereco = widget.pedido['endereco'] ?? '—';
    final complemento = widget.pedido['complemento']?.toString() ?? '';
    final nomeCliente = widget.pedido['cliente'] ?? '—';
    final telefone = widget.pedido['telefone']?.toString() ??
        widget.pedido['telefone_cliente']?.toString() ?? '—';
    final zero800 = widget.pedido['telefone_0800']?.toString() ??
        widget.pedido['zero_oitocentos']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.receipt_outlined, color: Colors.white54, size: 16),
            const SizedBox(width: 6),
            Text('Pedido #$numero',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const Divider(color: Color(0xFF2A2D35), height: 20),
          const Text('ENDEREÇO DE ENTREGA',
              style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.location_on, color: Color(0xFF1A56DB), size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(endereco,
                style: const TextStyle(color: Colors.white, fontSize: 15))),
          ]),
          if (complemento.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.info_outline, color: Colors.white38, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(complemento,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))),
            ]),
          ],
          const Divider(color: Color(0xFF2A2D35), height: 20),
          Row(children: [
            const Icon(Icons.person_outline, color: Colors.white54, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(nomeCliente,
                style: const TextStyle(color: Colors.white, fontSize: 14))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.phone_outlined, color: Colors.white54, size: 16),
            const SizedBox(width: 6),
            Text(telefone, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          if (zero800.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.support_agent_outlined, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              Text(zero800, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildInstrucao() {
    final config = {
      EtapaEntrega.aceito:      (Icons.store_outlined,       'Vá buscar o pedido',      'Dirija-se ao estabelecimento',   const Color(0xFF1A56DB)),
      EtapaEntrega.chegouLocal: (Icons.inventory_2_outlined,  'Chegou no local?',        'Pegue o pedido e confirme',      const Color(0xFF1A56DB)),
    };
    final entry = config[_etapa];
    if (entry == null) return const SizedBox.shrink();
    final (icon, titulo, sub, cor) = entry;
    return Column(children: [
      Icon(icon, color: cor, size: 52),
      const SizedBox(height: 12),
      Text(titulo, style: TextStyle(color: cor, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
    ]);
  }

  Widget _buildCampoCodigo() {
    return Column(children: [
      TextField(
        controller: _codigoCtrl,
        keyboardType: TextInputType.number,
        maxLength: 4,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 16),
        decoration: InputDecoration(
          counterText: '',
          hintText: '0000',
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 36, letterSpacing: 16),
          filled: true, fillColor: const Color(0xFF161820),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1A56DB))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2A2D35))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1A56DB), width: 2)),
        ),
      ),
      const SizedBox(height: 8),
      const Text('Peça ao cliente para mostrar o código', style: TextStyle(color: Colors.white38, fontSize: 12)),
    ]);
  }

  Widget _buildBotao() {
    final config = {
      EtapaEntrega.aceito:      (const Color(0xFF1A56DB), 'Cheguei no local',   Icons.store),
      EtapaEntrega.chegouLocal: (const Color(0xFF1A56DB), 'Saí para entregar',  Icons.moped),
      EtapaEntrega.emRota:      (const Color(0xFF1A56DB), 'Finalizar entrega',  Icons.check_circle),
      EtapaEntrega.finalizado:  (const Color(0xFF1A56DB), 'Voltar para pedidos', Icons.list_alt),
    };
    final (cor, label, icon) = config[_etapa] ?? (const Color(0xFF1A56DB), 'Voltar', Icons.list_alt);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: cor, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: _carregando ? null : _avancar,
        child: _carregando
            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 20), const SizedBox(width: 10),
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
      ),
    );
  }

  Widget _buildRetornando() {
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A56DB10),
          border: Border.all(color: const Color(0xFF1A56DB), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          const Icon(Icons.keyboard_return, color: Color(0xFF1A56DB), size: 52),
          const SizedBox(height: 12),
          const Text('Aguardando confirmação', style: TextStyle(color: Color(0xFF1A56DB), fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Você marcou este pedido como retorno.\nA loja precisa confirmar o pagamento para finalizar.',
              style: TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFF1A56DB), strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Aguardando loja...', style: TextStyle(color: Color(0xFF1A56DB), fontSize: 13)),
          ]),
        ]),
      ),
    ]);
  }

  Widget _buildFinalizado() {
    return Column(children: [
      const Icon(Icons.check_circle, color: Color(0xFF1A56DB), size: 90),
      const SizedBox(height: 16),
      const Text('Entrega finalizada!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Pedido entregue com sucesso', style: TextStyle(color: Colors.white54, fontSize: 14)),
      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A56DB), foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PedidosAceitosScreen()),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.list_alt, size: 20), SizedBox(width: 8),
            Text('Voltar para pedidos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    ]);
  }
}
