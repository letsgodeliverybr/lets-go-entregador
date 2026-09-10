import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'battery_service.dart';
import 'location_service.dart';
import 'foreground_service.dart';
import 'notification_service.dart';

class TrackingService {
  static final _supabase = Supabase.instance.client;
  static StreamSubscription<Position>? _sub;
  static StreamSubscription<int>? _batterySub;
  static bool _ativo = false;
  static bool _forcandoOfflinePorBateria = false;
  // Estado (não concorrência) — 2026-09-10, corrige alerta repetido: marca
  // que já disparou o alerta/offline PRO CRUZAMENTO ATUAL de 15%, distinto
  // de [_forcandoOfflinePorBateria] (que só evita 2 chamadas simultâneas e
  // é resetada assim que uma chamada termina — sem isso, o próximo
  // ACTION_BATTERY_CHANGED nativo, que pode disparar de novo mesmo sem o
  // % mudar de verdade, ver BatteryService, passava livre e repetia som/
  // vibração/notificação). Só volta a `false` quando o nível se recupera
  // pra ≥15% (uma queda futura já conta como cruzamento novo, deve
  // alertar de novo) ou quando o rastreamento reinicia.
  static bool _jaAlertouBateriaBaixa = false;
  static Position? _ultimaPosicao;
  static String? _entregadorId;

  // Telas (Home, Status) assinam isso pra saber, na hora, quando o serviço
  // forçou `disponivel=false` por bateria baixa — sem isso o toggle só
  // resincroniza ao reabrir a tela (_carregarEntregador), não enquanto o
  // motoboy já está parado nela com uma entrega em andamento (ver auditoria
  // 2026-09-08). Lista simples em vez de Stream/ValueNotifier porque não
  // carrega valor nenhum, é só um "aconteceu agora" — a tela decide o que
  // fazer (setState(() => _online = false)).
  static final List<void Function()> _listenersForcadoOffline = [];
  static void addForcadoOfflineListener(void Function() cb) => _listenersForcadoOffline.add(cb);
  static void removeForcadoOfflineListener(void Function() cb) => _listenersForcadoOffline.remove(cb);
  static void _notificarForcadoOffline() {
    for (final cb in List<void Function()>.from(_listenersForcadoOffline)) {
      cb();
    }
  }

  /// Lança [Exception] se a bateria estiver abaixo do limite mínimo
  /// (BatteryService.limiteMinimo) — chamado no início de [ficarOnline] E
  /// [iniciar] (não só um dos dois): ambos os fluxos de toggle do app
  /// (entregador_home_screen.dart, online_status_screen.dart) chamam os
  /// dois em sequência, e checar só em um deixaria uma janela onde
  /// `disponivel=true` já foi gravado no banco antes do outro barrar —
  /// estado inconsistente (banco diz disponível, ninguém rastreando de
  /// verdade). nivel==null (falha de leitura) NÃO bloqueia — não faz
  /// sentido impedir o entregador de trabalhar por uma falha de leitura,
  /// não da bateria em si.
  static Future<void> _exigirBateriaOk() async {
    final nivel = await BatteryService.nivelAtual();
    if (nivel != null && nivel < BatteryService.limiteMinimo) {
      throw Exception(
        'Bateria abaixo de ${BatteryService.limiteMinimo}%. '
        'Carregue o celular antes de ficar disponível.',
      );
    }
  }

  static Future<void> iniciar(String entregadorId) async {
    if (_ativo) return;
    await _exigirBateriaOk();
    _ativo = true;
    _entregadorId = entregadorId;

    debugPrint('[TrackingService] ▶ Iniciando rastreamento para $entregadorId');

    // Marca disponivel:true explicitamente aqui (não mais como efeito
    // colateral do primeiro ping de GPS, ver _enviar) — entregador_home_screen.dart
    // chama iniciar() direto, sem passar por ficarOnline() antes.
    try {
      await _supabase.from('entregadores').update({
        'disponivel': true,
        'status': 'disponivel',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', entregadorId);
    } catch (_) {}

    WakelockPlus.enable();
    await ForegroundService.iniciar(entregadorId);
    _assinarBateria(entregadorId);

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
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        _ultimaPosicao = pos;
        await _enviar(entregadorId, pos);
      } else if (_ultimaPosicao != null) {
        await _enviar(entregadorId, _ultimaPosicao!);
      }
    } catch (e) {
      debugPrint('[TrackingService] ⚠ Erro no loop: $e — reiniciando em 5s');
      await Future.delayed(const Duration(seconds: 5));
    }
    if (_ativo) _loopEnvio(entregadorId);
  }

  // Stream contínua (ACTION_BATTERY_CHANGED nativo, ver BatteryService) —
  // reage assim que o Android informa o nível cruzando o limite, sem
  // esperar nenhum ciclo de verificação próprio. Assinada só enquanto
  // online (chamada em iniciar(), cancelada em parar()) — não faz sentido
  // gastar esse listener com o entregador offline.
  static void _assinarBateria(String entregadorId) {
    _batterySub?.cancel();
    _jaAlertouBateriaBaixa = false; // novo início de rastreamento, estado limpo
    _batterySub = BatteryService.onLevelChanged.listen((nivel) {
      if (nivel >= BatteryService.limiteMinimo) {
        // Recuperou (carregou) acima do limite — uma queda futura no mesmo
        // turno é um cruzamento NOVO, deve alertar de novo.
        _jaAlertouBateriaBaixa = false;
        return;
      }
      if (_jaAlertouBateriaBaixa) return; // já alertou pra esse cruzamento
      _forcarOfflinePorBateria(entregadorId, nivel);
    });
  }

  // Força indisponível por bateria baixa enquanto já online.
  //
  // Correção 2026-09-08 (auditoria de segurança operacional): a versão
  // anterior desistia silenciosamente quando havia entrega ativa,
  // assumindo que bastava não conseguir NOVAS ofertas — entregadores_no_raio()
  // já exclui quem tem pedido ativo, então o resultado (não recebe oferta
  // nova) é o mesmo de qualquer jeito. Mas o pedido explícito era sobre o
  // ESTADO, não só o resultado: `disponivel` tem que virar false JÁ, e o
  // toggle da tela tem que mostrar isso, mesmo com entrega em andamento —
  // não só depois de finalizar. Por isso agora: tenta o desligamento
  // completo (ficarOffline, que também para GPS/foreground) e, se recusar
  // por entrega ativa, cai pro desligamento "suave" — só grava
  // `disponivel=false`, sem tocar em tracking/GPS/foreground service (o
  // motoboy ainda precisa disso tudo rodando pra terminar a entrega em
  // mãos). `_forcandoOfflinePorBateria` evita disparo duplicado se o
  // stream emitir mais de um valor abaixo do limite antes da primeira
  // chamada terminar (ambos os caminhos são assíncronos); `_jaAlertouBateriaBaixa`
  // evita o disparo repetido DEPOIS que essa chamada já terminou, pro mesmo
  // cruzamento (ver comentário em _assinarBateria).
  static Future<void> _forcarOfflinePorBateria(String entregadorId, int nivel) async {
    if (_forcandoOfflinePorBateria) return;
    _forcandoOfflinePorBateria = true;
    _jaAlertouBateriaBaixa = true;
    try {
      try {
        await ficarOffline(entregadorId);
        debugPrint('[TrackingService] 🔋 Forçado indisponível — bateria em $nivel%');
      } catch (e) {
        debugPrint('[TrackingService] 🔋 Bateria baixa ($nivel%) com entrega em andamento — mantendo tracking, só marcando indisponível: $e');
        try {
          await _supabase.from('entregadores').update({
            'disponivel': false,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', entregadorId);
        } catch (_) {}
      }
      // ignore: unawaited_futures
      NotificationService.showBateriaBaixaLocal(nivel);
      _notificarForcadoOffline();
    } finally {
      _forcandoOfflinePorBateria = false;
    }
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

  // NÃO reafirma disponivel:true/status:'disponivel' aqui — bug real
  // encontrado em auditoria (2026-09-03): um ping de GPS já em voo (esse
  // request) podia responder DEPOIS do UPDATE disponivel:false de
  // ficarOffline() (ex: forçado por bateria baixa, ver
  // _forcarOfflinePorBateria), sobrescrevendo o offline de volta pra
  // online — sem nenhuma outra causa, o entregador "voltava sozinho pra
  // online" simplesmente por causa da corrida entre esses dois updates
  // independentes. disponivel/status são responsabilidade exclusiva de
  // ficarOnline/ficarOffline/iniciar/parar — o ping de posição só deve
  // mexer em lat/lng.
  static Future<void> _enviar(String entregadorId, Position pos) async {
    try {
      await _supabase.from('entregadores').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
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
    await _batterySub?.cancel();
    _batterySub = null;
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
    await _exigirBateriaOk();
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

  /// Reconsulta a bateria atual e força offline se estiver abaixo do
  /// limite — usado pelas telas que exibem o toggle (Home, Status) toda
  /// vez que aparecem de novo (voltar de outra aba), não só no momento do
  /// toque. Fonte de verdade única: mesma [BatteryService]/[ficarOffline]
  /// usados no gate do toggle e no listener contínuo — nenhuma tela
  /// duplica a regra, só chama isso antes de confiar no `disponivel` lido
  /// do banco.
  ///
  /// Retorna `false` (e força offline, respeitando a exceção de entrega
  /// ativa de [ficarOffline]) se a bateria estiver baixa; `true` caso
  /// contrário (bateria ok ou leitura falhou — não bloqueia por falha de
  /// leitura, mesmo racional de [_exigirBateriaOk]). Só chama a rede se
  /// [aindaOnlineSegundoBanco] for true — não faz sentido forçar offline
  /// de quem já está offline.
  static Future<bool> verificarBateriaEForcarOffline(
    String entregadorId, {
    required bool aindaOnlineSegundoBanco,
  }) async {
    if (!aindaOnlineSegundoBanco) return false;
    final nivel = await BatteryService.nivelAtual();
    if (nivel == null) return true;
    if (nivel >= BatteryService.limiteMinimo) {
      // Recuperou — mesma lógica de _assinarBateria: uma queda futura no
      // mesmo turno volta a contar como cruzamento novo.
      _jaAlertouBateriaBaixa = false;
      return true;
    }
    try {
      await ficarOffline(entregadorId);
      debugPrint('[TrackingService] 🔋 Offline mantido/forçado ao reabrir a tela — bateria em $nivel%');
      // 2026-09-10: sem essa checagem, voltar pra essa tela várias vezes
      // (trocar de aba e voltar) com bateria já baixa disparava a
      // notificação de novo a cada volta — segundo ponto de disparo
      // repetido, junto com o listener contínuo em _assinarBateria. Mesmo
      // flag de estado dos dois caminhos, pra nunca alertar 2x pro mesmo
      // cruzamento não importa por qual caminho ele foi detectado.
      if (!_jaAlertouBateriaBaixa) {
        _jaAlertouBateriaBaixa = true;
        // ignore: unawaited_futures
        NotificationService.showBateriaBaixaLocal(nivel);
      }
      return false;
    } catch (_) {
      // Entrega ativa — ficarOffline já recusou, entregador continua
      // online de verdade (exceção da regra, ver ponto 5 já implementado).
      return true;
    }
  }

  static bool get ativo => _ativo;
}
