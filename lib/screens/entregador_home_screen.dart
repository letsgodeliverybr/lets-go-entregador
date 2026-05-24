import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EntregadorHomeScreen extends StatefulWidget {
  const EntregadorHomeScreen({super.key});
  @override
  State<EntregadorHomeScreen> createState() => _EntregadorHomeScreenState();
}

class _EntregadorHomeScreenState extends State<EntregadorHomeScreen> {
  final _supabase = Supabase.instance.client;
  bool _rastreandoAtivo = false;
  Position? _posicao;
  MapController _mapController = MapController();
  static const _centroRibeirao = LatLng(-21.1775, -47.8103);

  @override
  Widget build(BuildContext context) {
    final pos = _posicao;
    final center = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : _centroRibeirao;

    final markers = pos != null
        ? [Marker(
            point: LatLng(pos.latitude, pos.longitude),
            width: 48,
            height: 48,
            child: Icon(Icons.delivery_dining,
                color: _rastreandoAtivo ? Colors.green : Colors.orange,
                size: 40),
          )]
        : <Marker>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel do Entregador'),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _supabase.auth.signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.letsgo.entregador',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _rastreandoAtivo ? Icons.location_on : Icons.location_off,
                      color: _rastreandoAtivo ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      pos != null
                          ? 'Lat: ${pos.latitude.toStringAsFixed(5)}  Lng: ${pos.longitude.toStringAsFixed(5)}'
                          : 'Aguardando...',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(_rastreandoAtivo ? Icons.stop : Icons.play_arrow),
                    label: Text(_rastreandoAtivo ? 'Parar Rastreamento' : 'Iniciar Rastreamento'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _rastreandoAtivo ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _rastreandoAtivo ? _stopRastreamento : _initRastreamento,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initRastreamento() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return;
    setState(() => _rastreandoAtivo = true);
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _posicao = pos);
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
      _salvarPosicao(pos);
    });
  }

  void _stopRastreamento() {
    setState(() {
      _rastreandoAtivo = false;
    });
  }

  Future<void> _salvarPosicao(Position pos) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _supabase.from('entregadores').upsert({
      'id': user.id,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'disponiVel': true,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
