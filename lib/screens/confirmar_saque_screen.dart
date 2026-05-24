import 'package:flutter/material.dart';

class ConfirmarSaqueScreen extends StatefulWidget {
  final String valor;
  final Map<String, String> conta;

  const ConfirmarSaqueScreen({Key? key, required this.valor, required this.conta}) : super(key: key);

  @override
  State<ConfirmarSaqueScreen> createState() => _ConfirmarSaqueScreenState();
}

class _ConfirmarSaqueScreenState extends State<ConfirmarSaqueScreen> {
  bool _processando = false;
  bool _sucesso = false;

  Future<void> _confirmarSaque() async {
    setState(() => _processando = true);
    await Future.delayed(const Duration(seconds: 2));
    setState(() { _processando = false; _sucesso = true; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text('Carteira', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.notifications_outlined, color: Colors.white), onPressed: () {})],
      ),
      body: _sucesso ? _buildSucesso() : _buildConfirmacao(),
    );
  }

  Widget _buildConfirmacao() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Confirmar saque', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Revise os dados antes de confirmar:', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
          const SizedBox(height: 32),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Valor do saque', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
              const SizedBox(height: 8),
              Text(widget.valor, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Conta de destino', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
              const SizedBox(height: 12),
              Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF3A3A5E), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.account_balance, color: Color(0xFF9CA3AF), size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.conta['banco'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Agência: ${widget.conta['agencia']}  •  Conta: ${widget.conta['conta']}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                  const SizedBox(height: 2),
                  Text('CPF: ${widget.conta['cpf']}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                ])),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1F3A5F), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2A5298))),
            child: Row(children: const [
              Icon(Icons.info_outline, color: Color(0xFF6B9FE4), size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('O valor será depositado em até 1 dia útil na conta selecionada.', style: TextStyle(color: Color(0xFF6B9FE4), fontSize: 13))),
            ]),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _processando ? null : _confirmarSaque,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9500), disabledBackgroundColor: const Color(0xFF2A2D35), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: _processando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : Text('Confirmar saque de ${widget.valor}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSucesso() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 90, height: 90,
            decoration: BoxDecoration(color: const Color(0xFF1A3A2A), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF22C55E), width: 2)),
            child: const Icon(Icons.check, color: Color(0xFF22C55E), size: 48)),
          const SizedBox(height: 24),
          const Text('Saque solicitado!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('Seu saque foi solicitado com sucesso.\nO valor será depositado em até 1 dia útil.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.5)),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9500), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: const Text('Voltar para o início', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
