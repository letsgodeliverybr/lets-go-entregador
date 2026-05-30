import 'package:flutter/material.dart';
import 'vagas_screen.dart';
import 'login_screen.dart';
import 'extrato_screen.dart';
import 'historico_saques_screen.dart';

class DrawerScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  const DrawerScreen({super.key, this.onLogout});
  @override
  State<DrawerScreen> createState() => _DrawerScreenState();
}

class _DrawerScreenState extends State<DrawerScreen> {
  bool _contaExpanded = false;
  bool _sobreExpanded = false;
  bool _oportunidadesExpanded = false;
  bool _carteiraExpanded = false;

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
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Color(0xFF1A56DB),
                    child: Icon(Icons.person, color: Colors.white, size: 32),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gabriel Eliziario', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('ID: #00482', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12, fontWeight: FontWeight.w400)),
                      ],
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
                  _buildExpandable(
                    Icons.account_balance_wallet_outlined, 'CARTEIRA', _carteiraExpanded,
                    () => setState(() => _carteiraExpanded = !_carteiraExpanded),
                    [], // subitens customizados abaixo
                    customItems: [
                      _buildSubItem('Extrato', () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ExtratoScreen())); }),
                      _buildSubItem('Histórico de Saques', () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoricoSaquesScreen())); }),
                    ],
                  ),
                  _buildExpandable(Icons.manage_accounts_outlined, 'CONTA', _contaExpanded,
                    () => setState(() => _contaExpanded = !_contaExpanded),
                    ['Minha conta', 'Ranking', 'Notificações']),
                  _buildExpandable(Icons.auto_awesome_outlined, 'OPORTUNIDADES', _oportunidadesExpanded,
                    () => setState(() => _oportunidadesExpanded = !_oportunidadesExpanded),
                    ['Promoções de Feriado']),
                  _buildExpandable(Icons.info_outline, 'SOBRE O APP', _sobreExpanded,
                    () => setState(() => _sobreExpanded = !_sobreExpanded),
                    ['Termos de uso', 'Termos de privacidade', 'Log']),
                  const SizedBox(height: 24),
                  _buildItem(Icons.power_settings_new, 'LOGOUT', cor: Colors.redAccent, onTap: () {
                    Navigator.pop(context);
                    if (widget.onLogout != null) {
                      widget.onLogout!();
                    } else {
                      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
                    }
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

  static const _styleItem = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static const _styleSubItem = TextStyle(
    color: Color(0xFFCCCCCC),
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  Widget _buildItem(IconData icon, String label, {Color cor = const Color(0xFF1A56DB), Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: cor),
      title: Text(label, style: cor == Colors.redAccent ? _styleItem.copyWith(color: Colors.redAccent) : _styleItem),
      trailing: trailing,
      onTap: onTap ?? () {},
    );
  }

  Widget _buildSubItem(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: ListTile(
        title: Text(label, style: _styleSubItem),
        onTap: onTap,
      ),
    );
  }

  Widget _buildExpandable(IconData icon, String label, bool expanded, VoidCallback onTap, List<String> items, {List<Widget> customItems = const []}) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: const Color(0xFF1A56DB)),
          title: Text(label, style: _styleItem),
          trailing: Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white54),
          onTap: onTap,
        ),
        if (expanded) ...[
          ...customItems,
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(left: 56),
            child: ListTile(
              title: Text(item, style: _styleSubItem),
              onTap: () {
                if (item == 'Vagas de Motoboy Fixo' || item == 'Promoções de Feriado') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const VagasScreen()));
                }
              },
            ),
          )),
        ],
      ],
    );
  }
}
