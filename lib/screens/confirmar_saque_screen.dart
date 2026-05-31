import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConfirmarSaqueScreen extends StatefulWidget {
  const ConfirmarSaqueScreen({Key? key}) : super(key: key);

  @override
  State<ConfirmarSaqueScreen> createState() => _ConfirmarSaqueScreenState();
}

class _ConfirmarSaqueScreenState extends State<ConfirmarSaqueScreen> {
  final _supabase = Supabase.instance.client;
  final _valorController = TextEditingController();

  bool _carregando = true;
  bool _processando = false;
  bool _sucesso = false;

  double _saldoSemana = 0;
  String? _chavePix;
  String? _tipoChavePix;
  String? _banco;

  static const _tabelaPagamentoId = '7bf1cf41-b3f2-4694-b326-d4e830dae8e1';
  List<Map<String, dynamic>> _faixas = [];

  String get _uid => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _valorController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (_uid.isEmpty) {
      if (mounted) setState(() => _carregando = false);
      return;
    }
    setState(() => _carregando = true);
    try {
      final agora = DateTime.now();
      final inicioSemana = DateTime(
          agora.year, agora.month, agora.day - (agora.weekday - 1));
      final fimSemana =
          inicioSemana.add(const Duration(days: 6, hours: 23, minutes: 59));

      final results = await Future.wait([
        _supabase
            .from('entregadores')
            .select('chave_pix, tipo_chave_pix, banco')
            .eq('id', _uid)
            .single(),
        _supabase
            .from('tabelas_preco_faixas')
            .select('km_ate, valor_sem_retorno, valor_com_retorno')
            .eq('tabela_id', _tabelaPagamentoId)
            .order('km_ate'),
        _supabase
            .from('pedidos')
            .select('distancia_km, com_retorno, gorjeta, taxa_entrega_motoboy')
            .eq('entregador_id', _uid)
            .eq('status', 'finalizado')
            .gte('updated_at', inicioSemana.toIso8601String())
            .lte('updated_at', fimSemana.toIso8601String()),
      ]);

      final entregador = results[0] as Map<String, dynamic>;
      _faixas = List<Map<String, dynamic>>.from(results[1] as List);
      final pedidos = List<Map<String, dynamic>>.from(results[2] as List);

      final totalSemana =
          pedidos.fold<double>(0, (s, p) => s + _calcTaxa(p));

      if (mounted) {
        setState(() {
          _chavePix = entregador['chave_pix']?.toString();
          _tipoChavePix = entregador['tipo_chave_pix']?.toString();
          _banco = entregador['banco']?.toString();
          _saldoSemana = totalSemana;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  double _calcTaxa(Map<String, dynamic> p) {
    final gorjeta = double.tryParse(p['gorjeta']?.toString() ?? '0') ?? 0;
    if (p['taxa_entrega_motoboy'] != null) {
      return (double.tryParse(p['taxa_entrega_motoboy'].toString()) ?? 0) +
          gorjeta;
    }
    if (_faixas.isEmpty) return gorjeta;
    final km = double.tryParse(p['distancia_km']?.toString() ?? '0') ?? 0;
    final temRetorno = p['com_retorno'] == true;
    final faixa = km <= 0
        ? _faixas.first
        : _faixas.firstWhere(
            (f) => km <= (double.tryParse(f['km_ate']?.toString() ?? '0') ?? 0),
            orElse: () => _faixas.last);
    final campo = temRetorno ? 'valor_com_retorno' : 'valor_sem_retorno';
    return (double.tryParse(faixa[campo]?.toString() ?? '0') ?? 0) + gorjeta;
  }

  Future<void> _solicitarSaque() async {
    final valorStr =
        _valorController.text.trim().replaceAll(',', '.');
    final valor = double.tryParse(valorStr);

    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido')),
      );
      return;
    }

    if (valor > _saldoSemana) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Valor maior que o saldo disponível')),
      );
      return;
    }

    setState(() => _processando = true);
    try {
      await _supabase.from('saques').insert({
        'entregador_id': _uid,
        'valor': valor,
        'chave_pix': _chavePix,
        'tipo_chave_pix': _tipoChavePix,
        'banco': _banco,
        'status': 'pendente',
      });
      if (mounted) {
        setState(() {
          _processando = false;
          _sucesso = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao solicitar saque: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Solicitar Saque',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _carregando
          ? const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : _sucesso
              ? _buildSucesso()
              : _buildFormulario(),
    );
  }

  Widget _buildFormulario() {
    final temPix =
        _chavePix != null && _chavePix!.isNotEmpty;
    return SingleChildScrollView(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
                  const Text('Saldo disponível da semana',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                    'R\$ ${_saldoSemana.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Color(0xFF10b981),
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
          ),
          const SizedBox(height: 20),
          const Text('Valor do saque',
              style:
                  TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _valorController,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'[0-9,.]'))
            ],
            style: const TextStyle(
                color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              prefixText: 'R\$ ',
              prefixStyle: const TextStyle(
                  color: Colors.white54, fontSize: 18),
              hintText: '0,00',
              hintStyle:
                  const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: const Color(0xFF161820),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: Color(0xFF2A2D35)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: Color(0xFF2A2D35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: Color(0xFF1A56DB)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (temPix) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161820),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF2A2D35)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Chave PIX de destino',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A56DB)
                              .withOpacity(0.15),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.pix,
                            color: Color(0xFF1A56DB),
                            size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                _chavePix!,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.bold,
                                    fontSize: 14),
                              ),
                              if (_tipoChavePix != null &&
                                  _tipoChavePix!.isNotEmpty)
                                Text(
                                    'Tipo: $_tipoChavePix',
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12)),
                              if (_banco != null &&
                                  _banco!.isNotEmpty)
                                Text(
                                    _banco!,
                                    style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12)),
                            ]),
                      ),
                    ]),
                  ]),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2D1B00),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFD97706)
                        .withOpacity(0.4)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFD97706), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'Cadastre sua chave PIX em Minha Conta',
                      style: TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 13)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1F3A5F),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFF2A5298)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline,
                  color: Color(0xFF6B9FE4), size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                    'O valor será depositado em até 1 dia útil após aprovação.',
                    style: TextStyle(
                        color: Color(0xFF6B9FE4),
                        fontSize: 12)),
              ),
            ]),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed:
                  (!temPix || _processando) ? null : _solicitarSaque,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A56DB),
                disabledBackgroundColor:
                    const Color(0xFF2A2D35),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _processando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5))
                  : const Text('Solicitar Saque',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSucesso() {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A2A),
              shape: BoxShape.circle,
              border: Border.all(
                  color: const Color(0xFF22C55E), width: 2),
            ),
            child: const Icon(Icons.check,
                color: Color(0xFF22C55E), size: 48),
          ),
          const SizedBox(height: 24),
          const Text('Saque solicitado!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
              'Aguarde aprovação.\nO valor será depositado via PIX em até 1 dia útil.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5)),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () =>
                  Navigator.popUntil(context, (r) => r.isFirst),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A56DB),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Voltar para o início',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
