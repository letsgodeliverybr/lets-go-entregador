import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/pedidos_disponiveis_screen.dart';
import '../screens/pedidos_aceitos_screen.dart';
import '../screens/vagas_screen.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  const AppBottomNavBar({super.key, required this.currentIndex});

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    final screens = [
      const HomeScreen(),
      const PedidosDisponiveisScreen(),
      const PedidosAceitosScreen(),
      const VagasScreen(),
    ];
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screens[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF1A56DB);
    const inactiveColor = Colors.white54;

    final items = <_NavItem>[
      _NavItem(icon: Icons.home, label: 'Home'),
      _NavItem(icon: Icons.delivery_dining, label: 'Disponíveis'),
      _NavItem(icon: Icons.check_circle_outline, label: 'Aceitos'),
      _NavItem(icon: Icons.work_outline, label: 'Vagas'),
    ];

    return Container(
      height: 64,
      color: const Color(0xFF1A1A2E),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final selected = i == currentIndex;
          return GestureDetector(
            onTap: () => _onTap(context, i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    items[i].icon,
                    color: selected ? activeColor : inactiveColor,
                    size: 24,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].label,
                    style: TextStyle(
                      color: selected ? activeColor : inactiveColor,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
