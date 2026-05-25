import 'package:flutter/material.dart';

class VagasScreen extends StatelessWidget {
  const VagasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vagas = [
      {'nome': 'CANTO BRASIL PIZZARIA', 'tel': '(16) 99700-9075', 'endereco': 'Centro, R. Gen. Osorio, 987', 'valor': 'R\$ 30,00', 'inicio': '17:30', 'fim': '23:59'},
      {'nome': 'PESTO PIZZA', 'tel': '(16) 98165-3507', 'endereco': 'Centro, R. Rui Barbosa, 602', 'valor': 'R\$ 30,00', 'inicio': '18:00', 'fim': '23:59'},
      {'nome': 'FRANGUZ', 'tel': '(16) 3441-7121', 'endereco': 'Jardim America, Rua Jacomo Tonetto, 71', 'valor': 'R\$ 30,00', 'inicio': '18:30', 'fim': '23:30'},
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text('Vagas de Motoboy Fixo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: vagas.length,
        itemBuilder: (context, i) {
          final v = vagas[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v['nome']! + '  ' + v['tel']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.location_on, color: Color(0xFF1A56DB), size: 14), const SizedBox(width: 4), Expanded(child: Text(v['endereco']!, style: const TextStyle(color: Colors.white, fontSize: 13)))]),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.attach_money, color: Color(0xFF1A56DB), size: 14), const SizedBox(width: 4), Text(v['valor']!, style: const TextStyle(color: Colors.white, fontSize: 13))]),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.access_time, color: Color(0xFF22C55E), size: 14), const SizedBox(width: 4), Text(v['inicio']! + ' - ' + v['fim']!, style: const TextStyle(color: Colors.white, fontSize: 13))]),
                const SizedBox(height: 8),
                TextButton(onPressed: () {}, child: const Text('Visualizar vaga', style: TextStyle(color: Color(0xFF1A56DB), fontWeight: FontWeight.bold))),
              ],
            ),
          );
        },
      ),
    );
  }
}
