import 'package:flutter_test/flutter_test.dart';
import 'package:lets_go_entregador/utils/taxa_helper.dart' as th;

void main() {
  setUp(() {
    // tabela global de exemplo (fallback quando o pedido não tem taxa_motoboy)
    th.faixasGlobais = [
      {'km_ate': 5, 'valor_sem_retorno': 8.45, 'valor_com_retorno': 12},
      {'km_ate': 6, 'valor_sem_retorno': 10.22, 'valor_com_retorno': 14},
    ];
  });

  test('vale o taxa_motoboy gravado no pedido (tabela da loja), não a global', () {
    // caso real: global daria 10,22; a loja paga 9,00
    expect(th.valorEntregador({'distancia_km': 5.84, 'taxa_motoboy': 9, 'loja_id': 'x'}), 9);
    expect(th.detalharValor({'distancia_km': 5.84, 'taxa_motoboy': 9, 'loja_id': 'x'}).total, 9);
  });

  test('taxa_motoboy já inclui gorjeta e preço dinâmico (não soma de novo)', () {
    final v = th.detalharValor({'distancia_km': 4.0, 'taxa_motoboy': 12.45, 'gorjeta': 2, 'loja_id': 'x'});
    expect(v.total, 12.45);
    expect(v.gorjeta, 2);
    expect(v.pd, closeTo(2.0, 0.001)); // 12,45 - 2 (gorjeta) - 8,45 (base)
  });

  test('sem taxa_motoboy: calcula pela tabela (aqui a global) + pd + gorjeta', () {
    expect(th.valorEntregador({'distancia_km': 4.0, 'gorjeta': 1, 'preco_dinamico': 0.5}), 9.95);
  });

  test('valor sem retorno desconta a diferença da tabela', () {
    final v = th.detalharValor({'distancia_km': 4.0, 'taxa_motoboy': 12, 'com_retorno': true});
    expect(v.semRetorno, closeTo(8.45, 0.001));
  });
}
