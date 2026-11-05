import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BaseArea {
  final String id;
  final String nome;
  final List<LatLng> pontos;
  const BaseArea(this.id, this.nome, this.pontos);
}

/// Áreas das bases (Agendamento > Bases do painel) para o mapa da Home.
///
/// O entregador só LÊ agenda_bases (RLS); quem desenha é o ADM. Atualiza ao
/// vivo pelo Realtime enquanto a tela do mapa está aberta. Só desenha: quem
/// decide a chegada é o servidor (agenda_solicitar_chegada, pelo card).
class BasesService extends ChangeNotifier {
  BasesService._();
  static final BasesService instance = BasesService._();

  final _supabase = Supabase.instance.client;

  List<BaseArea> areas = const [];

  int _usos = 0;
  RealtimeChannel? _canal;
  Timer? _debounce;
  Timer? _retry;
  int _retryCont = 0;

  void ativar() {
    _usos++;
    if (_usos == 1) {
      _assinar();
      _carregarAreas();
    }
  }

  Future<void> desativar() async {
    if (_usos == 0) return;
    _usos--;
    if (_usos > 0) return;
    _debounce?.cancel();
    _retry?.cancel();
    _retryCont = 0;
    final c = _canal;
    _canal = null;
    if (c != null) await _supabase.removeChannel(c);
  }

  void _assinar() {
    _canal = _supabase
        .channel('bases_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'agenda_bases',
          callback: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 500), _carregarAreas);
          },
        )
        .subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _retryCont = 0;
        _carregarAreas(); // voltou a conexão: estado atual
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        if (_usos == 0) return;
        _retry?.cancel();
        final s = _retryCont < 5 ? (2 << _retryCont) : 60;
        _retryCont++;
        _retry = Timer(Duration(seconds: s), () async {
          if (_usos == 0) return;
          final c = _canal;
          _canal = null;
          if (c != null) await _supabase.removeChannel(c);
          _assinar();
        });
      }
    });
  }

  Future<void> _carregarAreas() async {
    try {
      final r = await _supabase.from('agenda_bases').select('id, nome, poligono, ativo');
      final lista = <BaseArea>[];
      for (final b in List<Map<String, dynamic>>.from(r)) {
        final poli = b['poligono'];
        if (b['ativo'] != true || poli is! List || poli.length < 3) continue;
        final pontos = <LatLng>[];
        for (final p in poli) {
          if (p is List && p.length == 2) {
            pontos.add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
          }
        }
        if (pontos.length >= 3) lista.add(BaseArea(b['id'] as String, (b['nome'] ?? '') as String, pontos));
      }
      areas = lista;
      notifyListeners();
    } catch (e) {
      debugPrint('[Bases] erro ao carregar áreas: $e');
    }
  }
}
