import 'package:flutter_test/flutter_test.dart';
import 'package:lets_go_entregador/utils/distancia_helper.dart';

void main() {
  test('formata com vírgula e 1 casa', () {
    expect(formatarKm(2.34), '2,3 km');
    expect(formatarKm(12), '12,0 km');
  });
  test('linha de coleta some sem posição', () {
    expect(textoAteColeta(null), isNull);
    expect(textoAteColeta(0), isNull);
    expect(textoAteColeta(2.34), '2,3 km até a coleta');
  });
  test('loja ao cliente', () {
    expect(textoLojaAoCliente(4.2), '4,2 km da loja ao cliente');
  });
}
