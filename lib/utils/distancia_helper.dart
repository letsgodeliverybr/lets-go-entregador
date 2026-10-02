// Distâncias exibidas nos cards de pedido (2026-10-02): só o valor, sem
// rótulo. Pino + "0,2 km" = entregador até a loja (linha acima dos pontos,
// some sem GPS); rota + "4,2 km" = loja até o cliente (ao lado do R$).

/// "2,3 km" (1 casa, vírgula).
String formatarKm(double km) => '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

/// Valor da linha de coleta, ou null quando não há posição do entregador
/// (ou coordenada da loja) — aí o card simplesmente esconde a linha.
String? kmAteColeta(double? kmAteLoja) =>
    (kmAteLoja == null || kmAteLoja <= 0) ? null : formatarKm(kmAteLoja);
