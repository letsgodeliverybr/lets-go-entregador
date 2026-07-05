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
      final data = await _supabase
          .from('entregadores')
          .select('nome, pontos_semana')
          .order('pontos_semana', ascending: false)
          .limit(10);
      final resultado = List<Map<String, dynamic>>.from(data);
      _cache = resultado;
      _cacheEm = DateTime.now();
      if (mounted) setState(() { _top10 = resultado; _carregando = false; });
    } catch (e) {
      if (mounted) setState(() { _top10 = []; _carregando = false; });
    }
  }

  Color _corPosicao(int posicao) {
    switch (posicao) {
      case 1: return const Color(0xFFFFD700);
      case 2: return const Color(0xFFC0C0C0);
      case 3: return const Color(0xFFCD7F32);
      default: return const Color(0xFF2A2D35);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        title: const Text('Ranking da Semana', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2D35)),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : _top10.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.leaderboard_outlined, color: Colors.white24, size: 64),
                    const SizedBox(height: 16),
                    const Text('Ranking ainda não disponível',
                        style: TextStyle(color: Colors.white54, fontSize: 16)),
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: () => _carregar(forcar: true),
                      icon: const Icon(Icons.refresh, color: Color(0xFF1A56DB)),
                      label: const Text('Atualizar', style: TextStyle(color: Color(0xFF1A56DB))),
                    ),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: () => _carregar(forcar: true),
                  color: const Color(0xFF1A56DB),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _top10.length,
                    itemBuilder: (_, i) {
                      final posicao = i + 1;
                      final entregador = _top10[i];
                      final nome = (entregador['nome'] ?? '—').toString();
                      final pontos = (entregador['pontos_semana'] as num?)?.toInt() ?? 0;
                      final premio = _premios[posicao] ?? 0;
                      final corPosicao = _corPosicao(posicao);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161820),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: posicao <= 3 ? corPosicao.withOpacity(0.5) : const Color(0xFF2A2D35),
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: corPosicao.withOpacity(posicao <= 3 ? 0.2 : 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Text('$posicao°',
                                style: TextStyle(
                                  color: posicao <= 3 ? corPosicao : Colors.white70,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                )),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(nome,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text('$pontos pontos',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ]),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10b981).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF10b981).withOpacity(0.4)),
                            ),
                            child: Text('R\$ $premio',
                                style: const TextStyle(color: Color(0xFF10b981), fontSize: 13, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
