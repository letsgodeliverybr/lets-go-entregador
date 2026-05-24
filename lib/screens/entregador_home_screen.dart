import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/location_service.dart';

class EntregadorHomeScreen extends StatefulWidget {
  const EntregadorHomeScreen({super.key});

  @override
  State<EntregadorHomeScreen> createState() => _EntregadorHomeScreenState();
}

class _EntregadorHomeScreenState extends State<EntregadorHomeScreen> {
  StreamSubscription<Position>? _locationSubscription;
  bool _rastreandoAtivo = false;
  String _status = 'Parado';
  double? _lat;
  double? _lng;

  final _supabase = Supabase.instance.client;

  void _iniciarRastreamento() {
    setState(() {
      _rastreandoAtivo = true;
      _status = 'Rastreando...';
    });

    _locationSubscription = LocationService.getPositionStream().listen((position) async {
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });

      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        await _supabase.from('entregadores').upsert({
          'id': userId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'atualizado_em': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  void _pararRastreamento() {
    _locationSubscription?.cancel();
    setState(() {
      _rastreandoAtivo = false;
      _status = 'Parado';
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel do Entregador'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _supabase.auth.signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _rastreandoAtivo ? Icons.location_on : Icons.location_off,
              size: 80,
              color: _rastreandoAtivo ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(fontSize: 20)),
            if (_lat != null) ...[
              const SizedBox(height: 8),
              Text('Lat: ${_lat!.toStringAsFixed(6)}'),
              Text('Lng: ${_lng!.toStringAsFixed(6)}'),
            ],
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: Icon(_rastreandoAtivo ? Icons.stop : Icons.play_arrow),
              label: Text(_rastreandoAtivo ? 'Parar' : 'Iniciar Rastreamento'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _rastreandoAtivo ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              onPressed: _rastreandoAtivo ? _pararRastreamento : _iniciarRastreamento,
            ),
          ],
        ),
      ),
    );
  }
}
