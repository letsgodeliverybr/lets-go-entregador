// Distâncias exibidas nos cards de pedido (2026-10-02). O commit b17cdb7
// tirou a linha "X km de onde você está" inteira (texto e, em parte das
// telas, o cálculo). Volta a distância do entregador até a loja, com outro
// texto: "2,3 km até a coleta". A distância do pedido (distancia_km, da loja
// ao cliente) ganha o rótulo "da loja ao cliente".

/// "2,3 km" (1 casa, vírgula). Usada nas duas linhas de distância.
String formatarKm(double km) => '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

/// Texto da linha de coleta, ou null quando não há posição do entregador
/// (ou coordenada da loja) — aí o card simplesmente esconde a linha.
String? textoAteColeta(double? kmAteLoja) =>
    (kmAteLoja == null || kmAteLoja <= 0) ? null : '${formatarKm(kmAteLoja)} até a coleta';

String textoLojaAoCliente(double kmPedido) => '${formatarKm(kmPedido)} da loja ao cliente';
