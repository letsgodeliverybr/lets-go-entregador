import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/home_screen.dart';
import '../screens/entregador_home_screen.dart';
import '../screens/pedidos_disponiveis_screen.dart';
import '../screens/pedidos_aceitos_screen.dart';
import '../screens/vagas_screen.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  const AppBottomNavBar({super.key, required this.currentIndex});

  Future<void> _irParaHome(BuildContext context) async {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) {
      _navReplace(context, const HomeScreen());
      return;
    }
    try {
      final e = await Supabase.instance.client
          .from('entregadores')
          .select('disponivel')
          .eq('id', uid)
          .single();
      if (!context.mounted) return;
      if (e['disponivel'] == true) {
        _navReplace(context, const EntregadorHomeScreen());
      } else {
        _navReplace(context, const HomeScreen());
      }
    } catch (_) {
      if (context.mounted) _navReplace(context, const HomeScreen());
    }
  }

  void _navReplace(BuildContext context, Widget tela) {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => tela,
        transitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161820),
        border: Border(top: BorderSide(color: Color(0xFF2A2D35), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1A56DB),
        unselectedItemColor: Colors.white54,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (index) {
          if (index == currentIndex) return;
          switch (index) {
            case 0:
              _irParaHome(context);
            case 1:
              _navReplace(context, const PedidosDisponiveisScreen());
            case 2:
              _navReplace(context, const PedidosAceitosScreen());
            case 3:
              _navReplace(context, const VagasScreen());
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Disponíveis',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            activeIcon: Icon(Icons.check_circle),
            label: 'Aceitos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.work_outline),
            activeIcon: Icon(Icons.work),
            label: 'Vagas',
          ),
        ],
      ),
    );
  }
}
