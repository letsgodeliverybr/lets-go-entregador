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
  final _complementoCtrl = TextEditingController();
  final _chavePIXCtrl    = TextEditingController();
  final _bancoCtrl       = TextEditingController();
  String _tipoPIX        = 'cpf';
  String? _dataNascimento;

  // Veículo
  String _modalVeiculo = 'moto';
  final _placaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  final _corCtrl = TextEditingController();
  final _cnhCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();

  // Documentos já enviados (só status, sem exibir a foto)
  bool _temFotoPerfil = false;
  bool _temFotoCnh = false;
  bool _temFotoCrlv = false;
  bool _temFotoComprovante = false;
  bool _temFotoPlaca = false;

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
    _complementoCtrl.dispose();
    _chavePIXCtrl.dispose(); _bancoCtrl.dispose();
    _placaCtrl.dispose(); _modeloCtrl.dispose(); _corCtrl.dispose();
    _cnhCtrl.dispose(); _cnpjCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (_uid.isEmpty) { if (mounted) setState(() => _carregando = false); return; }
    try {
      final e = await _supabase.from('entregadores').select().eq('id', _uid).single();
      if (!mounted) return;
      setState(() {
        _dadosEditados  = e['dados_editados'] == true;
        final nomeRaw = e['nome']?.toString() ?? '';
        _nomeCtrl.text       = nomeRaw.contains('@') ? '' : nomeRaw;
        _telefoneCtrl.text   = e['telefone'] ?? '';
        _cpfCtrl.text        = e['cpf'] ?? '';
        _rgCtrl.text         = e['rg'] ?? '';
        _cepCtrl.text        = e['cep'] ?? '';
        _bairroCtrl.text     = e['bairro'] ?? '';
        _logradouroCtrl.text = e['logradouro'] ?? '';
        _numeroEndCtrl.text  = e['numero_endereco'] ?? '';
        _complementoCtrl.text = e['complemento_end'] ?? '';
        _dataNascimento      = e['data_nascimento']?.toString();
        _modalVeiculo        = e['modal_veiculo'] ?? 'moto';
        _placaCtrl.text      = e['placa_veiculo'] ?? '';
        _modeloCtrl.text     = e['modelo_veiculo'] ?? '';
        _corCtrl.text        = e['cor_veiculo'] ?? '';
        _cnhCtrl.text        = e['cnh'] ?? '';
        _cnpjCtrl.text       = e['cnpj'] ?? '';
        _chavePIXCtrl.text   = e['chave_pix'] ?? '';
        _bancoCtrl.text      = e['banco'] ?? '';
        _tipoPIX             = e['tipo_chave_pix'] ?? 'cpf';
        _temFotoPerfil       = e['foto_perfil'] != null;
        _temFotoCnh          = e['foto_cnh'] != null;
        _temFotoCrlv         = e['foto_crlv'] != null;
        _temFotoComprovante  = e['foto_comprovante_residencia'] != null;
        _temFotoPlaca        = e['foto_placa'] != null;
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
      final cpf = _cpfCtrl.text.trim();
      if (cpf.isNotEmpty) {
        final duplicado = await _supabase
            .from('entregadores')
            .select('id')
            .eq('cpf', cpf)
            .neq('id', _uid)
            .limit(1);
        if (duplicado.isNotEmpty) {
          if (mounted) {
            setState(() => _salvando = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('CPF já cadastrado'),
                backgroundColor: Color(0xFFef4444),
              ),
            );
          }
          return;
        }
      }
      await _supabase.from('entregadores').update({
        'nome':           _nomeCtrl.text.trim(),
        'telefone':       _telefoneCtrl.text.trim(),
        'cpf':            _cpfCtrl.text.trim(),
        'rg':             _rgCtrl.text.trim(),
        'data_nascimento':_dataNascimento,
        'cep':            _cepCtrl.text.trim(),
        'bairro':         _bairroCtrl.text.trim(),
        'logradouro':     _logradouroCtrl.text.trim(),
        'numero_endereco':_numeroEndCtrl.text.trim(),
        'complemento_end':_complementoCtrl.text.trim(),
        'modal_veiculo':  _modalVeiculo,
        'placa_veiculo':  _placaCtrl.text.trim(),
        'modelo_veiculo': _modeloCtrl.text.trim(),
        'cor_veiculo':    _corCtrl.text.trim(),
        'cnh':            _cnhCtrl.text.trim(),
        'cnpj':           _cnpjCtrl.text.trim(),
        'chave_pix':      _chavePIXCtrl.text.trim(),
        'tipo_chave_pix': _tipoPIX,
        'banco':          _bancoCtrl.text.trim(),
        'dados_editados':  true,
        'status_cadastro': 'em_analise',
        'updated_at':      DateTime.now().toIso8601String(),
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
                    _dataNascimentoField(),
                    _secao('Endereço'),
                    _campo('CEP', _cepCtrl, tipo: TextInputType.number, obrigatorio: true, formatters: [_cepMask]),
                    _campo('Bairro', _bairroCtrl, obrigatorio: true),
                    _campo('Logradouro', _logradouroCtrl, hint: 'Rua, Av...', obrigatorio: true),
                    _campo('Número', _numeroEndCtrl, tipo: TextInputType.number, obrigatorio: true),
                    _campo('Complemento', _complementoCtrl, hint: 'Apto, Bloco... (sem apto? escreva "Casa")', obrigatorio: true),
                    _secao('🛵 Dados do Veículo'),
                    _dropdownVeiculo(),
                    _campo('Placa', _placaCtrl, hint: 'ABC-1234', obrigatorio: true),
                    _campo('Modelo', _modeloCtrl, hint: 'Honda CG 160...', obrigatorio: true),
                    _campo('Cor', _corCtrl, hint: 'Preta', obrigatorio: true),
                    _campo('CNH', _cnhCtrl, obrigatorio: true),
                    _campo('CNPJ', _cnpjCtrl, hint: '00.000.000/0000-00'),
                    _secao('Dados de Pagamento (PIX)'),
                    _dropdownPIX(),
                    _campo('Chave PIX', _chavePIXCtrl),
                    _campo('Banco', _bancoCtrl, hint: 'Ex: Nubank, Bradesco...'),
                    _secao('📄 Documentos Enviados'),
                    _statusDocumento('Foto de Perfil', _temFotoPerfil),
                    _statusDocumento('CNH', _temFotoCnh),
                    _statusDocumento('CRLV', _temFotoCrlv),
                    _statusDocumento('Comprovante de Residência', _temFotoComprovante),
                    _statusDocumento('Foto da Placa', _temFotoPlaca),
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

  Future<void> _selecionarData() async {
    if (_dadosEditados) return;
    final now = DateTime.now();
    DateTime initial = now.subtract(const Duration(days: 365 * 25));
    if (_dataNascimento != null) {
      initial = DateTime.tryParse(_dataNascimento!) ?? initial;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1940),
      lastDate: now,
      helpText: 'Data de nascimento',
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF1A56DB),
            onSurface: Colors.white,
            surface: Color(0xFF1E2130),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dataNascimento =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Widget _dataNascimentoField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Data de nascimento',
            style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4)),
        const SizedBox(height: 5),
        FormField<String>(
          initialValue: _dataNascimento,
          validator: (_) => _dataNascimento == null ? 'Obrigatório' : null,
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () async {
                  await _selecionarData();
                  field.didChange(_dataNascimento);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: _dadosEditados ? const Color(0xFF252525) : const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: field.hasError ? const Color(0xFFef4444) : const Color(0xFF3A3A3A)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        _dataNascimento ?? 'Selecionar data',
                        style: TextStyle(color: _dataNascimento != null ? (_dadosEditados ? Colors.white60 : Colors.white) : const Color(0xFF777777), fontSize: 14),
                      ),
                    ),
                    const Icon(Icons.calendar_today, color: Color(0xFFBBBBBB), size: 18),
                  ]),
                ),
              ),
              if (field.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(field.errorText!, style: const TextStyle(color: Color(0xFFef4444), fontSize: 12)),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _dropdownVeiculo() {
    final itens = {'moto': 'Moto', 'carro': 'Carro', 'bicicleta': 'Bicicleta', 'van': 'Van'};
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Modal do Veículo', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: itens.containsKey(_modalVeiculo) ? _modalVeiculo : 'moto',
          onChanged: _dadosEditados ? null : (v) => setState(() => _modalVeiculo = v!),
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
          items: itens.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        ),
      ]),
    );
  }

  // Só o status (enviado ou não) — nunca busca/mostra a imagem em si.
  Widget _statusDocumento(String label, bool enviado) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(enviado ? Icons.check_circle : Icons.radio_button_unchecked,
            color: enviado ? const Color(0xFF16A34A) : const Color(0xFF6B7280), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
        ),
        Text(enviado ? 'Enviado' : 'Não enviado',
            style: TextStyle(
                color: enviado ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
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
