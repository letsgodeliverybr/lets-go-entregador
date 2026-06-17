import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/foreground_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/tracking_service.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'pedidos_aceitos_screen.dart';

enum EtapaEntrega { aceito, chegouLocal, emRota, chegouDestino, retornando, aguardandoPagamento, finalizado }

class EntregaScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;
  const EntregaScreen({super.key, required this.pedido});
  @override
  State<EntregaScreen> createState() => _EntregaScreenState();
}

class _EntregaScreenState extends State<EntregaScreen> with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  final _codigoCtrl = TextEditingController();
  EtapaEntrega _etapa = EtapaEntrega.aceito;
  bool _carregando = false;
  String? _erro;

  Position? _posicaoAtual;
  double? _distanciaLojaKm;
  String? _enderecoLoja;
  String? _nomeLoja;
  double? _lojaLat;
  double? _lojaLng;
  double _precoDinamico = 0.0;
  StreamSubscription<Position>? _subProximidade;
  RealtimeChannel? _subPedido;
  Timer? _retryTimerPedido;
  int _retryContPedido = 0;

  String get _pedidoId => widget.pedido['id'].toString();

  @override
  void initState() {
    super.initState();
    final status = widget.pedido['status_detalhado'] ?? widget.pedido['status'] ?? '';
    switch (status) {
      case 'aceito':               _etapa = EtapaEntrega.aceito; break;
      case 'no_local':
      case 'chegou_local':         _etapa = EtapaEntrega.chegouLocal; break;
      case 'em_rota':              _etapa = EtapaEntrega.emRota; break;
      case 'chegou_destino':       _etapa = EtapaEntrega.chegouDestino; break;
      case 'retornando':           _etapa = EtapaEntrega.retornando; break;
      case 'aguardando_pagamento': _etapa = EtapaEntrega.aguardandoPagamento; break;
      default:                     _etapa = EtapaEntrega.aceito;
    }
    if (_etapa == EtapaEntrega.retornando || _etapa == EtapaEntrega.aguardandoPagamento) {
      _iniciarPollingPagamento();
    }
    if (_etapa == EtapaEntrega.emRota || _etapa == EtapaEntrega.retornando) {
      _iniciarVerificacaoProximidade();
    }
    _obterPosicao();
    _buscarInfoLoja();
    _buscarPrecoDinamico();
    _assinarResetPedido();
    _configurarComunicacaoForeground();
    _solicitarExcecaoBateria();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sincronizarStatusPedido();
  }

  // Ao voltar ao foreground, lê o status atual do banco — garante que a UI
  // reflita mudanças que aconteceram enquanto a tela estava bloqueada e o
  // Realtime perdeu eventos durante o lock (WebSocket cai e não replaya).
  Future<void> _sincronizarStatusPedido() async {
    if (!mounted) return;
    if (_etapa != EtapaEntrega.emRota && _etapa != EtapaEntrega.retornando) return;
    try {
      final data = await _supabase
          .from('pedidos')
          .select('status, status_detalhado')
          .eq('id', _pedidoId)
          .single();
      final status = (data['status_detalhado'] ?? data['status'])?.toString() ?? '';
      debugPrint('[EntregaScreen] sincronizar ao resumir: status_banco=$status etapa_atual=$_etapa');
      if (!mounted) return;
      if (status == 'chegou_destino' &&
          (_etapa == EtapaEntrega.emRota || _etapa == EtapaEntrega.retornando)) {
        debugPrint('[EntregaScreen] chegou_destino detectado no resume — atualizando UI');
        setState(() => _etapa = EtapaEntrega.chegouDestino);
        ForegroundService.desativarProximidade();
        NotificationService.showChegouDestinoLocal();
      }
    } catch (e) {
      debugPrint('[EntregaScreen] erro ao sincronizar status no resume: $e');
    }
  }

  Future<void> _abrirMaps(String endereco) async {
    final encoded = Uri.encodeComponent(endereco);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _buscarPrecoDinamico() async {
    try {
      final data = await _supabase
          .from('configuracoes')
          .select('valor')
          .eq('chave', 'preco_dinamico_entregador')
          .maybeSingle();
      final valor = double.tryParse(data?['valor']?.toString() ?? '0') ?? 0.0;
      if (mounted) setState(() => _precoDinamico = valor);
    } catch (_) {}
  }

  void _configurarComunicacaoForeground() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onDadosForeground);
    if (_etapa == EtapaEntrega.emRota || _etapa == EtapaEntrega.retornando) {
      _ativarProximidadeForeground();
    }
  }

  void _onDadosForeground(Object data) {
    if (data is! String) return;
    if (data.startsWith('chegou_destino:')) {
      final pedidoIdRecebido = data.split(':').last;
      if (pedidoIdRecebido == _pedidoId &&
          (_etapa == EtapaEntrega.emRota || _etapa == EtapaEntrega.retornando)) {
        debugPrint('[EntregaScreen] ForegroundTask detectou chegada — atualizando UI');
        if (mounted) setState(() => _etapa = EtapaEntrega.chegouDestino);
        NotificationService.showChegouDestinoLocal();
      }
    }
  }

  Future<void> _solicitarExcecaoBateria() async {
    try {
      final isIgnoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!isIgnoring) {
        debugPrint('[EntregaScreen] Solicitando exceção de otimização de bateria...');
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (e) {
      debugPrint('[EntregaScreen] Erro ao solicitar exceção de bateria: $e');
    }
  }

  void _ativarProximidadeForeground() {
    final clienteLat = (widget.pedido['latitude'] ?? widget.pedido['lat']) as num?;
    final clienteLng = (widget.pedido['longitude'] ?? widget.pedido['lng']) as num?;
    if (clienteLat != null && clienteLng != null) {
      ForegroundService.ativarProximidade(
        _pedidoId,
        clienteLat.toDouble(),
        clienteLng.toDouble(),
        status: 'em_rota',
      );
    } else {
      debugPrint('[EntregaScreen] Coordenadas do cliente ausentes — proximidade foreground não ativada');
    }
  }

  Future<void> _marcarChegouDestinoAutomatico() async {
    _subProximidade?.cancel();
    _subProximidade = null;
    if (!mounted) return;
    if (_etapa != EtapaEntrega.emRota && _etapa != EtapaEntrega.retornando) return;
    debugPrint('[EntregaScreen] Atualizando status para chegou_destino...');
    try {
      await _supabase.from('pedidos').update({
        'status': 'chegou_destino',
        'status_detalhado': 'chegou_destino',
        'chegou_destino_em': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _pedidoId);
      if (mounted) setState(() => _etapa = EtapaEntrega.chegouDestino);
      await NotificationService.showChegouDestinoLocal();
      ForegroundService.desativarProximidade();
      HapticFeedback.heavyImpact();
    } catch (e) {
      debugPrint('[EntregaScreen] Erro ao marcar chegou_destino automático: $e');
    }
  }

  Future<void> _buscarInfoLoja() async {
    final loja = widget.pedido['lojas'];
    if (loja != null) {
      final nome = loja['nome']?.toString() ?? '';
      final end = loja['endereco']?.toString() ?? '';
      if (nome.isNotEmpty || end.isNotEmpty) {
        if (mounted) setState(() { _nomeLoja = nome.isNotEmpty ? nome : null; _enderecoLoja = end.isNotEmpty ? end : null; });
        if (end.isNotEmpty) return;
      }
    }
    final endPedido = widget.pedido['endereco_loja']?.toString() ?? widget.pedido['endereco_coleta']?.toString() ?? '';
    if (endPedido.isNotEmpty) {
      if (mounted) setState(() => _enderecoLoja = endPedido);
      return;
    }
    final lojaId = widget.pedido['loja_id']?.toString();
    if (lojaId == null || lojaId.isEmpty) return;
    try {
      final data = await _supabase.from('lojas').select('nome, endereco, latitude, longitude').eq('id', lojaId).maybeSingle();
      if (data != null && mounted) {
        final nome = data['nome']?.toString() ?? '';
        final end = data['endereco']?.toString() ?? '';
        final lat = (data['latitude'] ?? data['lat']) as num?;
        final lng = (data['longitude'] ?? data['lng']) as num?;
        setState(() {
          if (nome.isNotEmpty) _nomeLoja = nome;
          if (end.isNotEmpty) _enderecoLoja = end;
          if (lat != null) _lojaLat = lat.toDouble();
          if (lng != null) _lojaLng = lng.toDouble();
        });
      }
    } catch (_) {}
  }

  Future<void> _obterPosicao() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() => _posicaoAtual = pos);
      final loja = widget.pedido['lojas'];
      if (loja != null) {
        final lat = (loja['lat'] ?? loja['latitude']) as num?;
        final lng = (loja['lng'] ?? loja['longitude']) as num?;
        if (lat != null && lng != null) {
          final coletaLat = (widget.pedido['latitude_coleta'] as num?)?.toDouble();
          final coletaLng = (widget.pedido['longitude_coleta'] as num?)?.toDouble();
          final distColeta = (coletaLat != null && coletaLng != null)
              ? _calcularDistancia(pos.latitude, pos.longitude, coletaLat, coletaLng)
              : _calcularDistancia(pos.latitude, pos.longitude, lat.toDouble(), lng.toDouble());
          if (mounted) setState(() {
            _distanciaLojaKm = distColeta;
            _lojaLat = lat.toDouble();
            _lojaLng = lng.toDouble();
          });
        }
      }
    } catch (_) {}
  }

  double _calcularDistancia(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void _iniciarPollingPagamento() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return false;
      try {
        final data = await _supabase.from('pedidos').select('pagamento_confirmado, status_detalhado').eq('id', _pedidoId).single();
        if (data['pagamento_confirmado'] == true) {
          if (mounted) setState(() => _etapa = EtapaEntrega.finalizado);
          return false;
        }
      } catch (_) {}
      return mounted && (_etapa == EtapaEntrega.retornando || _etapa == EtapaEntrega.aguardandoPagamento);
    });
  }

  void _iniciarVerificacaoProximidade() {
    final clienteLat = (widget.pedido['latitude'] ?? widget.pedido['lat']) as num?;
    final clienteLng = (widget.pedido['longitude'] ?? widget.pedido['lng']) as num?;
    if (clienteLat == null || clienteLng == null) {
      debugPrint('[PROX] Coordenadas do cliente ausentes — stream não iniciado');
      return;
    }
    debugPrint('[PROX] Iniciando stream (UI). Destino: lat=$clienteLat lng=$clienteLng, etapa: $_etapa');

    // Sem ForegroundNotificationConfig: o ForegroundTaskService já mantém GPS ativo
    // em background. Esta stream é fallback para quando o app está em foreground.
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            intervalDuration: const Duration(seconds: 5),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          );

    _subProximidade = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      final distM = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        clienteLat.toDouble(), clienteLng.toDouble(),
      );
      debugPrint('[GEO] distancia_destino=${distM.toStringAsFixed(0)}m acc=${pos.accuracy.toStringAsFixed(0)}m status=$_etapa');
      if (pos.accuracy > 30) return;
      if (distM <= 50 && (_etapa == EtapaEntrega.emRota || _etapa == EtapaEntrega.retornando)) {
        debugPrint('[PROX] ✓ Chegou ao destino! dist=${distM.toStringAsFixed(0)}m acc=${pos.accuracy.toStringAsFixed(0)}m');
        _marcarChegouDestinoAutomatico();
      }
    }, onError: (e) {
      debugPrint('[PROX] ⚠ Stream falhou: $e — reiniciando em 3s');
      _subProximidade?.cancel();
      _subProximidade = null;
      if (!mounted) return;
      final etapaAtual = _etapa;
      if (etapaAtual != EtapaEntrega.emRota && etapaAtual != EtapaEntrega.retornando) return;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && (_etapa == EtapaEntrega.emRota || _etapa == EtapaEntrega.retornando)) {
          _iniciarVerificacaoProximidade();
        }
      });
    }, cancelOnError: true);
  }

  void _assinarResetPedido() {
    _subPedido = _supabase
        .channel('pedido_reset_${_pedidoId}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _pedidoId,
          ),
          callback: (payload) {
            final novo = payload.newRecord;
            final status = novo['status']?.toString() ?? '';
            final motoboyId = novo['motoboy_id'];
            if (status == 'recebido' || status == 'pronto' || motoboyId == null) {
              _handleResetPedido();
            } else if (status == 'chegou_destino' &&
                (_etapa == EtapaEntrega.emRota || _etapa == EtapaEntrega.retornando)) {
              debugPrint('[EntregaScreen] Realtime: status=chegou_destino — atualizando UI');
              if (mounted) setState(() => _etapa = EtapaEntrega.chegouDestino);
            }
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _retryContPedido = 0;
            debugPrint('[EntregaScreen] Realtime subscribed OK');
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('[EntregaScreen] Realtime queda: status=$status error=$error — reconectando...');
            _agendarReconexaoPedido();
          }
        });
  }

  void _agendarReconexaoPedido() {
    if (!mounted) return;
    _retryTimerPedido?.cancel();
    final delayS = _retryContPedido < 6
        ? (2 << _retryContPedido).clamp(2, 30)
        : 30;
    _retryContPedido++;
    debugPrint('[EntregaScreen] Reconexão Realtime em ${delayS}s (tentativa $_retryContPedido)');
    _retryTimerPedido = Timer(Duration(seconds: delayS), () async {
      if (!mounted) return;
      if (_subPedido != null) {
        await _supabase.removeChannel(_subPedido!);
        _subPedido = null;
      }
      _assinarResetPedido();
    });
  }

  Future<void> _handleResetPedido() async {
    if (!mounted) return;
    _retryTimerPedido?.cancel();
    _retryTimerPedido = null;
    _subProximidade?.cancel();
    _subProximidade = null;
    if (_subPedido != null) {
      await _supabase.removeChannel(_subPedido!);
      _subPedido = null;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) await TrackingService.parar(userId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Este pedido foi cancelado pelo administrador'),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 4),
    ));
    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimerPedido?.cancel();
    _subProximidade?.cancel();
    if (_subPedido != null) _supabase.removeChannel(_subPedido!);
    FlutterForegroundTask.removeTaskDataCallback(_onDadosForeground);
    ForegroundService.desativarProximidade();
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _avancar() async {
    setState(() { _carregando = true; _erro = null; });
    try {
      switch (_etapa) {
        case EtapaEntrega.aceito:
          if (_lojaLat == null || _lojaLng == null) {
            setState(() => _carregando = false);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Coordenadas da loja não encontradas, contate o suporte'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ));
            return;
          }
          {
            final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
            final coletaLat1 = (widget.pedido['latitude_coleta'] as num?)?.toDouble();
            final coletaLng1 = (widget.pedido['longitude_coleta'] as num?)?.toDouble();
            final targetLat1 = coletaLat1 ?? _lojaLat!;
            final targetLng1 = coletaLng1 ?? _lojaLng!;
            final distM = _calcularDistancia(pos.latitude, pos.longitude, targetLat1, targetLng1) * 1000;
            if (distM > 50) {
              setState(() => _carregando = false);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Você precisa estar a menos de 50 metros da loja (atual: ${distM.toStringAsFixed(0)}m)'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ));
              return;
            }
          }
          await _supabase.from('pedidos').update({
            'status': 'no_local',
            'status_detalhado': 'no_local',
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.chegouLocal);
          HapticFeedback.mediumImpact();
          break;

        case EtapaEntrega.chegouLocal:
          if (_lojaLat == null || _lojaLng == null) {
            setState(() => _carregando = false);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Coordenadas da loja não encontradas, contate o suporte'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ));
            return;
          }
          {
            final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
            final coletaLat2 = (widget.pedido['latitude_coleta'] as num?)?.toDouble();
            final coletaLng2 = (widget.pedido['longitude_coleta'] as num?)?.toDouble();
            final targetLat2 = coletaLat2 ?? _lojaLat!;
            final targetLng2 = coletaLng2 ?? _lojaLng!;
            final distM = _calcularDistancia(pos.latitude, pos.longitude, targetLat2, targetLng2) * 1000;
            if (distM > 50) {
              setState(() => _carregando = false);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Você precisa estar a menos de 50 metros da loja para sair (atual: ${distM.toStringAsFixed(0)}m)'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ));
              return;
            }
          }
          await _supabase.from('pedidos').update({
            'status': 'em_rota',
            'status_detalhado': 'em_rota',
            'em_rota_em': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.emRota);
          _iniciarVerificacaoProximidade();
          _ativarProximidadeForeground();
          HapticFeedback.mediumImpact();
          break;

        case EtapaEntrega.emRota:
          final clienteLat = (widget.pedido['latitude'] ?? widget.pedido['lat']) as num?;
          final clienteLng = (widget.pedido['longitude'] ?? widget.pedido['lng']) as num?;
          if (clienteLat == null || clienteLng == null) {
            setState(() => _carregando = false);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Coordenadas do cliente não encontradas, contate o suporte'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ));
            return;
          }
          {
            final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
            final distM = _calcularDistancia(pos.latitude, pos.longitude, clienteLat.toDouble(), clienteLng.toDouble()) * 1000;
            if (distM > 50) {
              setState(() => _carregando = false);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Você precisa estar a menos de 50 metros do cliente (atual: ${distM.toStringAsFixed(0)}m)'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ));
              return;
            }
          }
          await _supabase.from('pedidos').update({
            'status': 'chegou_destino',
            'status_detalhado': 'chegou_destino',
            'chegou_destino_em': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.chegouDestino);
          HapticFeedback.mediumImpact();
          break;

        case EtapaEntrega.chegouDestino:
          final codigo = _codigoCtrl.text.trim();
          if (codigo.length != 4 || int.tryParse(codigo) == null) {
            setState(() { _erro = 'Digite os 4 dígitos do código'; _carregando = false; });
            return;
          }
          await _supabase.from('pedidos').update({
            'status': 'finalizado',
            'status_detalhado': 'finalizado',
            'finalizado_em': DateTime.now().toIso8601String(),
            'codigo_confirmacao': codigo,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.finalizado);
          HapticFeedback.heavyImpact();
          break;

        case EtapaEntrega.finalizado:
          if (mounted) Navigator.pop(context);
          break;

        default: break;
      }
    } catch (e) {
      setState(() => _erro = 'Erro de conexão. Tente novamente.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _marcarRetornando() async {
    setState(() => _carregando = true);
    try {
      await _supabase.from('pedidos').update({
        'status': 'retornando',
        'status_detalhado': 'retornando',
        'retornando_em': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _pedidoId);
      setState(() => _etapa = EtapaEntrega.retornando);
      HapticFeedback.mediumImpact();
      _iniciarPollingPagamento();
      _iniciarVerificacaoProximidade();
      _ativarProximidadeForeground();
    } catch (e) {
      setState(() => _erro = 'Erro ao marcar retorno.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final numero = widget.pedido['numero'] ?? _pedidoId.substring(0, 6);
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        leading: (_etapa != EtapaEntrega.finalizado && _etapa != EtapaEntrega.retornando && _etapa != EtapaEntrega.aguardandoPagamento)
            ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))
            : null,
        title: Text('Pedido #$numero',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildProgresso(),
            const SizedBox(height: 28),
            _buildCardPedido(),
            const SizedBox(height: 28),
            if (_etapa == EtapaEntrega.retornando) ...[
              _buildRetornando(),
            ] else if (_etapa == EtapaEntrega.finalizado) ...[
              _buildFinalizado(),
            ] else ...[
              if (_etapa != EtapaEntrega.chegouDestino) ...[
                _buildInstrucao(),
                const SizedBox(height: 24),
              ],
              if (_etapa == EtapaEntrega.chegouDestino) ...[
                _buildCampoCodigo(),
                const SizedBox(height: 8),
                if (_erro != null)
                  Text(_erro!, style: const TextStyle(color: Color(0xFFef4444), fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A56DB),
                    side: const BorderSide(color: Color(0xFF1A56DB)),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _carregando ? null : _marcarRetornando,
                  icon: const Icon(Icons.keyboard_return, size: 18),
                  label: const Text('Preciso retornar (maquininha/troco)', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 16),
              ],
              if (_erro != null && _etapa != EtapaEntrega.chegouDestino)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_erro!, style: const TextStyle(color: Color(0xFFef4444), fontSize: 13), textAlign: TextAlign.center),
                ),
              _buildBotao(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgresso() {
    final etapas = ['Aceito', 'No local', 'Em rota', 'No destino', 'Entregue'];
    final atual = _etapa == EtapaEntrega.retornando ? 3 :
                  _etapa == EtapaEntrega.aguardandoPagamento ? 3 :
                  _etapa == EtapaEntrega.finalizado ? 4 : _etapa.index;
    return Row(
      children: List.generate(etapas.length, (i) {
        final feito = i <= atual;
        final isRetornando = _etapa == EtapaEntrega.retornando && i == 3;
        return Expanded(
          child: Row(children: [
            Expanded(child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: isRetornando ? const Color(0xFFf59e0b) : feito ? const Color(0xFF1A56DB) : const Color(0xFF2a2a3e),
                  shape: BoxShape.circle,
                ),
                child: Center(child: isRetornando
                    ? const Icon(Icons.keyboard_return, color: Colors.white, size: 14)
                    : feito && i < atual
                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                        : Text('${i + 1}', style: TextStyle(color: feito ? Colors.white : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(height: 4),
              Text(isRetornando ? 'Retorno' : etapas[i],
                  style: TextStyle(color: isRetornando ? const Color(0xFFf59e0b) : feito ? Colors.white : Colors.grey, fontSize: 10)),
            ])),
            if (i < etapas.length - 1)
              Expanded(child: Container(height: 2, margin: const EdgeInsets.only(bottom: 20), color: i < atual ? const Color(0xFF1A56DB) : const Color(0xFF2a2a3e))),
          ]),
        );
      }),
    );
  }

  Widget _buildCardPedido() {
    final numero = widget.pedido['numero'] ?? _pedidoId.substring(0, 6);
    if (_etapa == EtapaEntrega.aceito || _etapa == EtapaEntrega.chegouLocal) {
      return _buildCardTela1(numero);
    }
    return _buildCardTela2(numero);
  }

  Widget _buildEnderecoClicavel(String endereco, {Color iconColor = const Color(0xFF1A56DB)}) {
    return GestureDetector(
      onTap: () => _abrirMaps(endereco),
      child: Row(children: [
        Icon(Icons.location_on, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(
          endereco,
          style: const TextStyle(
            color: Color(0xFF60a5fa),
            fontSize: 14,
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF60a5fa),
          ),
        )),
        const Icon(Icons.open_in_new, color: Color(0xFF60a5fa), size: 14),
      ]),
    );
  }

  Widget _buildCardTela1(dynamic numero) {
    final loja = widget.pedido['lojas'];
    final nomeLoja = _nomeLoja ?? loja?['nome']?.toString() ?? widget.pedido['nome_loja']?.toString() ?? 'Loja';
    final _endColeta = widget.pedido['endereco_coleta']?.toString() ?? '';
    final enderecoColeta = _endColeta.isNotEmpty ? _endColeta : (_enderecoLoja ?? widget.pedido['endereco_loja']?.toString() ?? '—');
    final observacao = widget.pedido['descricao']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_outlined, color: Colors.white54, size: 16),
          const SizedBox(width: 6),
          Text('Pedido #$numero', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.store, color: Color(0xFF1A56DB), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(nomeLoja, style: const TextStyle(color: Colors.white, fontSize: 14))),
        ]),
        const SizedBox(height: 10),
        const Text('Endereço de coleta:', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        _buildEnderecoClicavel(enderecoColeta),
        if (_distanciaLojaKm != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.route_outlined, color: Colors.white54, size: 16),
            const SizedBox(width: 6),
            Text('${_distanciaLojaKm!.toStringAsFixed(2)} km até o ponto de coleta', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        ],
        if (observacao.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(color: Color(0xFF2A2D35)),
          const SizedBox(height: 4),
          const Text('OBSERVAÇÕES', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Text(observacao, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ]),
    );
  }

  Widget _buildCardTela2(dynamic numero) {
    final endereco = widget.pedido['endereco'] ?? '—';
    final complemento = widget.pedido['complemento']?.toString() ?? '';
    final nomeCliente = widget.pedido['cliente'] ?? '—';
    final telefone = widget.pedido['telefone']?.toString() ?? widget.pedido['telefone_cliente']?.toString() ?? '—';
    final zero800 = widget.pedido['telefone_0800']?.toString() ?? widget.pedido['zero_oitocentos']?.toString() ?? '';
    final observacao = widget.pedido['descricao']?.toString() ?? '';
    final distKm = widget.pedido['distancia_km'];
    final endColeta2 = widget.pedido['endereco_coleta']?.toString() ?? '';
    final enderecoColeta = endColeta2.isNotEmpty ? endColeta2 : (_enderecoLoja ?? widget.pedido['endereco_loja']?.toString() ?? '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_outlined, color: Colors.white54, size: 16),
          const SizedBox(width: 6),
          Text('Pedido #$numero', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        const Divider(color: Color(0xFF2A2D35), height: 20),

        if (enderecoColeta.isNotEmpty) ...[
          const Text('COLETA', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          _buildEnderecoClicavel(enderecoColeta),
          const SizedBox(height: 10),
        ],

        const Text('ENDEREÇO DE ENTREGA', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        _buildEnderecoClicavel(endereco),
        if (complemento.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.info_outline, color: Colors.white38, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(complemento, style: const TextStyle(color: Colors.white70, fontSize: 13))),
          ]),
        ],
        if (distKm != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.straighten, color: Colors.white38, size: 16),
            const SizedBox(width: 6),
            Text('$distKm km da loja ao cliente', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ],
        const Divider(color: Color(0xFF2A2D35), height: 20),
        Row(children: [
          const Icon(Icons.person_outline, color: Colors.white54, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(nomeCliente, style: const TextStyle(color: Colors.white, fontSize: 14))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.phone_outlined, color: Colors.white54, size: 16),
          const SizedBox(width: 6),
          Text(telefone, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ]),
        if (zero800.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.support_agent_outlined, color: Colors.white54, size: 16),
            const SizedBox(width: 6),
            Text(zero800, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ],
        if (observacao.isNotEmpty) ...[
          const Divider(color: Color(0xFF2A2D35), height: 20),
          const Text('OBSERVAÇÕES', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Text(observacao, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ]),
    );
  }

  Widget _buildInstrucao() {
    final config = {
      EtapaEntrega.aceito:      (Icons.store_outlined,        'Vá buscar o pedido',       'Dirija-se ao estabelecimento',      const Color(0xFF1A56DB)),
      EtapaEntrega.chegouLocal: (Icons.inventory_2_outlined,  'Chegou no local?',         'Pegue o pedido e confirme',         const Color(0xFF1A56DB)),
      EtapaEntrega.emRota:      (Icons.directions_bike,        'A caminho do cliente',     'Confirme a chegada ao destino',     const Color(0xFF1A56DB)),
      EtapaEntrega.chegouDestino: (Icons.location_on,          'Chegou no destino!',       'Peça o código de confirmação',      const Color(0xFF1A56DB)),
    };
    final entry = config[_etapa];
    if (entry == null) return const SizedBox.shrink();
    final (icon, titulo, sub, cor) = entry;
    return Column(children: [
      Icon(icon, color: cor, size: 52),
      const SizedBox(height: 12),
      Text(titulo, style: TextStyle(color: cor, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
    ]);
  }

  Widget _buildCampoCodigo() {
    return Column(children: [
      TextField(
        controller: _codigoCtrl,
        keyboardType: TextInputType.number,
        maxLength: 4,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 16),
        decoration: InputDecoration(
          counterText: '',
          hintText: '0000',
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 36, letterSpacing: 16),
          filled: true, fillColor: const Color(0xFF161820),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1A56DB))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2A2D35))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1A56DB), width: 2)),
        ),
      ),
      const SizedBox(height: 8),
      const Text('Peça ao cliente para mostrar o código', style: TextStyle(color: Colors.white38, fontSize: 12)),
    ]);
  }

  Widget _buildBotao() {
    final config = {
      EtapaEntrega.aceito:         (const Color(0xFF1A56DB), 'Cheguei no local',    Icons.store),
      EtapaEntrega.chegouLocal:    (const Color(0xFF1A56DB), 'Saí para entregar',   Icons.moped),
      EtapaEntrega.emRota:         (const Color(0xFF1A56DB), 'Cheguei no destino',  Icons.location_on),
      EtapaEntrega.chegouDestino:  (const Color(0xFF1A56DB), 'Finalizar entrega',   Icons.check_circle),
      EtapaEntrega.finalizado:     (const Color(0xFF1A56DB), 'Voltar para pedidos', Icons.list_alt),
    };
    final (cor, label, icon) = config[_etapa] ?? (const Color(0xFF1A56DB), 'Voltar', Icons.list_alt);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: cor, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: _carregando ? null : _avancar,
        child: _carregando
            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 20), const SizedBox(width: 10),
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
      ),
    );
  }

  Widget _buildRetornando() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x101A56DB),
        border: Border.all(color: const Color(0xFF1A56DB), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(children: [
        Icon(Icons.keyboard_return, color: Color(0xFF1A56DB), size: 52),
        SizedBox(height: 12),
        Text('Aguardando confirmação', style: TextStyle(color: Color(0xFF1A56DB), fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('Você marcou este pedido como retorno.\nA loja precisa confirmar o pagamento para finalizar.',
            style: TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
        SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFF1A56DB), strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Aguardando loja...', style: TextStyle(color: Color(0xFF1A56DB), fontSize: 13)),
        ]),
      ]),
    );
  }

  Widget _buildFinalizado() {
    final gorjeta = (widget.pedido['gorjeta'] as num?)?.toDouble() ?? 0;
    final taxa = (widget.pedido['taxa_motoboy'] as num?)?.toDouble() ?? (widget.pedido['taxa_entrega'] as num?)?.toDouble() ?? 0;
    final totalMotoboy = taxa + gorjeta + _precoDinamico;

    return Column(children: [
      const Icon(Icons.check_circle, color: Color(0xFF1A56DB), size: 90),
      const SizedBox(height: 16),
      const Text('Entrega finalizada!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Pedido entregue com sucesso', style: TextStyle(color: Colors.white54, fontSize: 14)),
      if (totalMotoboy > 0) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x1022c55e),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x4022c55e)),
          ),
          child: Text('💰 Total a receber: R\$ ${totalMotoboy.toStringAsFixed(2)}',
              style: const TextStyle(color: Color(0xFF22c55e), fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A56DB), foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PedidosAceitosScreen())),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.list_alt, size: 20), SizedBox(width: 8),
            Text('Voltar para pedidos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    ]);
  }
}