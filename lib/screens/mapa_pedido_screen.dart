import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapaPedidoScreen extends StatelessWidget {
  final String nomeLoja;
  final LatLng localLoja;
  final LatLng localPedido;

  const MapaPedidoScreen({super.key, required this.nomeLoja, required this.localLoja, required this.localPedido});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: Text(nomeLoja, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng((localLoja.latitude + localPedido.latitude) / 2, (localLoja.longitude + localPedido.longitude) / 2),
              initialZoom: 15,
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
              MarkerLayer(markers: [
                Marker(point: localLoja, child: Container(decoration: const BoxDecoration(color: Color(0xFF1A56DB), shape: BoxShape.circle), child: const Icon(Icons.store, color: Colors.white, size: 24))),
                Marker(point: localPedido, child: Container(decoration: const BoxDecoration(color: Color(0xFF1A56DB), shape: BoxShape.circle), child: const Icon(Icons.location_on, color: Colors.white, size: 24))),
              ]),
            ],
          ),
          Positioned(
            left: 16, right: 16, bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Row(children: const [Icon(Icons.store, color: Color(0xFF1A56DB), size: 18), SizedBox(width: 8), Text('Loja', style: TextStyle(color: Colors.white54, fontSize: 12))]),
                const SizedBox(height: 4),
                Row(children: const [Icon(Icons.location_on, color: Color(0xFF1A56DB), size: 18), SizedBox(width: 8), Text('Pedido', style: TextStyle(color: Colors.white54, fontSize: 12))]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: SizedBox(height: 48, child: ElevatedButton(onPressed: () { Navigator.pop(context); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Rejeitar', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))))),
                  const SizedBox(width: 12),
                  Expanded(child: SizedBox(height: 48, child: ElevatedButton(onPressed: () { Navigator.pop(context); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A56DB), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), child: const Text('Aceitar', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))))),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}