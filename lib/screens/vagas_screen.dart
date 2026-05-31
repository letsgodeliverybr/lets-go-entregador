import 'package:flutter/material.dart';
import '../widgets/app_bottom_nav_bar.dart';

class VagasScreen extends StatelessWidget {
  const VagasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D0F14),
      bottomNavigationBar: AppBottomNavBar(currentIndex: 3),
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.campaign_outlined, size: 80, color: Color(0xFF374151)),
              SizedBox(height: 24),
              Text(
                'Em breve!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                'Consulte um líder da sua região para saber mais informações.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 15,
                    height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
