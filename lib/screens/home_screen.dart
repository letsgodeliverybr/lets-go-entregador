import 'vagas_screen.dart';
import 'pedidos_aceitos_screen.dart';
import 'carteira_screen.dart';
import 'estabelecimentos_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pedidos_disponiveis_screen.dart';
import 'mapa_calor_screen.dart';
import 'drawer_screen.dart';
import 'entregador_home_screen.dart';
import '../services/tracking_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _online = false;
  bool _carregando = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> _toggleOnline(bool value) async {
    if (!value) {
      setState(() => _online = false);
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _carregando = true);
    try {
      await Supabase.instance.client.from('entregadores').update({
        'disponivel': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
      await TrackingService.iniciar(user.id);
    } catch (_) {}
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const EntregadorHomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0D0F14),
      drawer: const DrawerScreen(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Bem vindo!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_outlined, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPerfilRow(),
            const SizedBox(height: 16),
            _buildCardOffline(),
            const SizedBox(height: 16),
            _buildCardsRow(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildPerfilRow() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 28,
          backgroundColor: Color(0xFF1A56DB),
          child: Icon(Icons.person, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Olá, Gabriel Eliziario', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text('Arroteia', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        _buildToggleOffline(),
      ],
    );
  }

  Widget _buildToggleOffline() {
    return GestureDetector(
      onTap: _carregando ? null : () => _toggleOnline(!_online),
      child: Container(
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
            _carregando
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A56DB)))
                : Switch(
                    value: _online,
                    onChanged: _toggleOnline,
                    activeColor: const Color(0xFF1A56DB),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardOffline() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: const Color(0xFF1E2130),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Center(
              child: Icon(Icons.inventory_2_outlined, size: 72, color: Colors.white24),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('Você ainda não faturou hoje',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text('Fique online para receber pedidos!',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _carregando ? null : () => _toggleOnline(!_online),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2130),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF2A2D35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_online ? 'ONLINE' : 'OFFLINE',
                            style: TextStyle(color: _online ? const Color(0xFF1A56DB) : Colors.white60, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        _carregando
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A56DB)))
                            : Switch(
                                value: _online,
                                onChanged: _toggleOnline,
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
        ],
      ),
    );
  }

  Widget _buildCardsRow() {
    return SizedBox(
      height: 180,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCardDemanda(),
          const SizedBox(width: 12),
          _buildCardSaldo(),
        ],
      ),
    );
  }

  Widget _buildCardDemanda() {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Demanda na sua região', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
          const SizedBox(height: 8),
          const Text('No Mapa de Calor você pode ver as áreas da região em que há mais pedidos pra você',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapaCalorScreen())),
              icon: const Icon(Icons.local_fire_department, color: Colors.white),
              label: const Text('Abrir mapa de calor >', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A56DB),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSaldo() {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saldo disponível', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
          const SizedBox(height: 8),
          const Text('R\$ 0,00', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => CarteiraScreen())); },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A56DB),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Sacar', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 64,
      color: const Color(0xFF161820),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(icon: const Icon(Icons.home, color: Color(0xFF1A56DB)), onPressed: () { Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false); }),
          IconButton(icon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF1A56DB)), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const PedidosDisponiveisScreen())); }),
          IconButton(icon: const Icon(Icons.check_circle_outline, color: Colors.white54), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const PedidosAceitosScreen())); }),
          IconButton(icon: const Icon(Icons.work_outline, color: Colors.white54), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const VagasScreen())); }),
        ],
      ),
    );
  }
}
