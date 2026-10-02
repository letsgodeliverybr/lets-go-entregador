import 'package:flutter_test/flutter_test.dart';
import 'package:lets_go_entregador/utils/distancia_helper.dart';

void main() {
  test('formata com vírgula e 1 casa', () {
    expect(formatarKm(2.34), '2,3 km');
    expect(formatarKm(12), '12,0 km');
  });
  test('linha de coleta some sem posição', () {
    expect(kmAteColeta(null), isNull);
    expect(kmAteColeta(0), isNull);
    expect(kmAteColeta(0.2), '0,2 km');
  });
}
