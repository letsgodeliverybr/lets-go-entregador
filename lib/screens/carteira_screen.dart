import 'package:flutter/material.dart';
import 'selecionar_conta_screen.dart';

class CarteiraScreen extends StatefulWidget {
  final double saldo;
  const CarteiraScreen({super.key, this.saldo = 8.19});
  @override
  State<CarteiraScreen> createState() => _CarteiraScreenState();
}

class _CarteiraScreenState extends State<CarteiraScreen> {
  bool _saldoVisivel = true;

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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161820),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2D35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Saldo atual', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _saldoVisivel ? 'R\$ ${widget.saldo.toStringAsFixed(2)}' : 'R\$ ••••',
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(_saldoVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: const Color(0xFF6B7280)),
                        onPressed: () => setState(() => _saldoVisivel = !_saldoVisivel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SelecionarContaScreen(valor: 'R\$ 8,19'))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A56DB),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Sacar saldo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Text('Historico', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.filter_list, color: Colors.white, size: 16),
                  label: const Text('Filtrar', style: TextStyle(color: Colors.white, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2A2D35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text('Nao ha informacoes a serem apresentadas.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
