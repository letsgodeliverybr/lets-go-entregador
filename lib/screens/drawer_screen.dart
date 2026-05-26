import 'package:flutter/material.dart';
import 'pedidos_disponiveis_screen.dart';
import 'vagas_screen.dart';
import 'login_screen.dart';
import 'carteira_screen.dart';
import 'pedidos_aceitos_screen.dart';

class DrawerScreen extends StatefulWidget {
  const DrawerScreen({super.key});
  @override
  State<DrawerScreen> createState() => _DrawerScreenState();
}

class _DrawerScreenState extends State<DrawerScreen> {
  bool _online = false;
  bool _contaExpanded = false;
  bool _sobreExpanded = false;
  bool _oportunidadesExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0D0F14),
      child: SafeArea(
        child: Column(
          children: [
            // HEADER COM FOTO DE PERFIL
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              color: const Color(0xFF161820),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFF1A56DB),
                    child: Icon(Icons.person, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Gabriel Eliziario', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2),
                        Text('ID: #00482', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  // TOGGLE ONLINE
                  GestureDetector(
                    onTap: () => setState(() => _online = !_online),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2130),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF2A2D35)),
                      ),
                      child: Row(
                        children: [
                          Text(_online ? 'ONLINE' : 'OFFLINE',
                            style: TextStyle(color: _online ? const Color(0xFF1A56DB) : Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Switch(
                            value: _online,
                            onChanged: (v) => setState(() => _online = v),
                            activeColor: const Color(0xFF1A56DB),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2D35), height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildItem(Icons.inventory_2_outlined, 'ENTREGAS', onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/pedidos'); }),
                  _buildItem(Icons.account_balance_wallet_outlined, 'CARTEIRA',
                    trailing: const Icon(Icons.chevron_right, color: Color(0xFF1A56DB)),
                    onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const CarteiraScreen())); }),
                  _buildExpandable(Icons.manage_accounts_outlined, 'CONTA', _contaExpanded,
                    () => setState(() => _contaExpanded = !_contaExpanded),
                    ['Minha conta', 'Ranking', 'Notificações']),
                  _buildExpandable(Icons.auto_awesome_outlined, 'OPORTUNIDADES', _oportunidadesExpanded,
                    () => setState(() => _oportunidadesExpanded = !_oportunidadesExpanded),
                    ['🎉 Promoções de Feriado']),
                  _buildExpandable(Icons.info_outline, 'SOBRE O APP', _sobreExpanded,
                    () => setState(() => _sobreExpanded = !_sobreExpanded),
                    ['Termos de uso', 'Termos de privacidade', 'Log']),
                  const Spacer(),
                  _buildItem(Icons.power_settings_new, 'LOGOUT', cor: Colors.redAccent, onTap: () {
                    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
                  }),
                  const SizedBox(height: 8),
                  const Text('4.4.7 (4157)', style: TextStyle(color: Color(0xFF374151), fontSize: 12), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(IconData icon, String label, {Color cor = const Color(0xFF1A56DB), Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: cor),
      title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
      trailing: trailing,
      onTap: onTap ?? () {},
    );
  }

  Widget _buildExpandable(IconData icon, String label, bool expanded, VoidCallback onTap, List<String> items) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: const Color(0xFF1A56DB)),
          title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
          trailing: Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white54),
          onTap: onTap,
        ),
        if (expanded)
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(left: 56),
            child: ListTile(
              title: Text(item, style: const TextStyle(color: Colors.white70)),
              onTap: () {
                if (item == 'Vagas de Motoboy Fixo' || item == '🎉 Promoções de Feriado') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const VagasScreen()));
                }
              },
            ),
          )),
      ],
    );
  }
}
