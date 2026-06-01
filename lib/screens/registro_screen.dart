import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cadastro_aprovacao_screen.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _confirmarSenhaCtrl = TextEditingController();
  bool _senhaVisivel = false;
  bool _confirmarSenhaVisivel = false;
  bool _carregando = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
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
      debugPrint('[REGISTRO] chamando supabase.auth.signUp...');
      final response = await supabase.auth.signUp(
        email: email,
        password: _senhaCtrl.text,
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

      // ── 2. INSERT entregadores — best-effort, nunca bloqueia o fluxo ──
      debugPrint('[REGISTRO] inserindo row em entregadores id=${user.id}...');
      try {
        await supabase.from('entregadores').insert({
          'id': user.id,
          'email': email,
          'status': 'inativo',
          'aprovado': false,
          'status_cadastro': 'pendente',
        });
        debugPrint('[REGISTRO] ✅ entregadores row inserida');
      } catch (insertErr) {
        // Row já existe, RLS bloqueou ou qualquer outro erro — conta já foi criada,
        // continua para a tela de aprovação normalmente.
        debugPrint('[REGISTRO] ⚠️ INSERT entregadores falhou (não bloqueia): $insertErr');
      }

      // ── 3. Navegar para tela de aprovação ─────────────────
      debugPrint('[REGISTRO] navegando para CadastroAprovacaoScreen...');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CadastroAprovacaoScreen()),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: teclado,
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
