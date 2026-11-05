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
/// vivo pelo Realtime enquanto a tela do mapa está aberta. Não liga GPS:
/// o "dentro/fora" usa a posição que o mapa já tem e é só informação — quem
/// decide a chegada é o servidor (agenda_solicitar_chegada).
class BasesService extends ChangeNotifier {
  BasesService._();
  static final BasesService instance = BasesService._();

  final _supabase = Supabase.instance.client;

  List<BaseArea> areas = const [];

  /// Faixa "+R$ 10 CHEGADA 18:30–19:00": só nos dias em que a chegada vale.
  String? faixaChegada;

  int _usos = 0;
  RealtimeChannel? _canal;
  Timer? _debounce;
  Timer? _retry;
  Timer? _dia;
  int _retryCont = 0;

  void ativar() {
    _usos++;
    if (_usos == 1) {
      _assinar();
      // A faixa da chegada depende da config do ADM e do dia: relê de hora em hora.
      _dia = Timer.periodic(const Duration(hours: 1), (_) => _carregarFaixa());
      carregar();
    }
  }

  Future<void> desativar() async {
    if (_usos == 0) return;
    _usos--;
    if (_usos > 0) return;
    _dia?.cancel();
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

  Future<void> carregar() async {
    await Future.wait([_carregarAreas(), _carregarFaixa()]);
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

  Future<void> _carregarFaixa() async {
    try {
      final r = Map<String, dynamic>.from(await _supabase.rpc('agenda_status') as Map);
      final ch = Map<String, dynamic>.from(r['chegada'] as Map? ?? {});
      final v = (ch['valor'] as num?)?.toDouble() ?? 0;
      final valor = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');
      faixaChegada = ch['vale_hoje'] == true ? '+R\$ $valor CHEGADA ${ch['inicio']}–${ch['fim']}' : null;
      notifyListeners();
    } catch (e) {
      debugPrint('[Bases] erro ao ler a faixa de chegada: $e');
    }
  }

  /// Nome da base cuja área contém [p] (mesma conta do servidor), ou null.
  String? baseEm(LatLng p) {
    for (final a in areas) {
      if (_dentro(p, a.pontos)) return a.nome;
    }
    return null;
  }

  static bool _dentro(LatLng p, List<LatLng> poli) {
    var d = false;
    for (var i = 0, j = poli.length - 1; i < poli.length; j = i++) {
      final yi = poli[i].latitude, xi = poli[i].longitude;
      final yj = poli[j].latitude, xj = poli[j].longitude;
      if (((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi)) {
        d = !d;
      }
    }
    return d;
  }
}
