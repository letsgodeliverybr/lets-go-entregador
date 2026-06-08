import 'package:flutter/material.dart';

Color statusColor(String? status) {
  switch (status) {
    case 'recebido':      return const Color(0xFFEF4444);
    case 'pronto':        return const Color(0xFFEC4899);
    case 'aceito':        return const Color(0xFFF59E0B);
    case 'chegou_local':  return const Color(0xFF38BDF8);
    case 'no_local':      return const Color(0xFF38BDF8);
    case 'em_rota':       return const Color(0xFF1A56DB);
    case 'chegou_destino':return const Color(0xFF1A56DB);
    case 'retornando':    return const Color(0xFF10B981);
    case 'finalizado':    return const Color(0xFF10B981);
    case 'entregue':      return const Color(0xFF10B981);
    case 'cancelado':     return const Color(0xFFEF4444);
    default:              return const Color(0xFF475569);
  }
}

String statusLabel(String? status) {
  switch (status) {
    case 'recebido':       return 'Recebido';
    case 'pronto':         return 'Pronto';
    case 'aceito':         return 'Aceito';
    case 'chegou_local':   return 'Chegou no local';
    case 'no_local':       return 'No local';
    case 'em_rota':        return 'Em rota';
    case 'chegou_destino': return 'Cheguei no local';
    case 'retornando':     return 'Retornando';
    case 'finalizado':     return 'Finalizado';
    case 'entregue':       return 'Entregue';
    case 'cancelado':      return 'Cancelado';
    default:               return status ?? '—';
  }
}

String svgHelmet(String corCasco, String corViseira) => '''
<svg viewBox="0 0 248 243" xmlns="http://www.w3.org/2000/svg">
<circle cx="124" cy="121" r="118" fill="none" stroke="white" stroke-width="2"/>
<g transform="translate(0,243) scale(0.1,-0.1)" stroke="none">
<path fill="$corCasco" d="M1375 2020 c322 -78 591 -300 702 -578 19 -48 41 -100 48 -117 22 -51 62 -195 85 -305 12 -58 35 -153 51 -213 46 -167 46 -175 0 -316 -49 -147 -105 -251 -183 -334 l-57 -61 -113 38 c-62 21 -189 67 -283 101 -149 55 -254 88 -440 140 -27 8 -97 24 -155 35 -58 11 -135 27 -172 35 -36 8 -139 18 -227 23 -175 9 -193 15 -205 73 -5 28 -33 86 -133 280 -146 281 -162 550 -48 788 25 51 55 106 66 123 19 26 20 33 9 71 -24 86 -24 84 7 90 15 2 117 28 226 56 327 84 428 101 592 97 100 -3 166 -10 230 -26z"/>
<path fill="$corViseira" d="M836 1426 c-150 -65 -39 -337 188 -460 353 -192 863 -329 1121 -301 l67 7 -7 36 c-27 154 -119 530 -133 544 -4 4 -70 12 -147 18 -267 20 -557 62 -711 101 -43 11 -105 27 -137 35 -86 22 -212 32 -241 20z"/>
</g>
</svg>
''';

const String svgPinLoja = '''
<svg viewBox="0 0 1272 1236" xmlns="http://www.w3.org/2000/svg">
<g transform="translate(0,1236) scale(0.1,-0.1)" fill="#1A56DB" stroke="none">
<path d="M6060 12169 c-456 -42 -996 -207 -1395 -426 -156 -85 -371 -227 -515 -339 -131 -101 -388 -348 -495 -474 -426 -503 -708 -1109 -810 -1741 -37 -231 -48 -380 -48 -634 1 -1054 379 -2092 1328 -3645 351 -575 771 -1203 1410 -2110 791 -1121 813 -1152 825 -1148 5 2 78 100 161 218 84 118 211 298 283 400 71 102 179 255 240 340 2066 2927 2744 4253 2862 5600 18 202 15 604 -6 775 -83 695 -316 1266 -748 1835 -199 261 -348 414 -586 597 -560 431 -1170 680 -1837 748 -157 16 -513 18 -669 4z m507 -2070 c300 -41 594 -175 832 -381 257 -222 446 -542 524 -888 18 -80 21 -128 21 -305 0 -180 -3 -225 -22 -311 -141 -648 -644 -1140 -1287 -1260 -150 -28 -422 -26 -572 4 -315 63 -597 215 -823 443 -135 137 -223 260 -310 434 -119 241 -155 397 -155 680 0 217 14 315 71 485 190 573 664 986 1249 1089 126 22 349 27 472 10z"/>
</g>
</svg>
''';
