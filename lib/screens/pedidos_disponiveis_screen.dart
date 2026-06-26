import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../services/notification_service.dart';
import '../utils/taxa_helper.dart' as th;
import 'pedidos_aceitos_screen.dart';
import 'rota_disponivel_screen.dart';

class PedidosDisponiveisScreen extends StatefulWidget {
  const PedidosDisponiveisScreen({super.key});
  @override
  State<PedidosDisponiveisScreen> createState() => _State();
}

class _State extends State<PedidosDisponiveisScreen> {
  final _supabase = Supabase.instance.client;
  final _audioPlayer = AudioPlayer();
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _rotasAgrupadas = [];
  bool _carregando = true;
  bool _disponivel = true;
  String _modoDespacho = 'todos';
  final Map<String, int> _contadores = {};
  final Map<String, Timer> _timersContadores = {};
  Timer? _timer;
  RealtimeChannel? _channel;
  RealtimeChannel? _channelRota;
  RealtimeChannel? _channelDespachoFila;

  Map<String, dynamic>? _rotaAtual;

  Position? _posicaoAtual;
  double _precoDinamico = 0.0;

  double _calcTaxaMotoboy(Map<String, dynamic> pedido) {
    final km = double.tryParse(pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final gorjeta = double.tryParse(pedido['gorjeta']?.toString() ?? '0') ?? 0;
    final temRetorno = pedido['com_retorno'] == true || pedido['retorno'] == true;
    double base = th.calcularTaxaMotoboy(km, temRetorno, th.faixasGlobais);
    return base + _precoDinamico + gorjeta;
  }

  @override
  void initState() {
    super.initState();
    _obterPosicao();
    th.carregarFaixas();
    _verificarEIniciar();
  }

  Future<void> _verificarEIniciar() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _carregando = false);
      return;
    }
    try {
      final e = await _supabase
          .from('entregadores')
          .select('disponivel')
          .eq('id', user.id)
          .single();
      final online = e['disponivel'] == true;
      if (!mounted) return;
      setState(() {
        _disponivel = online;
        if (!online) _carregando = false;
      });
      if (!online) return;
    } catch (_) {
      if (mounted) setState(() { _disponivel = false; _carregando = false; });
      return;
    }
    await _buscar();
    _assinarRealtimeRota();
    _assinarRealtimeDespachoFila();
    if (_modoDespacho != 'sequencial') {
      _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
      _assinarRealtime();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final t in _timersContadores.values) { t.cancel(); }
    _timersContadores.clear();
    _channel?.unsubscribe();
    _channelRota?.unsubscribe();
    _channelDespachoFila?.unsubscribe();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _obterPosicao() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) setState(() => _posicaoAtual = last);
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _posicaoAtual = pos);
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

  Future<void> _buscar() async {
    if (!_disponivel) return;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final configs = await Future.wait([
        _supabase
            .from('configuracoes')
            .select('valor')
            .eq('chave', 'modo_despacho')
            .maybeSingle(),
        _supabase
            .from('configuracoes')
            .select('valor')
            .eq('chave', 'preco_dinamico_entregador')
            .maybeSingle(),
      ]);

      final modoDespacho =
          (configs[0] as Map<String, dynamic>?)?['valor']?.toString() ?? 'todos';
      final precoDinamico = double.tryParse(
              (configs[1] as Map<String, dynamic>?)?['valor']?.toString() ?? '0') ??
          0.0;

      List<Map<String, dynamic>> lista;

      if (modoDespacho == 'sequencial') {
        // ── Pedidos individuais (sem rota agrupada) ──────────────────────────
        final filaIndividual = await _supabase
            .from('despacho_fila')
            .select('pedido_id')
            .eq('entregador_id', user.id)
            .eq('status', 'aguardando')
            .isFilter('rota_agrupada_id', null);

        final pedidoIds = (filaIndividual as List)
            .map((f) => f['pedido_id']?.toString())
            .whereType<String>()
            .toList();

        if (pedidoIds.isEmpty) {
          lista = [];
        } else {
          lista = List<Map<String, dynamic>>.from(
            await _supabase
                .from('pedidos')
                .select('*, lojas(nome, endereco, latitude, longitude)')
                .inFilter('id', pedidoIds)
                .eq('status', 'pronto'),
          );
          final idsValidos = lista.map((p) => p['id'].toString()).toSet();
          final idsInvalidos = pedidoIds.where((id) => !idsValidos.contains(id)).toList();
          for (final id in idsInvalidos) {
            _supabase
                .from('despacho_fila')
                .update({'status': 'expirado'})
                .eq('pedido_id', id)
                .eq('entregador_id', user.id)
                .eq('status', 'aguardando')
                .then((_) {});
          }
        }

        // ── Rotas agrupadas ──────────────────────────────────────────────────
        final filaRotas = await _supabase
            .from('despacho_fila')
            .select('id, pedido_id, rota_agrupada_id')
            .eq('entregador_id', user.id)
            .eq('status', 'aguardando')
            .not('rota_agrupada_id', 'is', null);

        final idsRotasConhecidas = _rotasAgrupadas
            .map((r) => r['rota_agrupada_id']?.toString())
            .toSet();

        final novasRotas = <Map<String, dynamic>>[];
        for (final filaRota in filaRotas as List) {
          final rotaId = filaRota['rota_agrupada_id']?.toString();
          if (rotaId == null) continue;
          try {
            final rotaData = await _supabase
                .from('rotas_agrupadas')
                .select('*')
                .eq('id', rotaId)
                .maybeSingle();
            if (rotaData == null) continue;

            final pedidoIdsRota = (rotaData['pedido_ids'] as List? ?? [])
                .map((id) => id.toString())
                .toList();
            final pedidosRota = pedidoIdsRota.isEmpty
                ? <Map<String, dynamic>>[]
                : List<Map<String, dynamic>>.from(
                    await _supabase
                        .from('pedidos')
                        .select('*, lojas(nome, endereco, latitude, longitude)')
                        .inFilter('id', pedidoIdsRota),
                  );

            novasRotas.add({
              'rota_agrupada_id': rotaId,
              'fila_id': filaRota['id'].toString(),
              'rota': rotaData,
              'pedidos': pedidosRota,
            });

            if (!idsRotasConhecidas.contains(rotaId)) {
              _tocarNotificacao();
              _iniciarContadorRota(rotaId, filaRota['id'].toString());
            }
          } catch (e) {
            debugPrint('Erro ao buscar rota $rotaId: $e');
          }
        }

        if (mounted) setState(() => _rotasAgrupadas = novasRotas);
      } else {
        lista = List<Map<String, dynamic>>.from(
          await _supabase
              .from('pedidos')
              .select('*, lojas(nome, endereco, latitude, longitude)')
              .inFilter('status', ['pronto'])
              .or('motoboy_id.is.null,motoboy_id.eq.${user.id}')
              .order('pronto_em', ascending: true),
        );
      }

      final idsConhecidos = _pedidos.map((p) => p['id']).toSet();
      final novos = lista.where((p) => !idsConhecidos.contains(p['id'])).toList();
      if (novos.isNotEmpty) {
        _tocarNotificacao();
        if (modoDespacho == 'sequencial') {
          for (final pedido in novos) {
            _iniciarContador(pedido['id'].toString());
          }
        }
      }

      if (mounted) {
        setState(() {
          _pedidos = lista;
          _precoDinamico = precoDinamico;
          _modoDespacho = modoDespacho;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _iniciarContador(String pedidoId) {
    _timersContadores[pedidoId]?.cancel();
    if (mounted) setState(() => _contadores[pedidoId] = 29);
    _timersContadores[pedidoId] = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) { t.cancel(); return; }
      final atual = (_contadores[pedidoId] ?? 0) - 1;
      if (atual <= 0) {
        t.cancel();
        _timersContadores.remove(pedidoId);
        if (mounted) setState(() => _contadores.remove(pedidoId));
        final user = _supabase.auth.currentUser;
        if (user != null) {
          try {
            await _supabase
                .from('despacho_fila')
                .update({'status': 'expirado'})
                .eq('pedido_id', pedidoId)
                .eq('entregador_id', user.id)
                .eq('status', 'aguardando');
          } catch (e) {
            debugPrint('Erro ao expirar despacho_fila: $e');
          }
        }
        if (mounted) {
          setState(() => _pedidos.removeWhere((p) => p['id'].toString() == pedidoId));
        }
      } else {
        if (mounted) setState(() => _contadores[pedidoId] = atual);
      }
    });
  }

  void _iniciarContadorRota(String rotaId, String filaId) {
    final key = 'rota_$rotaId';
    _timersContadores[key]?.cancel();
    if (mounted) setState(() => _contadores[key] = 29);
    _timersContadores[key] = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) { t.cancel(); return; }
      final atual = (_contadores[key] ?? 0) - 1;
      if (atual <= 0) {
        t.cancel();
        _timersContadores.remove(key);
        if (mounted) setState(() => _contadores.remove(key));
        final user = _supabase.auth.currentUser;
        if (user != null) {
          try {
            await _supabase
                .from('despacho_fila')
                .update({'status': 'expirado'})
                .eq('id', filaId)
                .eq('status', 'aguardando');
          } catch (e) {
            debugPrint('Erro ao expirar despacho_fila rota: $e');
          }
        }
        if (mounted) {
          setState(() => _rotasAgrupadas.removeWhere((r) => r['rota_agrupada_id'] == rotaId));
        }
      } else {
        if (mounted) setState(() => _contadores[key] = atual);
      }
    });
  }

  Future<void> _tocarNotificacao() async {
    NotificationService.showNovoPedidoLocal().catchError((e) {
      debugPrint('Notificação falhou: $e');
    });
    HapticFeedback.heavyImpact();
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setAudioSource(
        ConcatenatingAudioSource(
          children: List.generate(
            2,
            (_) => AudioSource.asset('assets/sounds/letsgo.wav'),
          ),
        ),
      );
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('Áudio falhou: $e');
    }
  }

  Future<void> _tocarNotificacaoRota() async {
    NotificationService.showNovaRotaLocal().catchError((e) {
      debugPrint('Notificação rota falhou: $e');
    });
    HapticFeedback.heavyImpact();
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setAudioSource(
        ConcatenatingAudioSource(
          children: List.generate(
            2,
            (_) => AudioSource.asset('assets/sounds/letsgo.wav'),
          ),
        ),
      );
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('Áudio rota falhou: $e');
    }
  }

  void _assinarRealtime() {
    _channel?.unsubscribe();
    _channel = _supabase
        .channel('pedidos-disp-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pedidos',
          callback: (payload) {
            final status = payload.newRecord['status']?.toString() ?? '';
            if (status == 'pronto') _buscar();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pedidos',
          callback: (payload) {
            final novo = payload.newRecord;
            final novoStatus = novo['status']?.toString() ?? '';
            final id = novo['id']?.toString() ?? '';
            if (id.isEmpty) return;
            if (novoStatus == 'pronto') {
              _buscar();
            } else {
              if (mounted) {
                setState(() => _pedidos.removeWhere((p) => p['id']?.toString() == id));
              }
            }
          },
        )
        .subscribe();
  }

  void _assinarRealtimeRota() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _channelRota = _supabase
        .channel('entregador-rota-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'entregadores',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: user.id,
          ),
          callback: (payload) async {
            final novoRegistro = payload.newRecord;
            final antigoRegistro = payload.oldRecord;
            final novaNotif = novoRegistro['notificacao_rota'];
            final antigaNotif = antigoRegistro['notificacao_rota'];
            if (novaNotif != null && novaNotif.toString() != antigaNotif?.toString()) {
              await _tocarNotificacaoRota();
              try {
                final rota = await _supabase
                    .from('rotas')
                    .select()
                    .eq('id', novaNotif.toString())
                    .maybeSingle();
                if (mounted && rota != null) {
                  setState(() => _rotaAtual = rota);
                }
              } catch (e) {
                debugPrint('Erro ao buscar rota: $e');
              }
            }
          },
        )
        .subscribe();
  }

  void _assinarRealtimeDespachoFila() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _channelDespachoFila = _supabase
        .channel('despacho-fila-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'despacho_fila',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'entregador_id',
            value: user.id,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            final status = record['status']?.toString() ?? '';
            if (status == 'aguardando') {
              await _tocarNotificacao();
              _buscar();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'despacho_fila',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'entregador_id',
            value: user.id,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            final status = record['status']?.toString() ?? '';
            final pedidoId = record['pedido_id']?.toString() ?? '';
            final rotaId = record['rota_agrupada_id']?.toString();
            if (status != 'aguardando' && mounted) {
              if (rotaId != null && rotaId.isNotEmpty) {
                final key = 'rota_$rotaId';
                _timersContadores[key]?.cancel();
                _timersContadores.remove(key);
                setState(() {
                  _contadores.remove(key);
                  _rotasAgrupadas.removeWhere((r) => r['rota_agrupada_id'] == rotaId);
                });
              } else if (pedidoId.isNotEmpty) {
                _timersContadores[pedidoId]?.cancel();
                _timersContadores.remove(pedidoId);
                setState(() {
                  _contadores.remove(pedidoId);
                  _pedidos.removeWhere((p) => p['id']?.toString() == pedidoId);
                });
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _aceitar(Map<String, dynamic> pedido) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final result = await _supabase
          .from('pedidos')
          .update({
            'status': 'aceito',
            'status_detalhado': 'aceito',
            'aceito_em': DateTime.now().toIso8601String(),
            'motoboy_id': user.id,
            'entregador_id': user.id,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('status', 'pronto')
          .eq('id', pedido['id'])
          .select();

      if (!mounted) return;
      if (result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pedido já foi aceito por outro entregador'),
          backgroundColor: Colors.red,
        ));
        _buscar();
        return;
      }

      if (_modoDespacho == 'sequencial') {
        final pedidoId = pedido['id'].toString();
        _timersContadores[pedidoId]?.cancel();
        _timersContadores.remove(pedidoId);
        if (mounted) setState(() => _contadores.remove(pedidoId));
        try {
          await _supabase
              .from('despacho_fila')
              .update({'status': 'aceito'})
              .eq('pedido_id', pedido['id'])
              .eq('entregador_id', user.id)
              .eq('status', 'aguardando');
        } catch (e) {
          debugPrint('Erro ao atualizar despacho_fila: $e');
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PedidosAceitosScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _aceitarRota(Map<String, dynamic> rotaData) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final rotaId = rotaData['rota_agrupada_id'].toString();
    final filaId = rotaData['fila_id'].toString();
    final pedidos = List<Map<String, dynamic>>.from(rotaData['pedidos'] as List);

    try {
      final agora = DateTime.now().toIso8601String();

      for (final pedido in pedidos) {
        await _supabase.from('pedidos').update({
          'status': 'aceito',
          'status_detalhado': 'aceito',
          'aceito_em': agora,
          'motoboy_id': user.id,
          'entregador_id': user.id,
          'updated_at': agora,
        }).eq('id', pedido['id']).eq('status', 'pronto');
      }

      await _supabase.from('rotas_agrupadas')
          .update({'status': 'aceita'})
          .eq('id', rotaId);

      await _supabase.from('despacho_fila')
          .update({'status': 'aceito'})
          .eq('id', filaId);

      final key = 'rota_$rotaId';
      _timersContadores[key]?.cancel();
      _timersContadores.remove(key);
      if (mounted) setState(() => _contadores.remove(key));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PedidosAceitosScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao aceitar rota: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalItens = _pedidos.length + _rotasAgrupadas.length;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(children: [
          const Text('Disponíveis',
              style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          if (totalItens > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFF1A56DB),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('$totalItens',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _buscar),
        ],
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : !_disponivel
              ? _buildOffline()
              : Column(
              children: [
                if (_rotaAtual != null) _buildBannerRota(_rotaAtual!),
                Expanded(
                  child: totalItens == 0
                      ? _buildVazio()
                      : RefreshIndicator(
                          onRefresh: _buscar,
                          color: const Color(0xFF1A56DB),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: totalItens,
                            itemBuilder: (_, i) {
                              if (i < _rotasAgrupadas.length) {
                                return _buildCardRotaAgrupada(_rotasAgrupadas[i]);
                              }
                              return _buildCard(_pedidos[i - _rotasAgrupadas.length]);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  // Banner de rota manual atribuída pelo admin (tabela 'rotas')
  Widget _buildBannerRota(Map<String, dynamic> rota) {
    final pedidoIds = (rota['pedido_ids'] as List?)?.length ?? 0;
    return GestureDetector(
      onTap: () => setState(() => _rotaAtual = null),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A56DB), Color(0xFF0E3A99)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A56DB).withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          const Icon(Icons.route, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🛵 Rota Disponível!',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('$pedidoIds entregas agrupadas para você',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.close, color: Colors.white54, size: 20),
        ]),
      ),
    );
  }

  // Card de rota agrupada pelo roterizador automático
  Widget _buildCardRotaAgrupada(Map<String, dynamic> rotaData) {
    final rota = rotaData['rota'] as Map<String, dynamic>;
    final pedidos = List<Map<String, dynamic>>.from(rotaData['pedidos'] as List);
    final rotaId = rotaData['rota_agrupada_id'].toString();
    final key = 'rota_$rotaId';
    final segundosRestantes = _contadores[key];

    final nomeLoja = pedidos.isNotEmpty
        ? (pedidos[0]['lojas']?['nome'] ?? 'Estabelecimento')
        : 'Estabelecimento';
    final valorTotal = (rota['valor_total'] as num?)?.toDouble() ?? 0.0;
    final distanciaTotal = pedidos.fold<double>(
      0.0,
      (sum, p) => sum + (double.tryParse(p['distancia_km']?.toString() ?? '0') ?? 0),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: segundosRestantes != null && segundosRestantes <= 10
              ? Colors.orange
              : const Color(0xFF1A56DB),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A56DB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.route, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nomeLoja,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '🗺️ ${pedidos.length} entregas agrupadas',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              if (segundosRestantes != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: segundosRestantes <= 10 ? Colors.red : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${segundosRestantes}s',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ]),

            const SizedBox(height: 12),
            const Divider(color: Color(0xFF2A2D35)),
            const SizedBox(height: 8),

            // Endereços de entrega
            ...pedidos.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              final endereco = p['endereco_entrega']?.toString()
                  ?? p['endereco']?.toString()
                  ?? '—';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A56DB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(endereco,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              );
            }),

            const SizedBox(height: 8),

            // Distância + valor
            Row(children: [
              const Icon(Icons.route_outlined, color: Colors.white54, size: 16),
              const SizedBox(width: 4),
              Text('${distanciaTotal.toStringAsFixed(2)} km total',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const Spacer(),
              Text(
                'R\$${valorTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ]),

            const SizedBox(height: 12),

            // Botão aceitar rota
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _aceitarRota(rotaData),
                icon: const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 18),
                label: const Text('Aceitar Rota',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A56DB),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> pedido) {
    final gorjeta = double.tryParse(pedido['gorjeta']?.toString() ?? '0') ?? 0;
    final distanciaKm =
        double.tryParse(pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final comRetorno = pedido['com_retorno'] == true;
    final taxaBase = th.calcularTaxaMotoboy(distanciaKm, comRetorno, th.faixasGlobais);
    final taxaMotoboySalvo = (pedido['taxa_motoboy'] as num?)?.toDouble() ?? taxaBase;
    final rawPd = taxaMotoboySalvo - taxaBase;
    final pdSalvo = rawPd >= 0.05 ? rawPd : 0.0;
    final taxaFinal = taxaBase + gorjeta + pdSalvo;

    final numero = pedido['numero'] ?? pedido['id'].toString().substring(0, 6);
    final pontos = pedido['pontos'] ?? 4;
    final taxaSemRetorno = comRetorno
        ? th.calcularTaxaMotoboy(distanciaKm, false, th.faixasGlobais) + pdSalvo + gorjeta
        : 0.0;
    final loja = pedido['lojas'];
    final nomeLoja = loja?['nome'] ?? 'Estabelecimento';

    double distMotoboyLoja = 0;
    if (_posicaoAtual != null &&
        loja != null &&
        loja['latitude'] != null &&
        loja['longitude'] != null) {
      distMotoboyLoja = _calcularDistancia(
        _posicaoAtual!.latitude,
        _posicaoAtual!.longitude,
        (loja['latitude'] as num).toDouble(),
        (loja['longitude'] as num).toDouble(),
      );
    }

    final pedidoId = pedido['id'].toString();
    final segundosRestantes = _contadores[pedidoId];
    final isSequencial = _modoDespacho == 'sequencial';

    return GestureDetector(
      onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => RotaDisponivelScreen(pedido: pedido)))
          .then((_) => _buscar()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF161820),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSequencial && segundosRestantes != null && segundosRestantes <= 10
                ? Colors.orange
                : const Color(0xFF2A2D35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A56DB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.store, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(nomeLoja,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                if (isSequencial && segundosRestantes != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: segundosRestantes <= 10 ? Colors.red : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${segundosRestantes}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text('#$numero',
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
              const SizedBox(height: 10),

              Row(children: [
                const Icon(Icons.location_on, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  distMotoboyLoja > 0
                      ? '${distMotoboyLoja.toStringAsFixed(2)} km de onde você está'
                      : '— km de onde você está',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ]),
              const SizedBox(height: 8),

              Row(children: [
                const Icon(Icons.star_border, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text('$pontos pontos',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ]),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white),
                    ),
                    child: const Text('Bag térmica',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  if (comRetorno)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white),
                      ),
                      child: const Text('RETORNO',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              Row(children: [
                const Icon(Icons.route_outlined, color: Color(0xFFFFFFFF), size: 16),
                const SizedBox(width: 4),
                Text('${distanciaKm.toStringAsFixed(2)} km',
                    style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13)),
                const Spacer(),
                if (comRetorno) ...[
                  Text('R\$${taxaSemRetorno.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.red,
                      )),
                  const SizedBox(width: 8),
                ] else if (pdSalvo > 0) ...[
                  Text('R\$${taxaBase.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.red,
                      )),
                  const SizedBox(width: 8),
                ] else if (gorjeta > 0) ...[
                  Text('R\$${taxaBase.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.white38,
                      )),
                  const SizedBox(width: 8),
                ],
                Text(
                  pdSalvo > 0
                      ? 'R\$${(taxaBase + pdSalvo).toStringAsFixed(2)}'
                      : 'R\$${taxaFinal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOffline() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, color: Colors.grey.shade700, size: 72),
          const SizedBox(height: 20),
          const Text(
            'Fique online para ver pedidos disponíveis',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          const Text(
            'Ative o modo online na tela inicial para começar a receber pedidos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748b), fontSize: 13, height: 1.5),
          ),
        ]),
      ),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.moped_outlined, color: Colors.grey.shade700, size: 72),
        const SizedBox(height: 16),
        const Text('Nenhum pedido disponível',
            style: TextStyle(color: Colors.grey, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Novos pedidos aparecerão aqui automaticamente',
            style: TextStyle(color: Color(0xFF555555), fontSize: 13)),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: _buscar,
          icon: const Icon(Icons.refresh, color: Color(0xFF1A56DB)),
          label: const Text('Atualizar',
              style: TextStyle(color: Color(0xFF1A56DB))),
        ),
      ]),
    );
  }
}
