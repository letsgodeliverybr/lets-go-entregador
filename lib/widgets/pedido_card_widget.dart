import 'package:flutter/material.dart';

class PedidoCardWidget extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final String? statusLabel;
  final Color? statusCor;
  final Color botaoCor;
  final VoidCallback? onTap;
  final bool isRetornando;
  final bool mostrarBotao;

  const PedidoCardWidget({
    super.key,
    required this.pedido,
    this.statusLabel,
    this.statusCor,
    this.botaoCor = const Color(0xFF1A56DB),
    this.onTap,
    this.isRetornando = false,
    this.mostrarBotao = false,
  });

  String _titleCase(String text) => text
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final taxa = double.tryParse(pedido['taxa_entrega']?.toString() ?? '0') ?? 0;
    final acrescimo = double.tryParse(pedido['taxa_acrescimo']?.toString() ?? '0') ?? 0;
    final taxaFinal = taxa + acrescimo;
    final temAcrescimo = acrescimo > 0 && taxaFinal != taxa;
    final distancia = double.tryParse(pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final pontos = pedido['pontos'] as int? ?? 4;
    final numero = pedido['numero'] ?? pedido['id'].toString().substring(0, 6);
    final enderecoColeta = _titleCase(pedido['endereco_loja']?.toString() ?? 'Estabelecimento');
    final enderecoEntrega = _titleCase(pedido['endereco']?.toString() ?? '—');
    final cor = statusCor ?? botaoCor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF161820),
          border: Border.all(color: const Color(0xFF1A56DB), width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header: número + status ──────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('#$numero',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  if (statusLabel != null)
                    Text(statusLabel!,
                        style: TextStyle(color: cor, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFF2a2a3e)),

            // ── Endereços ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(children: [
                // Coleta
                Row(children: [
                  _iconBox(Icons.store, const Color(0xFF1A56DB)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('COLETA', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
                    Text(enderecoColeta, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ])),
                ]),
                // Linha pontilhada
                Padding(
                  padding: const EdgeInsets.only(left: 13),
                  child: Column(children: List.generate(3, (_) => Container(
                    width: 2, height: 5, color: Colors.white24,
                    margin: const EdgeInsets.symmetric(vertical: 1),
                  ))),
                ),
                // Entrega
                Row(children: [
                  _iconBox(Icons.location_on, const Color(0xFF1A56DB)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('ENTREGA', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
                    Text(enderecoEntrega, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ])),
                ]),
              ]),
            ),

            // ── Info: distância + taxa | pontos ──────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (distancia > 0) ...[
                    _infoChip(Icons.route,
                        '${distancia.toStringAsFixed(1)} km',
                        const Color(0xFF60a5fa)),
                  ],

                  const Spacer(),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (taxa > 0) ...[
                        if (temAcrescimo) ...[
                          Text('R\$ ${taxa.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.red,
                              )),
                          const SizedBox(height: 2),
                        ],
                        Text('R\$ ${taxaFinal.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                      ],
                      Text('$pontos pts',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),

            // ── Retornando ───────────────────────────────
            if (isRetornando)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A56DB10),
                    border: Border.all(color: const Color(0xFF1A56DB40)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(color: Color(0xFF1A56DB), strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Aguardando confirmação da loja',
                        style: TextStyle(color: Color(0xFF1A56DB), fontSize: 13, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _iconBox(IconData icon, Color cor) => Container(
    width: 28, height: 28,
    decoration: BoxDecoration(
      color: cor.withOpacity(0.12),
      border: Border.all(color: cor),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, color: cor, size: 14),
  );

  Widget _infoChip(IconData icon, String label, Color cor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: cor.withOpacity(0.1),
      border: Border.all(color: cor.withOpacity(0.4)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(children: [
      Icon(icon, color: cor, size: 13),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}
