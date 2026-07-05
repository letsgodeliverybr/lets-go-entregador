import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _premios = <int, int>{
  1: 100, 2: 80, 3: 70, 4: 60, 5: 50,
  6: 40, 7: 30, 8: 20, 9: 15, 10: 10,
};

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});
  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  final _supabase = Supabase.instance.client;

  static List<Map<String, dynamic>>? _cache;
  static DateTime? _cacheEm;
  static const _ttl = Duration(hours: 3);

  List<Map<String, dynamic>> _top10 = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar({bool forcar = false}) async {
    final cacheValido = _cache != null &&
        _cacheEm != null &&
        DateTime.now().difference(_cacheEm!) < _ttl;

    if (cacheValido && !forcar) {
      setState(() {
        _top10 = _cache!;
        _carregando = false;
      });
      return;
    }

    if (mounted) setState(() => _carregando = true);
    try {
      // pontos_semana = 0 nunca deve aparecer no ranking — só quem pontuou
      // de verdade essa semana, mesmo que sobre menos de 10 posições.
      final data = await _supabase
          .from('entregadores')
          .select('nome, pontos_semana')
          .gt('pontos_semana', 0)
          .order('pontos_semana', ascending: false)
          .limit(10);
      final resultado = List<Map<String, dynamic>>.from(data);
      _cache = resultado;
      _cacheEm = DateTime.now();
      if (mounted) setState(() { _top10 = resultado; _carregando = false; });
    } catch (e) {
      debugPrint('[RankingScreen] erro ao buscar ranking: $e');
      if (mounted) setState(() { _top10 = []; _carregando = false; });
    }
  }

  Color _corPosicao(int posicao) {
    switch (posicao) {
      case 1: return const Color(0xFFFFD700);
      case 2: return const Color(0xFFC0C0C0);
      case 3: return const Color(0xFFCD7F32);
      default: return const Color(0xFF1A56DB);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0F14),
          foregroundColor: Colors.white,
          title: const Text('Ranking da Semana', style: TextStyle(fontWeight: FontWeight.w700)),
          centerTitle: true,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Color(0xFF1A56DB),
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            tabs: [
              Tab(text: 'Ranking'),
              Tab(text: 'Premiações'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildRanking(),
            _buildPremiacoes(),
          ],
        ),
      ),
    );
  }

  Widget _buildRanking() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)));
    }
    if (_top10.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.leaderboard_outlined, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          const Text('Nenhuma pontuação registrada ainda essa semana',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 15)),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => _carregar(forcar: true),
            icon: const Icon(Icons.refresh, color: Color(0xFF1A56DB)),
            label: const Text('Atualizar', style: TextStyle(color: Color(0xFF1A56DB))),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _carregar(forcar: true),
      color: const Color(0xFF1A56DB),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        itemCount: _top10.length,
        itemBuilder: (_, i) => _buildCardRanking(i),
      ),
    );
  }

  Widget _buildCardRanking(int i) {
    final posicao = i + 1;
    final entregador = _top10[i];
    final nome = (entregador['nome'] ?? '—').toString();
    final pontos = (entregador['pontos_semana'] as num?)?.toInt() ?? 0;
    final premio = _premios[posicao] ?? 0;
    final corPosicao = _corPosicao(posicao);
    final destaque = posicao <= 3;
    final ehPrimeiro = posicao == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(ehPrimeiro ? 18 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: destaque ? corPosicao.withOpacity(0.6) : const Color(0xFF2A2D35),
          width: ehPrimeiro ? 1.5 : 1,
        ),
        boxShadow: ehPrimeiro
            ? [BoxShadow(color: corPosicao.withOpacity(0.15), blurRadius: 16, spreadRadius: 1)]
            : null,
      ),
      child: Row(children: [
        SizedBox(
          width: 48,
          height: 48,
          child: destaque
              ? Stack(alignment: Alignment.center, children: [
                  Icon(Icons.emoji_events, color: corPosicao, size: 40),
                  Positioned(
                    bottom: 0,
                    child: Text('$posicao°',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ])
              : Container(
                  decoration: const BoxDecoration(color: Color(0xFF1F2229), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('$posicao°',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: ehPrimeiro ? 17 : 15)),
            const SizedBox(height: 4),
            Text('$pontos pontos',
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF10b981).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF10b981).withOpacity(0.4)),
          ),
          child: Text('R\$ $premio',
              style: const TextStyle(color: Color(0xFF10b981), fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildPremiacoes() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      itemCount: _premios.length,
      itemBuilder: (_, i) {
        final posicao = i + 1;
        final premio = _premios[posicao]!;
        final corPosicao = _corPosicao(posicao);
        final destaque = posicao <= 3;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161820),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: destaque ? corPosicao.withOpacity(0.6) : const Color(0xFF2A2D35)),
          ),
          child: Row(children: [
            SizedBox(
              width: 44,
              height: 44,
              child: destaque
                  ? Icon(Icons.emoji_events, color: corPosicao, size: 36)
                  : Container(
                      decoration: const BoxDecoration(color: Color(0xFF1F2229), shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('$posicao°',
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text('$posicao° lugar',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            Text('R\$ $premio',
                style: const TextStyle(color: Color(0xFF10b981), fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        );
      },
    );
  }
}
