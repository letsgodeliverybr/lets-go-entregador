import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'aguardo_aprovacao_screen.dart';

class CadastroAprovacaoScreen extends StatefulWidget {
  const CadastroAprovacaoScreen({super.key});

  @override
  State<CadastroAprovacaoScreen> createState() =>
      _CadastroAprovacaoScreenState();
}

class _CadastroAprovacaoScreenState extends State<CadastroAprovacaoScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  bool _salvando = false;

  // Dados Pessoais
  final _nomeCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _rgCtrl = TextEditingController();
  String? _dataNascimento;
  final _cepCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _logradouroCtrl = TextEditingController();
  final _numeroEndCtrl = TextEditingController();
  final _complementoEndCtrl = TextEditingController();

  // Dados do Veículo
  String _modalVeiculo = 'moto';
  final _placaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  final _corCtrl = TextEditingController();
  final _cnhCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();

  // Dados de Pagamento
  String _tipoPagamento = 'por_tabela';
  final _bancoCtrl = TextEditingController();
  String _tipoChavePix = 'cpf';
  final _chavePixCtrl = TextEditingController();
  bool _maquinaCartao = false;

  String get _uid => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _preencherDados();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _telefoneCtrl.dispose();
    _cpfCtrl.dispose();
    _rgCtrl.dispose();
    _cepCtrl.dispose();
    _bairroCtrl.dispose();
    _logradouroCtrl.dispose();
    _numeroEndCtrl.dispose();
    _complementoEndCtrl.dispose();
    _placaCtrl.dispose();
    _modeloCtrl.dispose();
    _corCtrl.dispose();
    _cnhCtrl.dispose();
    _cnpjCtrl.dispose();
    _bancoCtrl.dispose();
    _chavePixCtrl.dispose();
    super.dispose();
  }

  Future<void> _preencherDados() async {
    if (_uid.isEmpty) return;
    try {
      final e = await _supabase
          .from('entregadores')
          .select()
          .eq('id', _uid)
          .single();
      if (!mounted) return;
      setState(() {
        _nomeCtrl.text = e['nome'] ?? '';
        _telefoneCtrl.text = e['telefone'] ?? '';
        _cpfCtrl.text = e['cpf'] ?? '';
        _rgCtrl.text = e['rg'] ?? '';
        _dataNascimento = e['data_nascimento']?.toString();
        _cepCtrl.text = e['cep'] ?? '';
        _bairroCtrl.text = e['bairro'] ?? '';
        _logradouroCtrl.text = e['logradouro'] ?? '';
        _numeroEndCtrl.text = e['numero_endereco'] ?? '';
        _complementoEndCtrl.text = e['complemento_end'] ?? '';
        _modalVeiculo = e['modal_veiculo'] ?? 'moto';
        _placaCtrl.text = e['placa_veiculo'] ?? '';
        _modeloCtrl.text = e['modelo_veiculo'] ?? '';
        _corCtrl.text = e['cor_veiculo'] ?? '';
        _cnhCtrl.text = e['cnh'] ?? '';
        _cnpjCtrl.text = e['cnpj'] ?? '';
        _tipoPagamento = e['tipo_pagamento'] ?? 'por_tabela';
        _bancoCtrl.text = e['banco'] ?? '';
        _tipoChavePix = e['tipo_chave_pix'] ?? 'cpf';
        _chavePixCtrl.text = e['chave_pix'] ?? '';
        _maquinaCartao = e['maquina_cartao'] == true;
      });
    } catch (_) {}
  }

  Future<void> _selecionarData() async {
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

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_uid.isEmpty) return;
    setState(() => _salvando = true);
    try {
      await _supabase.from('entregadores').update({
        'nome': _nomeCtrl.text.trim(),
        'telefone': _telefoneCtrl.text.trim(),
        'cpf': _cpfCtrl.text.trim(),
        'rg': _rgCtrl.text.trim(),
        'data_nascimento': _dataNascimento,
        'cep': _cepCtrl.text.trim(),
        'bairro': _bairroCtrl.text.trim(),
        'logradouro': _logradouroCtrl.text.trim(),
        'numero_endereco': _numeroEndCtrl.text.trim(),
        'complemento_end': _complementoEndCtrl.text.trim(),
        'modal_veiculo': _modalVeiculo,
        'placa_veiculo': _placaCtrl.text.trim(),
        'modelo_veiculo': _modeloCtrl.text.trim(),
        'cor_veiculo': _corCtrl.text.trim(),
        'cnh': _cnhCtrl.text.trim(),
        'cnpj': _cnpjCtrl.text.trim(),
        'tipo_pagamento': _tipoPagamento,
        'banco': _bancoCtrl.text.trim(),
        'tipo_chave_pix': _tipoChavePix,
        'chave_pix': _chavePixCtrl.text.trim(),
        'maquina_cartao': _maquinaCartao,
        'status_cadastro': 'em_analise',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _uid);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AguardoAprovacaoScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar: $e'),
          backgroundColor: const Color(0xFFef4444),
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        title: const Text('Cadastro para Aprovação',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2D35)),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secao('👤 Dados Pessoais'),
              _campo('Nome completo', _nomeCtrl, obrigatorio: true),
              _campo('Telefone', _telefoneCtrl,
                  tipo: TextInputType.phone, hint: '(16) 99999-9999'),
              _campo('CPF', _cpfCtrl, hint: '000.000.000-00'),
              _campo('RG', _rgCtrl),
              _dataNascimentoField(),
              _campo('CEP', _cepCtrl,
                  tipo: TextInputType.number, hint: '00000-000'),
              _campo('Bairro', _bairroCtrl),
              _campo('Logradouro', _logradouroCtrl, hint: 'Rua, Av...'),
              Row(children: [
                Expanded(
                    flex: 2,
                    child: _campo('Número', _numeroEndCtrl,
                        tipo: TextInputType.number, padding: false)),
                const SizedBox(width: 12),
                Expanded(
                    flex: 3,
                    child: _campo('Complemento', _complementoEndCtrl,
                        hint: 'Apto, Bloco...', padding: false)),
              ]),
              const SizedBox(height: 4),

              _secao('🛵 Dados do Veículo'),
              _dropdown(
                label: 'Modal do Veículo',
                value: _modalVeiculo,
                itens: const {
                  'moto': 'Moto',
                  'carro': 'Carro',
                  'bicicleta': 'Bicicleta',
                  'van': 'Van',
                },
                onChanged: (v) => setState(() => _modalVeiculo = v!),
              ),
              _campo('Placa', _placaCtrl, hint: 'ABC-1234'),
              _campo('Modelo', _modeloCtrl, hint: 'Honda CG 160...'),
              _campo('Cor', _corCtrl, hint: 'Preta'),
              _campo('CNH', _cnhCtrl),
              _campo('CNPJ', _cnpjCtrl, hint: '00.000.000/0000-00'),

              _secao('💰 Dados de Pagamento'),
              _dropdown(
                label: 'Tipo de pagamento',
                value: _tipoPagamento,
                itens: const {
                  'por_tabela': 'Por Tabela',
                  'percentual': 'Percentual',
                  'fixo': 'Fixo',
                },
                onChanged: (v) => setState(() => _tipoPagamento = v!),
              ),
              _campo('Banco', _bancoCtrl, hint: 'Nubank, Bradesco...'),
              _dropdown(
                label: 'Tipo de chave PIX',
                value: _tipoChavePix,
                itens: const {
                  'cpf': 'CPF',
                  'cnpj': 'CNPJ',
                  'email': 'E-mail',
                  'telefone': 'Telefone',
                  'aleatoria': 'Aleatória',
                },
                onChanged: (v) => setState(() => _tipoChavePix = v!),
              ),
              _campo('Chave PIX', _chavePixCtrl),
              _checkboxMaquina(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _salvando ? null : _enviar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A56DB),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF1A56DB).withOpacity(.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _salvando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('Enviar para Análise',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _secao(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo,
            style: const TextStyle(
                color: Color(0xFF1A56DB),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 6),
        Container(height: 1, color: const Color(0xFF2A2D35)),
      ]),
    );
  }

  Widget _campo(
    String label,
    TextEditingController ctrl, {
    TextInputType tipo = TextInputType.text,
    String? hint,
    bool obrigatorio = false,
    bool padding = true,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: padding ? 12 : 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF64748b),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .5)),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          keyboardType: tipo,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF161820),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2A2D35)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2A2D35)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF1A56DB), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFef4444)),
            ),
          ),
          validator: obrigatorio
              ? (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null
              : null,
        ),
      ]),
    );
  }

  Widget _dataNascimentoField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Data de nascimento',
            style: TextStyle(
                color: Color(0xFF64748b),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .5)),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: _selecionarData,
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF161820),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2A2D35)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  _dataNascimento ?? 'Selecionar data',
                  style: TextStyle(
                      color: _dataNascimento != null
                          ? Colors.white
                          : const Color(0xFF475569),
                      fontSize: 14),
                ),
              ),
              const Icon(Icons.calendar_today,
                  color: Color(0xFF475569), size: 18),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required Map<String, String> itens,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF64748b),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .5)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: itens.containsKey(value) ? value : itens.keys.first,
          dropdownColor: const Color(0xFF1E2130),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF161820),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2A2D35)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2A2D35)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF1A56DB), width: 1.5),
            ),
          ),
          items: itens.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ]),
    );
  }

  Widget _checkboxMaquina() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _maquinaCartao = !_maquinaCartao),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF161820),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _maquinaCartao
                  ? const Color(0xFF1A56DB)
                  : const Color(0xFF2A2D35),
            ),
          ),
          child: Row(children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _maquinaCartao,
                onChanged: (v) => setState(() => _maquinaCartao = v!),
                activeColor: const Color(0xFF1A56DB),
                side: const BorderSide(color: Color(0xFF475569)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Possuo máquina de cartão',
                style: TextStyle(color: Colors.white, fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}
