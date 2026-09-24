import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Fluxo "Esqueci minha senha" (2026-09-24) — o botão já existia em
// login_screen.dart, mas onPressed estava vazio (não fazia nada).
//
// Usa código de 8 dígitos por e-mail, não link mágico: o app não tem
// deep link configurado (sem app_links/uni_links, sem esquema de URL
// próprio no AndroidManifest), então o fluxo padrão do Supabase
// (clicar no link do e-mail → abrir o app) não funcionaria hoje. O
// template do e-mail de recuperação no Supabase Auth foi trocado pra
// incluir {{ .Token }} (código), não só {{ .ConfirmationURL }}.
//
// Etapa 1: e-mail -> resetPasswordForEmail() dispara o e-mail com o
// código. Etapa 2: código + nova senha -> verifyOTP(type: recovery)
// estabelece uma sessão de recuperação, updateUser() troca a senha, e
// então desloga e volta pro login — pra forçar login limpo com a senha
// nova, sem deixar o usuário "meio logado" numa sessão de recovery.
class RecuperarSenhaScreen extends StatefulWidget {
  const RecuperarSenhaScreen({super.key});
  @override
  State<RecuperarSenhaScreen> createState() => _RecuperarSenhaScreenState();
}

class _RecuperarSenhaScreenState extends State<RecuperarSenhaScreen> {
  final _supabase = Supabase.instance.client;
  final _formKeyEmail = GlobalKey<FormState>();
  final _formKeyCodigo = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _codigoController = TextEditingController();
  final _novaSenhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();

  int _etapa = 0; // 0 = pede e-mail, 1 = pede código + nova senha
  bool _carregando = false;
  bool _senhaVisivel = false;
  String _emailEnviado = '';

  @override
  void dispose() {
    _emailController.dispose();
    _codigoController.dispose();
    _novaSenhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  Future<void> _enviarCodigo() async {
    if (!_formKeyEmail.currentState!.validate()) return;
    setState(() => _carregando = true);
    final email = _emailController.text.trim();
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (_) {
      // Não revela se o e-mail existe ou não (mesma prática do próprio
      // Supabase Auth) — segue pra etapa do código de qualquer forma.
    } finally {
      if (mounted) {
        setState(() {
          _carregando = false;
          _emailEnviado = email;
          _etapa = 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Se $email estiver cadastrado, um código de 8 dígitos foi enviado.'),
        ));
      }
    }
  }

  Future<void> _confirmarNovaSenha() async {
    if (!_formKeyCodigo.currentState!.validate()) return;
    if (_novaSenhaController.text != _confirmarSenhaController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('As senhas não coincidem.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _carregando = true);
    try {
      await _supabase.auth.verifyOTP(
        type: OtpType.recovery,
        email: _emailEnviado,
        token: _codigoController.text.trim(),
      );
      await _supabase.auth.updateUser(
        UserAttributes(password: _novaSenhaController.text),
      );
      // Desloga a sessão de recovery — força login limpo com a senha nova,
      // consistente com o resto do app (que sempre passa por
      // signInWithPassword real, ver registrarLoginAgora em login_screen.dart).
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Senha redefinida! Faça login com a senha nova.'), backgroundColor: Colors.green),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Código inválido ou expirado: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Esqueci minha senha', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _etapa == 0 ? _buildEtapaEmail() : _buildEtapaCodigo(),
      ),
    );
  }

  Widget _buildEtapaEmail() {
    return Form(
      key: _formKeyEmail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Informe seu e-mail cadastrado',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Vamos enviar um código de 8 dígitos pra redefinir sua senha.',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
          const SizedBox(height: 24),
          _buildCampo(
            controller: _emailController,
            hint: 'E-mail de acesso',
            icone: Icons.mail_outline,
            teclado: TextInputType.emailAddress,
            validar: (v) {
              if (v == null || v.isEmpty) return 'Informe o e-mail';
              if (!v.contains('@')) return 'E-mail inválido';
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildBotao('Enviar código', _carregando ? null : _enviarCodigo),
        ],
      ),
    );
  }

  Widget _buildEtapaCodigo() {
    return Form(
      key: _formKeyCodigo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Digite o código e a nova senha',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Enviamos um código de 8 dígitos pra $_emailEnviado.',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
          const SizedBox(height: 24),
          _buildCampo(
            controller: _codigoController,
            hint: 'Código de 8 dígitos',
            icone: Icons.pin_outlined,
            teclado: TextInputType.number,
            validar: (v) {
              if (v == null || v.trim().isEmpty) return 'Informe o código';
              if (v.trim().length != 8) return 'O código tem 8 dígitos';
              return null;
            },
          ),
          _buildCampoSenha(_novaSenhaController, 'Nova senha'),
          const SizedBox(height: 16),
          _buildCampoSenha(_confirmarSenhaController, 'Confirmar nova senha'),
          const SizedBox(height: 12),
          _buildBotao('Redefinir senha', _carregando ? null : _confirmarNovaSenha),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _carregando ? null : () => setState(() => _etapa = 0),
              child: const Text('Reenviar código / trocar e-mail', style: TextStyle(color: Color(0xFF3B82F6))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampo({
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
          prefixIcon: Icon(icone, color: const Color(0xFF9E9E9E), size: 20),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          filled: true,
          fillColor: const Color(0xFF2D2D2D),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A56DB))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildCampoSenha(TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: TextFormField(
        controller: controller,
        obscureText: !_senhaVisivel,
        style: const TextStyle(color: Colors.white),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Informe a senha';
          if (v.length < 6) return 'Senha muito curta';
          return null;
        },
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF9E9E9E), size: 20),
          suffixIcon: IconButton(
            icon: Icon(_senhaVisivel ? Icons.visibility : Icons.visibility_off, color: const Color(0xFF9E9E9E), size: 20),
            onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
          ),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          filled: true,
          fillColor: const Color(0xFF2D2D2D),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3A3A3A))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A56DB))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildBotao(String texto, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A56DB),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: _carregando
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
