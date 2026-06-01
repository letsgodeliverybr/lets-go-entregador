import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
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

  // Foto / selfie
  XFile? _foto;
  final _picker = ImagePicker();

  // Máscaras
  final _cpfMask = MaskTextInputFormatter(
      mask: '###.###.###-##', filter: {'#': RegExp(r'[0-9]')});
  final _telefoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {'#': RegExp(r'[0-9]')});
  final _cepMask = MaskTextInputFormatter(
      mask: '#####-###', filter: {'#': RegExp(r'[0-9]')});

  // Dados do Veículo
  String _modalVeiculo = 'moto';
  final _placaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  final _corCtrl = TextEditingController();
  final _cnhCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();

  String get _uid => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    debugPrint('[DEBUG] *** CadastroAprovacaoScreen ABRIU *** uid=$_uid');
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
      });
    } catch (_) {}
  }

  Future<void> _selecionarFoto(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1024,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked != null) setState(() => _foto = picked);
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
    debugPrint('[DEBUG] _enviar() chamado');

    final formValido = _formKey.currentState!.validate();
    debugPrint('[DEBUG] form válido: $formValido');
    if (!formValido) return;

    // DEBUG 1: usuário logado
    final user = _supabase.auth.currentUser;
    debugPrint('[DEBUG] currentUser: id=${user?.id} email=${user?.email} isNull=${user == null}');
    debugPrint('[DEBUG] _uid getter: "$_uid"');

    if (_uid.isEmpty) {
      debugPrint('[DEBUG] _uid vazio → abortando envio');
      return;
    }
    // Verificar CPF duplicado antes de salvar
    final cpfDigitado = _cpfCtrl.text.trim();
    if (cpfDigitado.isNotEmpty) {
      try {
        final duplicado = await _supabase
            .from('entregadores')
            .select('id')
            .eq('cpf', cpfDigitado)
            .neq('id', _uid)
            .limit(1);
        if (duplicado.isNotEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CPF já cadastrado por outro entregador'),
              backgroundColor: Color(0xFFef4444),
              duration: Duration(seconds: 5),
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint('[DEBUG] Erro ao verificar CPF duplicado: $e');
      }
    }

    setState(() => _salvando = true);
    try {
      // Upload de foto — não-bloqueante: falha é logada mas não aborta o envio
      String? fotoUrl;
      if (_foto != null) {
        try {
          final bytes = await File(_foto!.path).readAsBytes();
          final path = '$_uid/selfie.jpg';
          await _supabase.storage
              .from('fotos-cadastro')
              .uploadBinary(path, bytes,
                  fileOptions: const FileOptions(
                      contentType: 'image/jpeg', upsert: true));
          fotoUrl = _supabase.storage
              .from('fotos-cadastro')
              .getPublicUrl(path);
          debugPrint('[DEBUG] foto enviada: $fotoUrl');
        } catch (uploadErr) {
          debugPrint('[DEBUG] AVISO upload foto falhou (não bloqueia): $uploadErr');
        }
      } else {
        debugPrint('[DEBUG] nenhuma foto selecionada');
      }

      // DEBUG 2: payload do PATCH
      final payload = {
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
        if (fotoUrl != null) 'foto_url': fotoUrl,
        'status_cadastro': 'em_analise',
        'updated_at': DateTime.now().toIso8601String(),
      };
      debugPrint('[DEBUG] PATCH entregadores WHERE id=$_uid');
      debugPrint('[DEBUG] payload: $payload');

      await _supabase.from('entregadores').update(payload).eq('id', _uid);

      debugPrint('[DEBUG] PATCH concluído com sucesso');
      debugPrint('[DEBUG] navegando para AguardoAprovacaoScreen');

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AguardoAprovacaoScreen()),
      );
      debugPrint('[DEBUG] Navigator.pushReplacement chamado');
    } catch (e, st) {
      // DEBUG 3: erro detalhado do PATCH
      debugPrint('[DEBUG] ❌ ERRO no PATCH: $e');
      debugPrint('[DEBUG] ❌ tipo do erro: ${e.runtimeType}');
      debugPrint('[DEBUG] ❌ stacktrace: $st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar: $e'),
          backgroundColor: const Color(0xFFef4444),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        centerTitle: true,
        elevation: 0,
        title: const Text('Cadastro para Aprovação',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE0E0E0)),
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
              _fotoField(),
              _campo('Nome completo', _nomeCtrl, obrigatorio: true),
              _campo('Telefone', _telefoneCtrl,
                  tipo: TextInputType.phone,
                  hint: '(00) 00000-0000',
                  obrigatorio: true,
                  formatters: [_telefoneMask]),
              _campo('CPF', _cpfCtrl,
                  hint: '000.000.000-00',
                  obrigatorio: true,
                  formatters: [_cpfMask]),
              _campo('RG', _rgCtrl),
              _dataNascimentoField(),
              _campo('CEP', _cepCtrl,
                  tipo: TextInputType.number,
                  hint: '00000-000',
                  formatters: [_cepMask]),
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
              onPressed: () {
                debugPrint('[DEBUG] *** BOTÃO PRESSIONADO *** _salvando=$_salvando');
                if (_salvando) return;
                _enviar();
              },
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

  Widget _fotoField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Foto / Selfie',
            style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .5)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _mostrarOpcoesFoto(),
          child: Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _foto != null
                    ? const Color(0xFF1A56DB)
                    : const Color(0xFFE0E0E0),
                width: _foto != null ? 1.5 : 1,
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: _foto != null
                ? Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(
                        File(_foto!.path),
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _foto = null),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ])
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo_outlined,
                          color: Color(0xFF9E9E9E), size: 36),
                      const SizedBox(height: 10),
                      const Text('Toque para adicionar sua foto',
                          style: TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _btnFoto(Icons.camera_alt_outlined, 'Câmera',
                            () => _selecionarFoto(ImageSource.camera)),
                        const SizedBox(width: 10),
                        _btnFoto(Icons.photo_library_outlined, 'Galeria',
                            () => _selecionarFoto(ImageSource.gallery)),
                      ]),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _btnFoto(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A56DB).withOpacity(.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: const Color(0xFF1A56DB).withOpacity(.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: const Color(0xFF60a5fa), size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF60a5fa),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  void _mostrarOpcoesFoto() {
    if (_foto != null) return; // já tem foto, toca direto no X para remover
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2130),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFF3A3D4A),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined,
                color: Color(0xFF60a5fa)),
            title: const Text('Tirar selfie',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _selecionarFoto(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: Color(0xFF60a5fa)),
            title: const Text('Escolher da galeria',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _selecionarFoto(ImageSource.gallery);
            },
          ),
          const SizedBox(height: 8),
        ]),
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
    List<dynamic>? formatters,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: padding ? 12 : 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .5)),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          keyboardType: tipo,
          inputFormatters: formatters?.cast(),
          style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1A56DB), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
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
                color: Color(0xFF666666),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .5)),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: _selecionarData,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  _dataNascimento ?? 'Selecionar data',
                  style: TextStyle(
                      color: _dataNascimento != null
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFF9E9E9E),
                      fontSize: 14),
                ),
              ),
              const Icon(Icons.calendar_today,
                  color: Color(0xFF9E9E9E), size: 18),
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
                color: Color(0xFF666666),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .5)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: itens.containsKey(value) ? value : itens.keys.first,
          dropdownColor: Colors.white,
          style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
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
}
