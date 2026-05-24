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

  void _escutarMotoboys() {
    _supabase
        .from('entregadores')
        .stream(primaryKey: ['id'])
        .listen((data) {
      setState(() {
        _markers = data
            .where((e) => e['lat'] != null && e['lng'] != null)
            .map((e) => Marker(
                  point: LatLng(e['lat'], e['lot']),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.delivery_dining, color: Colors.green, size: 36),
                ))
            .toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel ADM - Motoboys'),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
      ),
      body: _markers.isEmpty
          ? const Center(child: Text('Nenhum motoboy ativo'))
          : MapaWidget(
              center: _markers.first.point,
              markers: _markers,
              zoom: 13,
            ),
    );
  }
}
