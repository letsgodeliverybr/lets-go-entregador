import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'location_service.dart';

class TrackingService {
  static final _supabase = Supabase.instance.client;
  static StreamSubscription<Position>? _sub;
  static Timer? _timer;
  static bool _ativo = false;
  static Position? _ultimaPosicao;

  static Future<void> iniciar(String entregadorId) async {
    if (_ativo) return;
    _ativo = true;

    debugPrint('[TrackingService] Iniciando rastreamento para $entregadorId');

    // Envia posição inicial imediatamente
    final posInicial = await LocationService.getCurrentPosition();
    if (posInicial != null) {
      _ultimaPosicao = posInicial;
      await _enviar(entregadorId, posInicial);
    }

    // Stream de posição do GPS
    _sub = LocationService.getPositionStream().listen(
      (pos) async {
        _ultimaPosicao = pos;
        await _enviar(entregadorId, pos);
      },
      onError: (e) => debugPrint('[TrackingService] Erro no stream: $e'),
      cancelOnError: false,
    );

    // Timer fallback: garante envio a cada 5s mesmo que o stream não dispare
    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final pos = _ultimaPosicao;
      if (pos != null) await _enviar(entregadorId, pos);
    });
  }

  static Future<void> _enviar(String entregadorId, Position pos) async {
    try {
      await _supabase.from('entregadores').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'disponivel': true,
        'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
      debugPrint('[TrackingService] GPS enviado: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}');
    } catch (e) {
      debugPrint('[TrackingService] Erro ao enviar GPS: $e');
    }
  }

  static Future<void> parar(String entregadorId) async {
    _ativo = false;
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    _ultimaPosicao = null;
    debugPrint('[TrackingService] Rastreamento parado');
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

  /// Marca motoboy como offline e para o rastreamento
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
