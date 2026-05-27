import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'location_service.dart';

class TrackingService {
  static final _supabase = Supabase.instance.client;
  static StreamSubscription<Position>? _sub;
  static bool _ativo = false;

  /// Inicia envio de GPS para o Supabase
  static Future<void> iniciar(String entregadorId) async {
    if (_ativo) return;
    _ativo = true;

    _sub = LocationService.getPositionStream().listen((pos) async {
      try {
        await _supabase.from('entregadores').update({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'disponivel': true,
          'status': 'ocupado',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', entregadorId);
      } catch (_) {}
    });
  }

  /// Para o envio de GPS
  static Future<void> parar(String entregadorId) async {
    _ativo = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _supabase.from('entregadores').update({
        'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}
  }

  /// Marca motoboy como online/disponível
  static Future<void> ficarOnline(String entregadorId) async {
    final pos = await LocationService.getCurrentPosition();
    try {
      await _supabase.from('entregadores').update({
        'disponivel': true,
        'status': 'disponivel',
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'latitude': pos?.latitude,
        'longitude': pos?.longitude,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}
  }

  /// Marca motoboy como offline
  static Future<void> ficarOffline(String entregadorId) async {
    await parar(entregadorId);
    try {
      await _supabase.from('entregadores').update({
        'disponivel': false,
        'status': 'offline',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}
  }

  static bool get ativo => _ativo;
}
