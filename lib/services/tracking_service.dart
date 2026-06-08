import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'location_service.dart';
import 'foreground_service.dart';

class TrackingService {
  static final _supabase = Supabase.instance.client;
  static StreamSubscription<Position>? _sub;
  static bool _ativo = false;
  static Position? _ultimaPosicao;
  static String? _entregadorId;

  static Future<void> iniciar(String entregadorId) async {
    if (_ativo) return;
    _ativo = true;
    _entregadorId = entregadorId;

    debugPrint('[TrackingService] ▶ Iniciando rastreamento para $entregadorId');

    WakelockPlus.enable();
    await ForegroundService.iniciar(entregadorId);

    // 1. Posição inicial imediata
    final posInicial = await LocationService.getCurrentPosition();
    if (posInicial != null) {
      _ultimaPosicao = posInicial;
      await _enviar(entregadorId, posInicial);
    }

    // 2. Stream do GPS — recebe atualizações quando há movimento
    _assinarStream(entregadorId);
    debugPrint('[TrackingService] Stream GPS assinado: $_sub');

    // 3. Loop resiliente: busca posição a cada 8s, se autoreinicia após erro
    _loopEnvio(entregadorId);
  }

  static Future<void> _loopEnvio(String entregadorId) async {
    await Future.delayed(const Duration(seconds: 8));
    if (!_ativo) return;
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      _ultimaPosicao = pos;
      await _enviar(entregadorId, pos);
    } else if (_ultimaPosicao != null) {
      await _enviar(entregadorId, _ultimaPosicao!);
    }
    if (_ativo) _loopEnvio(entregadorId);
  }

  static void _assinarStream(String entregadorId) {
    _sub?.cancel();
    _sub = LocationService.getPositionStream().listen(
      (pos) {
        _ultimaPosicao = pos;
        _enviar(entregadorId, pos);
      },
      onError: (e) {
        debugPrint('[TrackingService] ⚠ Erro no stream: $e — reiniciando em 10s');
        _sub?.cancel();
        _sub = null;
        if (!_ativo) return;
        Future.delayed(const Duration(seconds: 10), () {
          if (_ativo) _assinarStream(entregadorId);
        });
      },
      cancelOnError: true,
    );
  }

  static Future<void> _enviar(String entregadorId, Position pos) async {
    try {
      await _supabase.from('entregadores').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'disponivel': true,
        'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
      debugPrint('[TrackingService] ✓ GPS: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}');
    } catch (e) {
      debugPrint('[TrackingService] ✗ Erro ao enviar GPS: $e');
    }
  }

  static Future<void> parar(String entregadorId) async {
    _ativo = false;
    await _sub?.cancel();
    _sub = null;
    _ultimaPosicao = null;
    _entregadorId = null;
    WakelockPlus.disable();
    await ForegroundService.parar();
    debugPrint('[TrackingService] ■ Rastreamento parado');
    try {
      await _supabase.from('entregadores').update({
        'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}
  }

  static Future<void> ficarOnline(String entregadorId) async {
    final pos = await LocationService.getCurrentPosition();
    try {
      await _supabase.from('entregadores').update({
        'disponivel': true,
        'status': 'disponivel',
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}
  }

  /// Tenta marcar o entregador como offline.
  ///
  /// Lança [Exception] se houver pedido ativo (aceito / chegou_local /
  /// em_rota / retornando) — o chamador deve capturar e exibir o alerta.
  static Future<void> ficarOffline(String entregadorId) async {
    final ativos = await _supabase
        .from('pedidos')
        .select('id')
        .eq('motoboy_id', entregadorId)
        .inFilter('status', ['aceito', 'chegou_local', 'em_rota', 'retornando']);

    if (ativos.isNotEmpty) {
      throw Exception(
        'Você possui uma entrega em andamento. '
        'Finalize a entrega antes de ficar offline.',
      );
    }

    await parar(entregadorId);
    try {
      await _supabase.from('entregadores').update({
        'disponivel': false,
        'status': 'offline',
        'lat': null,
        'lng': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}
  }

  static bool get ativo => _ativo;
}
