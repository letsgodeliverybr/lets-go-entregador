import 'confirmar_saque_screen.dart';
import 'package:flutter/material.dart';

class SelecionarContaScreen extends StatefulWidget {
  final String valor;
  const SelecionarContaScreen({super.key, required this.valor});
  @override
  State<SelecionarContaScreen> createState() => _SelecionarContaScreenState();
}

class _SelecionarContaScreenState extends State<SelecionarContaScreen> {
  int? _contaSelecionada;

  final List<Map<String, String>> _contas = [
    {'banco': '077 BANCO INTER', 'agencia': '0001', 'conta': '7210063-0', 'cpf': '405.707.968-81'},
  ];

  void _confirmarSaque() { Navigator.push(context, MaterialPageRoute(builder: (_) => ConfirmarSaqueScreen(valor: widget.valor, conta: _contas[_contaSelecionada!]))); } void _old() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161820),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Saque solicitado!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('${widget.valor} sera transferido para a conta selecionada em ate 1 dia util.',
            style: const TextStyle(color: Color(0xFF6B7280))),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF1A56DB), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text('Carteira', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.notifications_outlined, color: Colors.white), onPressed: () {})],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text('Para qual conta voce
deseja transferir?',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, height: 1.3)),
            const SizedBox(height: 12),
            const Text('Selecione ou exclua uma conta, ou adicione uma nova conta:',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _contas.length,
                itemBuilder: (_, i) {
                  final conta = _contas[i];
                  final selecionada = _contaSelecionada == i;
                  return GestureDetector(
                    onTap: () => setState(() => _contaSelecionada = i),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161820),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selecionada ? const Color(0xFF1A56DB) : const Color(0xFF2A2D35), width: selecionada ? 2 : 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(conta['banco']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.more_vert, color: Color(0xFF6B7280), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Agencia: ${conta['agencia']}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                                    Text('Conta: ${conta['conta']}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                                    Text('CPF: ${conta['cpf']}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _contaSelecionada == null ? null : _confirmarSaque,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A56DB),
                  disabledBackgroundColor: const Color(0xFF2A2D35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  _contaSelecionada == null ? 'Adicionar nova conta' : 'Confirmar saque de ${widget.valor}',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
