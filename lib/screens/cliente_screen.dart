import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/mapa_widget.dart';

class ClienteScreen extends StatefulWidget {
  const ClienteScreen({super.key});
  @override
  State<ClienteScreen> createState() => _ClienteScreenState();
}

class _ClienteScreenState extends State<ClienteScreen> {
  final _supabase = Supabase.instance.client;
  List<Marker> _markers = [];
  static const _ribeiraoPreto = LatLng(-21.1775, -47.8103);

  @override
  void initState() {
    super.initState();
    _escutarMotoboys();
  }

  void _escutarMotoboys() {
    _supabase
        .from('entregadores')
        .stream(primaryKey: ['id'])
        .listen((data) {
      setState(() {
        _markers = data
            .where((e) => e['lat'] != null && e['lng'] != null && e['disponivel'] == true)
            .map((e) => Marker(
                  point: LatLng(e['lat'], e['lng']),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.delivery_dining, color: Colors.orange, size: 36),
                ))
            .toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Motoboys Disponíveis'),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${_markers.length} motoboy(s) disponível(is) agora',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: MapaWidget(
              center: _ribeiraoPreto,
              markers: _markers,
              zoom: 13,
            ),
          ),
        ],
      ),
    );
  }
}
