import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _senhaVisivel = false;
  bool _carregando = false;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _fazerLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    const Text('Bem vindo(a)!', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('Insira seu e-mail e senha para continuar', style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
                    const SizedBox(height: 28),
                    _buildLabel('E-mail'),
                    const SizedBox(height: 8),
                    _buildCampo(controller: _emailController, hint: 'E-mail de acesso', icone: Icons.mail_outline, teclado: TextInputType.emailAddress,
                      validar: (v) {
                        if (v == null || v.isEmpty) return 'Informe o e-mail';
                        if (!v.contains('@')) return 'E-mail invalido';
                        return null;
                      },
                    ),
                    _buildLabel('Senha'),
                    const SizedBox(height: 8),
                    _buildCampoSenha(),
                    const SizedBox(height: 28),
                    _buildBotaoEntrar(),
                    const SizedBox(height: 16),
                    Center(child: TextButton(onPressed: () {}, child: const Text('Esqueci minha senha', style: TextStyle(color: Color(0xFF3B82F6))))),
                    const Divider(color: Color(0xFF2A2D35), height: 32),
                    Center(child: TextButton(onPressed: () {}, child: const Text('Criar conta', style: TextStyle(color: Color(0xFF3B82F6))))),
                    const SizedBox(height: 8),
                    const Center(child: Text('1.0.0 (1)', style: TextStyle(color: Color(0xFF374151), fontSize: 12))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 60, bottom: 32),
      decoration: const BoxDecoration(
        color: Color(0xFF1A56DB),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(36), bottomRight: Radius.circular(36)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.delivery_dining, color: Color(0xFF1A56DB), size: 28),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lets Go', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text('DELIVERY', style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11, letterSpacing: 3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(texto, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
  );

  Widget _buildCampo({required TextEditingController controller, required String hint, required IconData icone, TextInputType teclado = TextInputType.text, String? Function(String?)? validar}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller, keyboardType: teclado,
        style: const TextStyle(color: Colors.white), validator: validar,
        decoration: InputDecoration(
          prefixIcon: Icon(icone, color: const Color(0xFF4B5563), size: 20),
          hintText: hint, hintStyle: const TextStyle(color: Color(0xFF4B5563)),
          filled: true, fillColor: const Color(0xFF161820),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2A2D35))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2A2D35))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1A56DB))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildCampoSenha() {
    return TextFormField(
      controller: _senhaController, obscureText: !_senhaVisivel,
      style: const TextStyle(color: Colors.white),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Informe a senha';
        if (v.length < 6) return 'Senha muito curta';
        return null;
      },
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF4B5563), size: 20),
        suffixIcon: IconButton(
          icon: Icon(_senhaVisivel ? Icons.visibility : Icons.visibility_off, color: const Color(0xFF4B5563), size: 20),
          onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
        ),
        hintText: 'Senha cadastrada', hintStyle: const TextStyle(color: Color(0xFF4B5563)),
        filled: true, fillColor: const Color(0xFF161820),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2A2D35))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2A2D35))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1A56DB))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildBotaoEntrar() {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: _carregando ? null : _fazerLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A56DB), foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0,
        ),
        child: _carregando
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Entrar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, size: 18),
                ],
              ),
      ),
    );
  }
}
