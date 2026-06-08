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
  bool _carregando = true;
  bool _disponivel = true;
  Timer? _timer;
  RealtimeChannel? _channel;
  RealtimeChannel? _channelRota;

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
    _buscar();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
    _assinarRealtime();
    _assinarRealtimeRota();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.unsubscribe();
    _channelRota?.unsubscribe();
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

      final results = await Future.wait([
        _supabase
            .from('pedidos')
            .select('*, lojas(nome, endereco, latitude, longitude)')
            .inFilter('status', ['pronto'])
            .or('motoboy_id.is.null,motoboy_id.eq.${user.id}')
            .order('pronto_em', ascending: true),
        _supabase
            .from('configuracoes')
            .select('valor')
            .eq('chave', 'preco_dinamico_entregador')
            .maybeSingle(),
      ]);

      final lista = List<Map<String, dynamic>>.from(results[0] as List);
      final precoDinamico = double.tryParse(
              (results[1] as Map<String, dynamic>?)?['valor']?.toString() ?? '0') ??
          0.0;

      final idsConhecidos = _pedidos.map((p) => p['id']).toSet();
      final novos = lista.where((p) => !idsConhecidos.contains(p['id'])).toList();
      if (novos.isNotEmpty) {
        _tocarNotificacao();
      }

      if (mounted) {
        setState(() {
          _pedidos = lista;
          _precoDinamico = precoDinamico;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
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
            final novo = payload.newRecord;
            final status = novo['status']?.toString() ?? '';
            if (status == 'pronto') {
              _buscar();
            }
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
            final motoboyId = novo['motoboy_id']?.toString();
            final uid = _supabase.auth.currentUser?.id;

            if (novoStatus == 'pronto' &&
                (motoboyId == null || motoboyId.isEmpty)) {
              _buscar();
            } else if (novoStatus != 'pronto' ||
                (motoboyId != null &&
                    motoboyId.isNotEmpty &&
                    motoboyId != uid)) {
              if (mounted && id.isNotEmpty) {
                setState(() => _pedidos.removeWhere((p) => p['id'] == id));
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

  @override
  Widget build(BuildContext context) {
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
          if (_pedidos.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFF1A56DB),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${_pedidos.length}',
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
                if (_rotaAtual != null) _buildCardRota(_rotaAtual!),
                Expanded(
                  child: _pedidos.isEmpty
                      ? _buildVazio()
                      : RefreshIndicator(
                          onRefresh: _buscar,
                          color: const Color(0xFF1A56DB),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _pedidos.length,
                            itemBuilder: (_, i) => _buildCard(_pedidos[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildCardRota(Map<String, dynamic> rota) {
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

  Widget _buildCard(Map<String, dynamic> pedido) {
    final gorjeta = double.tryParse(pedido['gorjeta']?.toString() ?? '0') ?? 0;
    final taxaFinal = _calcTaxaMotoboy(pedido);
    final taxaBase = taxaFinal - gorjeta - _precoDinamico;
    final temBonus = gorjeta > 0 || _precoDinamico > 0;

    final numero = pedido['numero'] ?? pedido['id'].toString().substring(0, 6);
    final pontos = pedido['pontos'] ?? 4;
    final distanciaKm =
        double.tryParse(pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final comRetorno = pedido['com_retorno'] == true;
    final taxaSemRetorno = comRetorno
        ? th.calcularTaxaMotoboy(distanciaKm, false, th.faixasGlobais) + _precoDinamico + gorjeta
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

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RotaDisponivelScreen(pedido: pedido))).then((_) => _buscar()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF161820),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2D35)),
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
                      color: const Color(0xFF1A56DB).withOpacity(0.18),
                      border: Border.all(color: const Color(0xFF1A56DB)),
                    ),
                    child: const Text('RETORNO',
                        style: TextStyle(
                            color: Color(0xFF1A56DB),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
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
              ] else if (temBonus) ...[
                Text('R\$${taxaBase.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.white38,
                    )),
                const SizedBox(width: 8),
              ],
              Text('R\$${taxaFinal.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: comRetorno
                          ? const Color(0xFF10b981)
                          : _precoDinamico > 0
                              ? Colors.red
                              : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
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