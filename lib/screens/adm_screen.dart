import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/mapa_widget.dart';

class AdmScreen extends StatefulWidget {
  const AdmScreen({super.key});
  @override
  State<AdmScreen> createState() => _AdmScreenState();
}

class _AdmScreenState extends State<AdmScreen> {
  final _supabase = Supabase.instance.client;
  List<Marker> _markers = [];

  @override
  void initState() {
    super.initState();
    _escutarMotoboys();
  }

  // Lê lat e lng da tabela entregadores via stream em tempo real
  void _escutarMotoboys() {
    _supabase
        .from('entregadores')
        .stream(primaryKey: ['id'])
        .listen((data) {
      setState(() {
        _markers = data
            .where((e) => e['lat'] != null && e['lng'] != null)
            .map((e) => Marker(
                  point: LatLng(
                    (e['lat'] as num).toDouble(),
                    (e['lng'] as num).toDouble(),
                  ),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.delivery_dining, color: Colors.greenAccent, size: 36),
                ))
            .toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        title: const Text('Painel ADM - Motoboys', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('${_markers.length} online', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
      body: _markers.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delivery_dining, color: Colors.white30, size: 64),
                  SizedBox(height: 12),
                  Text('Nenhum motoboy ativo', style: TextStyle(color: Colors.white70, fontSize: 16)),
                ],
              ),
            )
          : MapaWidget(
              center: _markers.first.point,
              markers: _markers,
              zoom: 13,
            ),
    );
  }
}
