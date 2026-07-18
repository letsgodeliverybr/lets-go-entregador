import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cadastro_aprovacao_screen.dart';
import 'permissoes_screen.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _confirmarSenhaCtrl = TextEditingController();
  bool _senhaVisivel = false;
  bool _confirmarSenhaVisivel = false;
  bool _carregando = false;

  final _telefoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {'#': RegExp(r'[0-9]')});
  final _cpfMask = MaskTextInputFormatter(
      mask: '###.###.###-##', filter: {'#': RegExp(r'[0-9]')});

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    _telefoneCtrl.dispose();
    _cpfCtrl.dispose();
    _senhaCtrl.dispose();
    _confirmarSenhaCtrl.dispose();
    super.dispose();
  }

  void _mostrarErro(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFef4444),
      duration: const Duration(seconds: 6),
    ));
  }

  Future<void> _criarConta() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    debugPrint('[REGISTRO] iniciando criação de conta email=$email');

    setState(() => _carregando = true);
    try {
      final supabase = Supabase.instance.client;

      // ── 1. signUp ──────────────────────────────────────────
      // data.origem='entregador' é lido pelo trigger on_auth_user_created_entregadores
      // (ver migrations/fix_entregadores_signup_trigger.sql) pra criar a linha em
      // entregadores no servidor, sem depender da sessão que ainda não existe
      // quando a confirmação de e-mail está habilitada.
      debugPrint('[REGISTRO] chamando supabase.auth.signUp...');
      final response = await supabase.auth.signUp(
        email: email,
        password: _senhaCtrl.text,
        data: {
          'origem': 'entregador',
          'nome': _nomeCtrl.text.trim(),
        },
      );
      debugPrint('[REGISTRO] signUp response: user=${response.user?.id} identities=${response.user?.identities?.length} session=${response.session != null}');

      final user = response.user;
      if (user == null) {
        debugPrint('[REGISTRO] ❌ user == null após signUp');
        _mostrarErro('Não foi possível criar a conta. Tente novamente.');
        return;
      }

      // Quando confirmação de email está OFF e o email já existe,
      // Supabase retorna o usuário mas com identities vazio.
      if (user.identities != null && user.identities!.isEmpty) {
        debugPrint('[REGISTRO] ❌ identities vazio → email já cadastrado');
        _mostrarErro('E-mail já cadastrado. Faça login.');
        return;
      }

      debugPrint('[REGISTRO] ✅ user criado id=${user.id} email=${user.email}');

      // ── 2. Verificar CPF/telefone duplicados ──────────────
      // Só é possível checar contra a tabela depois do signUp (sessão
      // autenticada); a conta em auth.users já existe neste ponto mesmo se
      // o CPF/telefone estiver duplicado (mesma limitação que já existia
      // antes na checagem de CadastroAprovacaoScreen).
      final cpfDigitado = _cpfCtrl.text.trim();
      final cpfSomenteDigitos = cpfDigitado.replaceAll(RegExp(r'[^0-9]'), '');
      try {
        final duplicadoCpf = await supabase
            .from('entregadores')
            .select('id')
            .or('cpf.eq.$cpfDigitado,cpf.eq.$cpfSomenteDigitos')
            .neq('id', user.id)
            .limit(1);
        if (duplicadoCpf.isNotEmpty) {
          debugPrint('[REGISTRO] ❌ CPF já cadastrado por outro entregador');
          _mostrarErro('CPF já cadastrado por outro entregador.');
          return;
        }
      } catch (e) {
        debugPrint('[REGISTRO] ⚠️ erro ao verificar CPF duplicado: $e');
      }

      final telefoneDigitado = _telefoneCtrl.text.trim();
      try {
        final duplicadoTelefone = await supabase
            .from('entregadores')
            .select('id')
            .eq('telefone', telefoneDigitado)
            .neq('id', user.id)
            .limit(1);
        if (duplicadoTelefone.isNotEmpty) {
          debugPrint('[REGISTRO] ❌ telefone já cadastrado por outro entregador');
          _mostrarErro('Telefone já cadastrado por outro entregador.');
          return;
        }
      } catch (e) {
        debugPrint('[REGISTRO] ⚠️ erro ao verificar telefone duplicado: $e');
      }

      // ── 3. Fallback client-side — a linha normalmente já existe aqui, criada
      // pelo trigger on_auth_user_created_entregadores no servidor (passo 1).
      // UPDATE primeiro (nunca sobrescreve colunas fora do payload); só faz
      // INSERT completo se a linha realmente não existir ainda. upsert() puro
      // não serve aqui: o PostgREST exige todas as colunas NOT NULL no payload
      // mesmo quando a linha já existe e a intenção é só atualizar 'nome'.
      debugPrint('[REGISTRO] update em entregadores id=${user.id}...');
      final camposIniciais = {
        'nome': _nomeCtrl.text.trim(),
        'telefone': telefoneDigitado,
        'cpf': cpfDigitado,
      };
      try {
        final atualizados = await supabase
            .from('entregadores')
            .update(camposIniciais)
            .eq('id', user.id)
            .select('id');
        if (atualizados.isEmpty) {
          debugPrint('[REGISTRO] linha não existia, criando via insert completo');
          await supabase.from('entregadores').insert({
            'id': user.id,
            'status': 'inativo',
            'aprovado': false,
            'status_cadastro': 'pendente',
            ...camposIniciais,
          });
        }
        debugPrint('[REGISTRO] ✅ entregadores row ok');
      } catch (insertErr) {
        // Row já existe, RLS bloqueou ou qualquer outro erro — conta já foi criada,
        // continua para a tela de aprovação normalmente.
        debugPrint('[REGISTRO] ⚠️ entregadores falhou (não bloqueia): $insertErr');
      }

      // ── 4. Navegar para permissões, depois aprovação ──────
      // Passa por todas as permissões (localização, notificação, bateria,
      // não perturbe) juntas, numa tela só, antes do resto do cadastro —
      // signUp() já criou sessão, então o cold-start check de main.dart
      // (session == null) nunca pegaria esse caso.
      debugPrint('[REGISTRO] navegando para PermissoesScreen...');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const PermissoesScreen(
            next: CadastroAprovacaoScreen(),
          ),
        ),
      );
      debugPrint('[REGISTRO] ✅ navegação concluída');

    } on AuthException catch (e) {
      debugPrint('[REGISTRO] ❌ AuthException: "${e.message}" statusCode=${e.statusCode}');
      // ignore: avoid_print
      print('[REGISTRO] AuthException toString: ${e.toString()}');
      // ignore: avoid_print
      print('[REGISTRO] AuthException runtimeType: ${e.runtimeType}');
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') ||
          msg.contains('already been registered') ||
          msg.contains('email address is already') ||
          msg.contains('user already') ||
          msg.contains('already exists')) {
        _mostrarErro('Este e-mail já está cadastrado. Faça login.');
      } else if (msg.contains('security purposes') ||
          msg.contains('after 6 seconds') ||
          msg.contains('after 60 seconds')) {
        _mostrarErro('Aguarde alguns segundos e tente novamente.');
      } else if (msg.contains('invalid') && msg.contains('email')) {
        _mostrarErro('E-mail inválido.');
      } else if (msg.contains('weak password') ||
          msg.contains('password') ||
          msg.contains('senha')) {
        _mostrarErro('Senha muito fraca, use pelo menos 6 caracteres.');
      } else {
        _mostrarErro('Erro ao criar conta: ${e.message}');
      }
    } catch (e, st) {
      debugPrint('[REGISTRO] ❌ Erro inesperado: $e');
      debugPrint('[REGISTRO] ❌ tipo: ${e.runtimeType}');
      debugPrint('[REGISTRO] ❌ stacktrace: $st');
      // ignore: avoid_print
      print('[REGISTRO] ERRO toString: ${e.toString()}');
      // ignore: avoid_print
      print('[REGISTRO] ERRO runtimeType: ${e.runtimeType}');
      // ignore: avoid_print
      print('[REGISTRO] ERRO stacktrace: $st');
      _mostrarErro('Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Criar conta',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF3A3A3A)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text('Bem-vindo(a)!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Crie sua conta para começar a entregar',
                  style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 14)),
              const SizedBox(height: 32),
              _label('Nome completo'),
              const SizedBox(height: 8),
              _campo(
                controller: _nomeCtrl,
                hint: 'Seu nome completo',
                icone: Icons.person_outline,
                teclado: TextInputType.name,
                validar: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe seu nome';
                  if (v.trim().length < 3) return 'Nome muito curto';
                  return null;
                },
              ),
              _label('E-mail'),
              const SizedBox(height: 8),
              _campo(
                controller: _emailCtrl,
                hint: 'seu@email.com',
                icone: Icons.mail_outline,
                teclado: TextInputType.emailAddress,
                validar: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o e-mail';
                  if (!v.contains('@')) return 'E-mail inválido';
                  return null;
                },
              ),
              _label('Telefone (WhatsApp)'),
              const SizedBox(height: 8),
              _campo(
                controller: _telefoneCtrl,
                hint: '(00) 00000-0000',
                icone: Icons.phone_outlined,
                teclado: TextInputType.phone,
                formatters: [_telefoneMask],
                validar: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o telefone';
                  if (v.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
                    return 'Telefone inválido';
                  }
                  return null;
                },
              ),
              _label('CPF'),
              const SizedBox(height: 8),
              _campo(
                controller: _cpfCtrl,
                hint: '000.000.000-00',
                icone: Icons.badge_outlined,
                teclado: TextInputType.number,
                formatters: [_cpfMask],
                validar: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe o CPF';
                  if (v.replaceAll(RegExp(r'[^0-9]'), '').length < 11) {
                    return 'CPF inválido';
                  }
                  return null;
                },
              ),
              _label('Senha'),
              const SizedBox(height: 8),
              _campoSenha(
                controller: _senhaCtrl,
                hint: 'Mínimo 6 caracteres',
                visivel: _senhaVisivel,
                onToggle: () =>
                    setState(() => _senhaVisivel = !_senhaVisivel),
                validar: (v) {
                  if (v == null || v.isEmpty) return 'Informe a senha';
                  if (v.length < 6) return 'Mínimo 6 caracteres';
                  return null;
                },
              ),
              _label('Confirmar senha'),
              const SizedBox(height: 8),
              _campoSenha(
                controller: _confirmarSenhaCtrl,
                hint: 'Repita a senha',
                visivel: _confirmarSenhaVisivel,
                onToggle: () => setState(
                    () => _confirmarSenhaVisivel = !_confirmarSenhaVisivel),
                validar: (v) {
                  if (v != _senhaCtrl.text) return 'As senhas não coincidem';
                  return null;
                },
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _carregando ? null : _criarConta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A56DB),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF1A56DB).withOpacity(.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: _carregando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Criar conta',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto,
            style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
      );

  Widget _campo({
    required TextEditingController controller,
    required String hint,
    required IconData icone,
    TextInputType teclado = TextInputType.text,
    String? Function(String?)? validar,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: teclado,
        inputFormatters: formatters,
        style: const TextStyle(color: Colors.white),
        validator: validar,
        decoration: InputDecoration(
          prefixIcon: Icon(icone, color: const Color(0xFFBBBBBB), size: 20),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF777777)),
          filled: true,
          fillColor: const Color(0xFF2D2D2D),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1A56DB))),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFef4444))),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _campoSenha({
    required TextEditingController controller,
    required String hint,
    required bool visivel,
    required VoidCallback onToggle,
    String? Function(String?)? validar,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        obscureText: !visivel,
        style: const TextStyle(color: Colors.white),
        validator: validar,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.lock_outline,
              color: Color(0xFFBBBBBB), size: 20),
          suffixIcon: IconButton(
            icon: Icon(visivel ? Icons.visibility : Icons.visibility_off,
                color: const Color(0xFFBBBBBB), size: 20),
            onPressed: onToggle,
          ),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF777777)),
          filled: true,
          fillColor: const Color(0xFF2D2D2D),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1A56DB))),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFef4444))),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
