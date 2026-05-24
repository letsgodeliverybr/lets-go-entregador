import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapaCalorScreen extends StatefulWidget {
  const MapaCalorScreen({super.key});
  @override
  State<MapaCalorScreen> createState() => _MapaCalorScreenState();
}

class _MapaCalorScreenState extends State<MapaCalorScreen> {
  bool _atualizacaoAtiva = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mapa de calor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_outlined, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(-21.1767, -47.8208),
                initialZoom: 11,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.letsgo.entregador',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: const LatLng(-21.1767, -47.8208),
                      width: 60,
                      height: 60,
                      child: const Icon(Icons.delivery_dining, color: Color(0xFF1A56DB), size: 48),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: const Color(0xFF0D0F14),
            child: Column(
              children: [
                Row(
                  children: [
                    Switch(
                      value: _atualizacaoAtiva,
                      onChanged: (v) => setState(() => _atualizacaoAtiva = v),
                      activeColor: const Color(0xFF1A56DB),
                    ),
                    const SizedBox(width: 8),
                    const Text('Atualizacao ativada',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Desativar a atualizacao do mapa ajuda na economia de dados e bateria',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
