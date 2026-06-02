import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MinhaContaScreen extends StatefulWidget {
  const MinhaContaScreen({super.key});
  @override
  State<MinhaContaScreen> createState() => _MinhaContaScreenState();
}

class _MinhaContaScreenState extends State<MinhaContaScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool _carregando = true;
  bool _salvando = false;
  bool _dadosEditados = false;

  final _nomeCtrl        = TextEditingController();
  final _telefoneCtrl    = TextEditingController();
  final _cpfCtrl         = TextEditingController();
  final _rgCtrl          = TextEditingController();
  final _cepCtrl         = TextEditingController();
  final _bairroCtrl      = TextEditingController();
  final _logradouroCtrl  = TextEditingController();
  final _numeroEndCtrl   = TextEditingController();
  final _chavePIXCtrl    = TextEditingController();
  final _bancoCtrl       = TextEditingController();
  String _tipoPIX        = 'cpf';

  final _telefoneMask = MaskTextInputFormatter(mask: '(##) #####-####', filter: {'#': RegExp(r'[0-9]')});
  final _cpfMask      = MaskTextInputFormatter(mask: '###.###.###-##',   filter: {'#': RegExp(r'[0-9]')});
  final _cepMask      = MaskTextInputFormatter(mask: '#####-###',         filter: {'#': RegExp(r'[0-9]')});

  String get _uid => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose(); _telefoneCtrl.dispose(); _cpfCtrl.dispose();
    _rgCtrl.dispose(); _cepCtrl.dispose(); _bairroCtrl.dispose();
    _logradouroCtrl.dispose(); _numeroEndCtrl.dispose();
    _chavePIXCtrl.dispose(); _bancoCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (_uid.isEmpty) { if (mounted) setState(() => _carregando = false); return; }
    try {
      final e = await _supabase.from('entregadores').select().eq('id', _uid).single();
      if (!mounted) return;
      setState(() {
        _dadosEditados  = e['dados_editados'] == true;
        _nomeCtrl.text       = e['nome'] ?? '';
        _telefoneCtrl.text   = e['telefone'] ?? '';
        _cpfCtrl.text        = e['cpf'] ?? '';
        _rgCtrl.text         = e['rg'] ?? '';
        _cepCtrl.text        = e['cep'] ?? '';
        _bairroCtrl.text     = e['bairro'] ?? '';
        _logradouroCtrl.text = e['logradouro'] ?? '';
        _numeroEndCtrl.text  = e['numero_endereco'] ?? '';
        _chavePIXCtrl.text   = e['chave_pix'] ?? '';
        _bancoCtrl.text      = e['banco'] ?? '';
        _tipoPIX             = e['tipo_chave_pix'] ?? 'cpf';
        _carregando = false;
      });
    } catch (e) {
      debugPrint('[CONTA] erro ao carregar: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      await _supabase.from('entregadores').update({
        'nome':           _nomeCtrl.text.trim(),
        'telefone':       _telefoneCtrl.text.trim(),
        'cpf':            _cpfCtrl.text.trim(),
        'rg':             _rgCtrl.text.trim(),
        'cep':            _cepCtrl.text.trim(),
        'bairro':         _bairroCtrl.text.trim(),
        'logradouro':     _logradouroCtrl.text.trim(),
        'numero_endereco':_numeroEndCtrl.text.trim(),
        'chave_pix':      _chavePIXCtrl.text.trim(),
        'tipo_chave_pix': _tipoPIX,
        'banco':          _bancoCtrl.text.trim(),
        'dados_editados': true,
        'updated_at':     DateTime.now().toIso8601String(),
      }).eq('id', _uid);
      if (!mounted) return;
      setState(() { _dadosEditados = true; _salvando = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados salvos com sucesso!'), backgroundColor: Color(0xFF10b981)),
      );
    } catch (e) {
      debugPrint('[CONTA] erro ao salvar: $e');
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: const Color(0xFFef4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        foregroundColor: Colors.white,
        title: const Text('Minha Conta', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF3A3A3A)),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_dadosEditados) _buildAviso(),
                    _secao('Dados Pessoais'),
                    _campo('Nome completo', _nomeCtrl, obrigatorio: true),
                    _campo('Telefone', _telefoneCtrl, tipo: TextInputType.phone, formatters: [_telefoneMask]),
                    _campo('CPF', _cpfCtrl, formatters: [_cpfMask]),
                    _campo('RG', _rgCtrl),
                    _secao('Endereço'),
                    _campo('CEP', _cepCtrl, tipo: TextInputType.number, formatters: [_cepMask]),
                    _campo('Bairro', _bairroCtrl),
                    _campo('Logradouro', _logradouroCtrl, hint: 'Rua, Av...'),
                    _campo('Número', _numeroEndCtrl, tipo: TextInputType.number),
                    _secao('Dados de Pagamento (PIX)'),
                    _dropdownPIX(),
                    _campo('Chave PIX', _chavePIXCtrl),
                    _campo('Banco', _bancoCtrl, hint: 'Ex: Nubank, Bradesco...'),
                    const SizedBox(height: 32),
                    if (!_dadosEditados)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _salvando ? null : _salvar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A56DB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: _salvando
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                              : const Text('Salvar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAviso() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2D1B00),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD97706).withOpacity(0.5)),
      ),
      child: const Row(children: [
        Icon(Icons.lock_outline, color: Color(0xFFD97706), size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Para alterar seus dados, entre em contato com o líder da sua região.',
            style: TextStyle(color: Color(0xFFD97706), fontSize: 13, height: 1.4),
          ),
        ),
      ]),
    );
  }

  Widget _secao(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: const TextStyle(color: Color(0xFF1A56DB), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 5),
        Container(height: 1, color: const Color(0xFF3A3A3A)),
      ]),
    );
  }

  Widget _campo(String label, TextEditingController ctrl, {
    TextInputType tipo = TextInputType.text,
    String? hint,
    bool obrigatorio = false,
    List<dynamic>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4)),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          keyboardType: tipo,
          readOnly: _dadosEditados,
          inputFormatters: formatters?.cast(),
          style: TextStyle(color: _dadosEditados ? Colors.white60 : Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF777777), fontSize: 14),
            filled: true,
            fillColor: _dadosEditados ? const Color(0xFF252525) : const Color(0xFF2D2D2D),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _dadosEditados ? const Color(0xFF3A3A3A) : const Color(0xFF1A56DB), width: 1.5)),
            disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
          ),
          validator: obrigatorio ? (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null : null,
        ),
      ]),
    );
  }

  Widget _dropdownPIX() {
    final tipos = {'cpf': 'CPF', 'cnpj': 'CNPJ', 'email': 'E-mail', 'telefone': 'Telefone', 'aleatoria': 'Chave Aleatória'};
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tipo de Chave PIX', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: tipos.containsKey(_tipoPIX) ? _tipoPIX : 'cpf',
          onChanged: _dadosEditados ? null : (v) => setState(() => _tipoPIX = v!),
          dropdownColor: const Color(0xFF2D2D2D),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: _dadosEditados ? const Color(0xFF252525) : const Color(0xFF2D2D2D),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1A56DB), width: 1.5)),
          ),
          items: tipos.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        ),
      ]),
    );
  }
}
