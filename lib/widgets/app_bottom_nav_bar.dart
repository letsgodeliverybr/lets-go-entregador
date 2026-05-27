import 'package:flutter/material.dart';
import '../screens/entregador_home_screen.dart';
import '../screens/pedidos_disponiveis_screen.dart';
import '../screens/pedidos_aceitos_screen.dart';
import '../screens/vagas_screen.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  const AppBottomNavBar({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13131f),
        border: Border(top: BorderSide(color: Color(0xFF2a2a3e), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1A56DB),
        unselectedItemColor: const Color(0xFF6b7280),
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (index) {
          if (index == currentIndex) return;
          Widget destino;
          switch (index) {
            case 0: destino = const EntregadorHomeScreen(); break;
            case 1: destino = const PedidosDisponiveisScreen(); break;
            case 2: destino = const PedidosAceitosScreen(); break;
            case 3: destino = const VagasScreen(); break;
            default: return;
          }
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => destino,
              transitionDuration: Duration.zero,
            ),
          );
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.delivery_dining_outlined), activeIcon: Icon(Icons.delivery_dining), label: 'Disponíveis'),
          BottomNavigationBarItem(icon: Icon(Icons.check_circle_outline), activeIcon: Icon(Icons.check_circle), label: 'Aceitos'),
          BottomNavigationBarItem(icon: Icon(Icons.work_outline), activeIcon: Icon(Icons.work), label: 'Vagas'),
        ],
      ),
    );
  }
}