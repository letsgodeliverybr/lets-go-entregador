import 'package:flutter/material.dart';
import 'vagas_screen.dart';
import 'login_screen.dart';

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2130),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF2A2D35)),
                    ),
                    child: Row(
                      children: [
                        Text(_online ? 'ONLINE' : 'OFFLINE',
                            style: TextStyle(color: _online ? const Color(0xFF1A56DB) : Colors.white60, fontSize: 12, fontWeight: FontWeight.bold)),
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
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2D35)),
            _buildItem(Icons.inventory_2_outlined, 'ENTREGAS', onTap: () => Navigator.pop(context)),
            _buildItem(Icons.account_balance_wallet_outlined, 'CARTEIRA', trailing: const Icon(Icons.chevron_right, color: Color(0xFF1A56DB))),
            _buildExpandable(Icons.manage_accounts_outlined, 'CONTA', _contaExpanded, () => setState(() => _contaExpanded = !_contaExpanded),
              ['Minha conta', 'Ranking', 'Histórico', 'Notificações']),
            _buildExpandable(Icons.auto_awesome_outlined, 'OPORTUNIDADES', _oportunidadesExpanded, () => setState(() => _oportunidadesExpanded = !_oportunidadesExpanded), ['Vagas de Motoboy Fixo']),
            _buildExpandable(Icons.info_outline, 'SOBRE O APP', _sobreExpanded, () => setState(() => _sobreExpanded = !_sobreExpanded),
              ['Termos de uso', 'Termos de privacidade', 'Log']),
            const Spacer(),
            _buildItem(Icons.power_settings_new, 'LOGOUT', cor: Colors.redAccent, onTap: () {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
            }),
            const SizedBox(height: 8),
            const Text('4.4.7 (4157)', style: TextStyle(color: Color(0xFF374151), fontSize: 12)),
            const SizedBox(height: 16),
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
              onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const VagasScreen())); },
            ),
          )),
      ],
    );
  }
}
