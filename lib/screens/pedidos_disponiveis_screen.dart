import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';
import 'entrega_screen.dart';

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

  // Controle de IDs já exibidos para detectar novidades
  final Set<String> _idsConhecidos = {};
  bool _primeiraCarregada = true;

  Position? _posicaoAtual;

  @override
  void initState() {
    super.initState();
    _obterPosicao();
    _buscar();
    // Polling como fallback (8s)
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
    // Realtime — toca som ao INSERT de pedido novo
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
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() => _posicaoAtual = pos);
    } catch (_) {}
  }

  double _calcularDistancia(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── busca pedidos com status 'pronto' (exclui finalizado/cancelado) ──────
  Future<void> _buscar() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('pedidos')
          .select('*, lojas(nome, latitude, longitude)')
          .inFilter('status', ['pronto']) // garante que finalizado/cancelado nunca entram
          .not('status', 'in', '("finalizado","cancelado")')
          .or('motoboy_id.is.null,motoboy_id.eq.${user.id}')
          .order('pronto_em', ascending: true);

      final lista = List<Map<String, dynamic>>.from(data);

      // Detecta novidades (ignora na primeira carga para não tocar ao abrir)
      if (!_primeiraCarregada) {
        for (final p in lista) {
          final id = p['id'].toString();
          if (!_idsConhecidos.contains(id)) {
            await _tocarNotificacao();
            break; // toca só uma vez por lote
          }
        }
      }

      // Atualiza set de IDs conhecidos
      for (final p in lista) {
        _idsConhecidos.add(p['id'].toString());
      }
      _primeiraCarregada = false;

      if (mounted) {
        setState(() {
          _pedidos = lista;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  // ── toca ringtone + vibra ─────────────────────────────────────────────────
  Future<void> _tocarNotificacao() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setAsset('assets/sounds/novo_pedido.mp3');
      await _audioPlayer.play();
    } catch (_) {}
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 300));
    HapticFeedback.heavyImpact();
  }

  // ── realtime: toca som imediatamente ao INSERT de pedido ─────────────────
  void _assinarRealtime() {
    _channel = _supabase.channel('pedidos-disp-realtime').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'pedidos',
      callback: (payload) {
        final status = payload.newRecord['status']?.toString() ?? '';
        // Só reage a pedidos prontos (não finalizado/cancelado/outros)
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
        // Toca som se pedido acabou de ficar pronto
        if (novo == 'pronto' && antigo != 'pronto') {
          _tocarNotificacao();
        }
        _buscar();
      },
    ).subscribe();
  }

  // ── aceita pedido ─────────────────────────────────────────────────────────
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

      _timer?.cancel();
      _channel?.unsubscribe();
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => EntregaScreen(pedido: pedido)));
      _buscar();
      _timer = Timer.periodic(const Duration(seconds: 8), (_) => _buscar());
      _assinarRealtime();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

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
                  color: const Color(0xFFec4899),
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
              child: CircularProgressIndicator(color: Color(0xFFec4899)))
          : _pedidos.isEmpty
              ? _buildVazio()
              : RefreshIndicator(
                  onRefresh: _buscar,
                  color: const Color(0xFFec4899),
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
    final taxaBase = taxa;
    final taxaReal = taxa * 1.20;
    final numero = pedido['numero'] ?? pedido['id'].toString().substring(0, 6);
    final pontos = pedido['pontos'] ?? 4;
    final distanciaKm =
        double.tryParse(pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final descricao = pedido['descricao']?.toString() ?? '';
    final loja = pedido['lojas'];
    final nomeLoja = loja?['nome'] ?? 'Estabelecimento';

    // Distância motoboy → loja
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

    final tags = descricao.isNotEmpty
        ? descricao
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList()
        : <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        children: [
          // HEADER — loja
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A56DB20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1A56DB50)),
                    ),
                    child: const Center(
                        child: Text('🏪', style: TextStyle(fontSize: 20))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(nomeLoja,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  // Badge pedido número
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2D35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('#$numero',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                  ),
                ]),
                const SizedBox(height: 12),

                // Distância até a loja
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      color: Color(0xFF94a3b8), size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      distMotoboyLoja > 0
                          ? '${distMotoboyLoja.toStringAsFixed(2)} km de você até a loja'
                          : (pedido['endereco']?.toString() ?? '—'),
                      style: const TextStyle(
                          color: Color(0xFF94a3b8), fontSize: 13),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),

                // Pontos
                Row(children: [
                  const Icon(Icons.star_border,
                      color: Color(0xFF94a3b8), size: 16),
                  const SizedBox(width: 4),
                  Text('$pontos pontos',
                      style: const TextStyle(
                          color: Color(0xFF94a3b8), fontSize: 13)),
                ]),

                // Tags
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 6,
                      children: tags
                          .map((tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2D35),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(tag,
                                    style: const TextStyle(
                                        color: Color(0xFF94a3b8), fontSize: 12)),
                              ))
                          .toList()),
                ],
              ],
            ),
          ),

          // FOOTER — distância entrega + valores + botão
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF2A2D35))),
            ),
            child: Row(children: [
              // Distância loja→cliente
              const Icon(Icons.route_outlined,
                  color: Color(0xFF94a3b8), size: 16),
              const SizedBox(width: 4),
              Text('${distanciaKm.toStringAsFixed(2)} km',
                  style: const TextStyle(
                      color: Color(0xFF94a3b8), fontSize: 13)),
              const Spacer(),

              // Valor tachado
              if (taxaBase > 0) ...[
                Text('R\$${taxaBase.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xFF94a3b8),
                      fontSize: 13,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Color(0xFF94a3b8),
                    )),
                const SizedBox(width: 6),
              ],

              // Valor real (com bônus)
              Text('R\$${taxaReal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Color(0xFF22c55e),
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),

              // Botão aceitar
              GestureDetector(
                onTap: () => _aceitar(pedido),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFec4899),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Aceitar',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ],
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
          icon: const Icon(Icons.refresh, color: Color(0xFFec4899)),
          label: const Text('Atualizar',
              style: TextStyle(color: Color(0xFFec4899))),
        ),
      ]),
    );
  }
}
