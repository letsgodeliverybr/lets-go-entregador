import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../services/notification_service.dart';
import 'pedidos_aceitos_screen.dart';

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
  Timer? _timer;
  RealtimeChannel? _channel;

  final Set<String> _idsConhecidos = {};
  bool _primeiraCarregada = true;

  Position? _posicaoAtual;
  double _precoDinamico = 0.0;

  @override
  void initState() {
    super.initState();
    _obterPosicao();
    _buscar();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
    _assinarRealtime();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.unsubscribe();
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
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final results = await Future.wait([
        _supabase
            .from('pedidos')
            .select('*, lojas(nome, latitude, longitude)')
            .inFilter('status', ['pronto'])
            .not('status', 'in', '("finalizado","cancelado")')
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

      if (!_primeiraCarregada) {
        for (final p in lista) {
          final id = p['id'].toString();
          if (!_idsConhecidos.contains(id)) {
            await _tocarNotificacao();
            break;
          }
        }
      }

      for (final p in lista) {
        _idsConhecidos.add(p['id'].toString());
      }
      _primeiraCarregada = false;

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
    // Notificação local (funciona em foreground e background)
    NotificationService.showNovoPedidoLocal().catchError((_) {});

    // Vibração imediata
    HapticFeedback.heavyImpact();

    // Tocar letsgo.wav 7 vezes em sequência (foreground)
    for (int i = 0; i < 7; i++) {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setAsset('assets/sounds/letsgo.wav');
        await _audioPlayer.play();
        await _audioPlayer.playerStateStream.firstWhere(
          (s) => s.processingState == ProcessingState.completed,
        );
      } catch (_) {
        break;
      }
    }
  }

  void _assinarRealtime() {
    _channel = _supabase.channel('pedidos-disp-realtime').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'pedidos',
      callback: (payload) {
        final status = payload.newRecord['status']?.toString() ?? '';
        if (status == 'pronto') {
          _tocarNotificacao();
          _buscar();
        }
      },
    ).onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'pedidos',
      callback: (payload) {
        final novo = payload.newRecord['status']?.toString() ?? '';
        final antigo = payload.oldRecord['status']?.toString() ?? '';
        if (novo == 'pronto' && antigo != 'pronto') {
          _tocarNotificacao();
        }
        _buscar();
      },
    ).subscribe();
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
          : _pedidos.isEmpty
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
    );
  }

  Widget _buildCard(Map<String, dynamic> pedido) {
    final taxa = double.tryParse(pedido['taxa_entrega']?.toString() ?? '0') ?? 0;
    final gorjeta = double.tryParse(pedido['gorjeta']?.toString() ?? '0') ?? 0;
    final taxaFinal = taxa + gorjeta + _precoDinamico;
    final temBonus = gorjeta > 0 || _precoDinamico > 0;

    final numero = pedido['numero'] ?? pedido['id'].toString().substring(0, 6);
    final pontos = pedido['pontos'] ?? 4;
    final distanciaKm =
        double.tryParse(pedido['distancia_km']?.toString() ?? '0') ?? 0;
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
      onTap: () => _aceitar(pedido),
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
            // Linha 1: ícone loja + nome + número
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

            // Linha 2: distância até a loja
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

            // Linha 3: pontos
            Row(children: [
              const Icon(Icons.star_border, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text('$pontos pontos',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
            const SizedBox(height: 8),

            // Linha 4: tag Bag térmica
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white),
              ),
              child: const Text('Bag térmica',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),

            const SizedBox(height: 12),

            // Linha 5: distância percurso + valor
            Row(children: [
              const Icon(Icons.route_outlined, color: Colors.white70, size: 16),
              const SizedBox(width: 4),
              Text('${distanciaKm.toStringAsFixed(2)} km',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              if (temBonus) ...[
                Text('R\$${taxa.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.red,
                    )),
                const SizedBox(width: 8),
              ],
              Text('R\$${taxaFinal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ]),
          ],
          ),
        ),
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