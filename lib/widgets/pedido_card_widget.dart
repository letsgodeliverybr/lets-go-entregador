import 'package:flutter/material.dart';

class PedidoCardWidget extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final String? statusLabel;
  final Color? statusCor;
  final Color botaoCor;
  final VoidCallback? onTap;
  final bool isRetornando;
  final bool mostrarBotao;
  final double? distMotoboyLojaKm;

  const PedidoCardWidget({
    super.key,
    required this.pedido,
    this.statusLabel,
    this.statusCor,
    this.botaoCor = const Color(0xFF1A56DB),
    this.onTap,
    this.isRetornando = false,
    this.mostrarBotao = false,
    this.distMotoboyLojaKm,
  });

  @override
  Widget build(BuildContext context) {
    final taxa = double.tryParse(pedido['taxa_entrega']?.toString() ?? '0') ?? 0;
    final acrescimo = double.tryParse(pedido['taxa_acrescimo']?.toString() ?? '0') ?? 0;
    final taxaFinal = taxa > 0 ? taxa * 1.20 : 0.0;
    final distanciaKm = double.tryParse(pedido['distancia_km']?.toString() ?? '0') ?? 0;
    final pontos = pedido['pontos'] as int? ?? 4;
    final numero = pedido['numero'] ?? pedido['id'].toString().substring(0, 6);
    final loja = pedido['lojas'];
    final nomeLoja = loja?['nome']?.toString() ?? pedido['nome_loja']?.toString() ?? 'Estabelecimento';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF161820),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1A56DB)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Linha 1: ícone loja + nome + número
              Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A56DB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.store, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(nomeLoja,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text('#$numero',
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
              const SizedBox(height: 10),

              // Linha 2: km de onde você está
              Row(children: [
                const Icon(Icons.location_on, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  (distMotoboyLojaKm != null && distMotoboyLojaKm! > 0)
                      ? '${distMotoboyLojaKm!.toStringAsFixed(2)} km de onde você está'
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

              // Linha 4: tag "Bag térmica"
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

              // Linha 5: rota + km | taxa + status badge
              Row(children: [
                const Icon(Icons.route_outlined, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Text('${distanciaKm.toStringAsFixed(2)} km',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const Spacer(),
                if (taxa > 0) ...[
                  Text('R\$${taxa.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.red, fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.red,
                      )),
                  const SizedBox(width: 8),
                  Text('R\$${taxaFinal.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ],
                if (statusLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A56DB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(statusLabel!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),

              // Retornando indicator
              if (isRetornando) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A56DB).withOpacity(0.08),
                    border: Border.all(color: const Color(0xFF1A56DB).withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(color: Color(0xFF1A56DB), strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Aguardando confirmação da loja',
                        style: TextStyle(color: Color(0xFF1A56DB), fontSize: 12, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
