import 'package:flutter/material.dart';

class CarteiraScreen extends StatefulWidget {
  const CarteiraScreen({super.key});
  @override
  State<CarteiraScreen> createState() => _CarteiraScreenState();
}

class _CarteiraScreenState extends State<CarteiraScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _saldoVisivel = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        title: const Text('Carteira', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1A56DB),
          labelColor: const Color(0xFF1A56DB),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Extrato'),
            Tab(text: 'Histórico'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF161820),
              border: Border(bottom: BorderSide(color: Color(0xFF2A2D35))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Saldo disponível', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(_saldoVisivel ? 'R\$ 0,00' : '••••••',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: Icon(_saldoVisivel ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.white70),
                  onPressed: () => setState(() => _saldoVisivel = !_saldoVisivel),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildExtrato(),
                _buildHistorico(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtrato() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Últimas movimentações', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        _extratoItem(Icons.arrow_downward, 'Entrega #4819', 'Hoje, 14:22', '+ R\$ 7,00', Colors.green),
        _extratoItem(Icons.arrow_downward, 'Entrega #4815', 'Hoje, 13:10', '+ R\$ 12,50', Colors.green),
        _extratoItem(Icons.arrow_upward, 'Saque', 'Ontem, 19:00', '- R\$ 100,00', Colors.redAccent),
        _extratoItem(Icons.arrow_downward, 'Entrega #4810', 'Ontem, 16:44', '+ R\$ 9,00', Colors.green),
        _extratoItem(Icons.star, 'Bônus feriado', '25/05, 08:00', '+ R\$ 25,00', Colors.amber),
        const SizedBox(height: 16),
        const Center(child: Text('Nenhuma outra movimentação.', style: TextStyle(color: Colors.white70, fontSize: 13))),
      ],
    );
  }

  Widget _buildHistorico() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Histórico por semana', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        _historicoItem('Semana 19–25/05', '42 entregas', 'R\$ 543,00'),
        _historicoItem('Semana 12–18/05', '38 entregas', 'R\$ 472,00'),
        _historicoItem('Semana 05–11/05', '35 entregas', 'R\$ 410,50'),
        _historicoItem('Semana 28/04–04/05', '40 entregas', 'R\$ 498,00'),
      ],
    );
  }

  Widget _extratoItem(IconData icon, String title, String date, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 18, backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 16)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
              Text(date, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          )),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _historicoItem(String semana, String entregas, String total) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 18, backgroundColor: Color(0xFF1A56DB),
            child: Icon(Icons.moped, color: Colors.white, size: 16)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(semana, style: const TextStyle(color: Colors.white, fontSize: 14)),
              Text(entregas, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          )),
          Text(total, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}
