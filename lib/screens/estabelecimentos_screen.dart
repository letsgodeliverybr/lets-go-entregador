import 'package:flutter/material.dart';

class EstabelecimentosScreen extends StatefulWidget {
  const EstabelecimentosScreen({super.key});
  @override
  State<EstabelecimentosScreen> createState() => _EstabelecimentosScreenState();
}

class _EstabelecimentosScreenState extends State<EstabelecimentosScreen> {
  int _tabIndex = 1;
  int _diaIndex = 0;

  final List<String> _dias = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM_'];

  final List<Map<String, dynamic>> _vagas = [
    {'nome': 'CANTO BRASIL PIZZARIA', 'tel': '(16) 99700-9075', 'endereco': 'Centro, R. Gen. Osorio, 987', 'valor': 'R\$ 30,00', 'inicio': '17:30', 'fim': '23:59'},
    {'nome': 'PESTO PIZZA', 'tel': '(16) 98165-3507', 'endereco': 'Centro, R. Rui Barbosa, 602', 'valor': 'R\$ 30,00', 'inicio': '18:00', 'fim': '23:59'},
    {'nome': 'FRANGUZ', 'tel': '(16) 3441-7121', 'endereco': 'Jardim America, Rua Jacomo Tonetto, 71', 'valor': 'R\$ 30,00', 'inicio': '18:30', 'fim': '23:30'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text('Vagas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(child: GestureDetector(onTap: () => setState(() => _tabIndex = 0), child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: _tabIndex == 0 ? const Color(0xFF1A56DB) : Colors.transparent), child: Text('Minha escala', textAlign: TextAlign.center, style: TextStyle(color: _tabIndex == 0 ? Colors.white : Colors.white54, fontWeight: FontWeight.bold))))),
              Expanded(child: GestureDetector(onTap: () => setState(() => _tabIndex = 1), child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: _tabIndex == 1 ? const Color(0xFF1A56DB) : Colors.transparent), child: Text('Vagas disponíveis', textAlign: TextAlign.center, style: TextStyle(color: _tabIndex == 1 ? Colors.white : Colors.white54, fontWeight: FontWeight.bold))))),
            ]),
          ),
          SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: List.generate(_dias.length, (i) => GestureDetector(onTap: () => setState(() => _diaIndex = i), child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: _diaIndex == i ? const Color(0xFF1A56DB) : const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(8)), child: Text(_dias[i], style: TextStyle(color: _diaIndex == i ? Colors.white : Colors.white54, fontWeight: FontWeight.bold))))))),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _vagas.length,
              itemBuilder: (_, i) {
                final v = _vagas[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${v['nome']}  ${v['tel']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.store, color: Colors.white)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [const Icon(Icons.location_on, color: Color(0xFF1A56DB), size: 14), const SizedBox(width: 4), Text(v['endereco'], style: const TextStyle(color: Colors.white, fontSize: 13))]),
                        const SizedBox(height: 4),
                        Row(children: [const Icon(Icons.attach_money, color: Color(0xFF1A56DB), size: 14), const SizedBox(width: 4), Text(v['valor'], style: const TextStyle(color: Colors.white, fontSize: 13))]),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Row(children: [const Icon(Icons.access_time, color: Color(0xFF22C55E), size: 14), const SizedBox(width: 4), Text(v['inicio'], style: const TextStyle(color: Colors.white, fontSize: 13)), const Text(' - ', style: TextStyle(color: Colors.white54)), const Icon(Icons.access_time, color: Colors.red, size: 14), const SizedBox(width: 4), Text(v['fim'], style: const TextStyle(color: Colors.white, fontSize: 13))]),
                    ]),
                    const SizedBox(height: 8),
                    TextButton(onPressed: () {}, child: const Text('Visualizar vaga', style: TextStyle(color: Color(0xFF1A56DB), fontWeight: FontWeight.bold))),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}