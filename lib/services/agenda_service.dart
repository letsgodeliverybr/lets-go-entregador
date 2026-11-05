import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'location_service.dart';

/// Agendamento 131: vaga única do dia, bônus por entregas e chegada na base.
///
/// Toda regra fica no banco (funções agenda_*): o app só mostra o estado que
/// o servidor devolve em `agenda_status()` e pede reserva/cancelamento/
/// chegada. Atualiza ao vivo pelo Realtime do Supabase — as tabelas têm RLS,
/// então cada entregador só recebe as próprias linhas — e, de reserva, a
/// cada 30 s enquanto alguma tela que usa o estado está aberta.
///
/// Assinatura por contagem de uso: [ativar] ao abrir a tela, [desativar] ao
/// sair/minimizar. Com zero telas, canal e timer são cancelados (bateria).
class AgendaService extends ChangeNotifier {
  AgendaService._();
  static final AgendaService instance = AgendaService._();

  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? estado;
  bool carregando = false;
  String? erro;

  /// Conferência da chegada (só durante a janela, com vaga e sem pedido).
  Map<String, dynamic>? chegadaConferida;

  /// Nomes das bases ativas com área (cadastradas pelo ADM no painel) — o
  /// card usa no texto da chegada; nada de nome fixo no código.
  List<String> basesNomes = const [];

  /// Incrementa quando chega crédito/pedido novo do entregador — a Home usa
  /// para recarregar o saldo sem esperar o próprio canal dela.
  final ValueNotifier<int> saldoMudou = ValueNotifier<int>(0);

  int _usos = 0;
  RealtimeChannel? _canal;
  Timer? _timer30s;
  Timer? _debounce;
  Timer? _retry;
  int _retryCont = 0;
  String? _uid;

  bool get ativo => _usos > 0;

  void ativar() {
    _usos++;
    if (_usos == 1) _ligar();
  }

  void desativar() {
    if (_usos == 0) return;
    _usos--;
    if (_usos == 0) _desligar();
  }

  void _ligar() {
    _uid = _supabase.auth.currentUser?.id;
    if (_uid == null) return;
    _assinar();
    _timer30s?.cancel();
    _timer30s = Timer.periodic(const Duration(seconds: 30), (_) => atualizar());
    atualizar();
  }

  Future<void> _desligar() async {
    _timer30s?.cancel();
    _timer30s = null;
    _debounce?.cancel();
    _retry?.cancel();
    _retry = null;
    _retryCont = 0;
    final c = _canal;
    _canal = null;
    if (c != null) await _supabase.removeChannel(c);
  }

  void _assinar() {
    final uid = _uid!;
    PostgresChangeFilter doEntregador() => PostgresChangeFilter(
        type: PostgresChangeFilterType.eq, column: 'entregador_id', value: uid);
    _canal = _supabase
        .channel('agenda_${uid}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'agenda_reservas',
            filter: doEntregador(), callback: (_) => _agendar())
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'agenda_pagamentos',
            filter: doEntregador(), callback: (_) => _agendar(saldo: true))
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'agenda_chegadas',
            filter: doEntregador(), callback: (_) => _agendar())
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'creditos_entregadores',
            filter: doEntregador(), callback: (_) => _agendar(saldo: true))
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'agenda_vagas_dia',
            callback: (_) => _agendar())
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'pedidos',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq, column: 'motoboy_id', value: uid),
            callback: (_) => _agendar())
        .subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _retry?.cancel();
        _retry = null;
        _retryCont = 0;
        // Voltou a conexão: busca o estado atual (pode ter perdido eventos).
        atualizar();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('[Agenda] Realtime caiu ($status) — reconectando');
        _reconectar();
      }
    });
  }

  void _reconectar() {
    if (!ativo) return;
    _retry?.cancel();
    final s = _retryCont < 5 ? (2 << _retryCont) : 60;
    _retryCont++;
    _retry = Timer(Duration(seconds: s), () async {
      if (!ativo) return;
      final c = _canal;
      _canal = null;
      if (c != null) await _supabase.removeChannel(c);
      _assinar();
    });
  }

  void _agendar({bool saldo = false}) {
    if (saldo) saldoMudou.value++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), atualizar);
  }

  Future<void> atualizar() async {
    if (_supabase.auth.currentUser == null) return;
    try {
      final r = await _supabase.rpc('agenda_status');
      estado = Map<String, dynamic>.from(r as Map);
      erro = null;
      await _carregarBasesNomes();
      await _conferirChegadaSePreciso();
    } catch (e) {
      debugPrint('[Agenda] erro ao atualizar: $e');
      erro = 'Sem conexão. Tentando de novo…';
    }
    notifyListeners();
  }

  Future<void> _carregarBasesNomes() async {
    final ch = Map<String, dynamic>.from(estado?['chegada'] as Map? ?? {});
    if (estado?['reservado'] != true || ch['vale_hoje'] != true) return;
    try {
      final r = await _supabase
          .from('agenda_bases')
          .select('nome')
          .eq('ativo', true)
          .not('poligono', 'is', null)
          .order('nome');
      basesNomes = [for (final b in List<Map<String, dynamic>>.from(r)) (b['nome'] ?? '').toString()]
        ..removeWhere((n) => n.isEmpty);
    } catch (_) {}
  }

  bool get _chegadaEmAberto {
    final e = estado;
    if (e == null || e['reservado'] != true) return false;
    final ch = Map<String, dynamic>.from(e['chegada'] as Map? ?? {});
    return ch['vale_hoje'] == true && ch['janela_aberta'] == true && ch['status'] == null;
  }

  // Durante a janela (18:30–19:00, com vaga): confere no
  // servidor se o botão pode aparecer. Se faltou só um GPS recente/preciso,
  // manda uma posição nova (o entregador parado na base não gera ping).
  Future<void> _conferirChegadaSePreciso() async {
    if (!_chegadaEmAberto) {
      chegadaConferida = null;
      return;
    }
    var r = await _rpcChegada(conferir: true);
    if (r['motivo'] == 'sem_sinal' || r['motivo'] == 'precisao') {
      if (await _enviarPosicaoAgora()) r = await _rpcChegada(conferir: true);
    }
    chegadaConferida = r;
  }

  Future<Map<String, dynamic>> _rpcChegada({required bool conferir}) async {
    final r = await _supabase
        .rpc('agenda_solicitar_chegada', params: {'p_somente_conferir': conferir});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<bool> _enviarPosicaoAgora() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos == null || _uid == null) return false;
      // Só lat/lng/gps_meta — nunca disponivel/status (mesma regra dos pings).
      await _supabase.from('entregadores').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'gps_meta': LocationService.gpsMeta(pos),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _uid!);
      return true;
    } catch (e) {
      debugPrint('[Agenda] erro ao enviar posição: $e');
      return false;
    }
  }

  Future<String> reservar() => _acao('agenda_reservar');
  Future<String> cancelar() => _acao('agenda_cancelar');

  Future<String> solicitarChegada() async {
    try {
      await _enviarPosicaoAgora();
      final r = await _rpcChegada(conferir: false);
      await atualizar();
      return (r['msg'] as String?) ?? '';
    } catch (e) {
      return 'Não foi possível enviar agora. Verifique a internet.';
    }
  }

  Future<String> _acao(String fn) async {
    try {
      final r = Map<String, dynamic>.from(await _supabase.rpc(fn) as Map);
      await atualizar();
      return (r['msg'] as String?) ?? '';
    } catch (e) {
      return 'Não foi possível agora. Verifique a internet.';
    }
  }
}
