import 'package:flutter_test/flutter_test.dart';
import 'package:lets_go_entregador/utils/diaria_helper.dart';

void main() {
  final credito = {'tipo': 'credito', 'valor': 30, 'observacoes': 'Diária Finalizada - @PEDELETSGO', 'data': '2026-09-30', 'created_at': '2026-09-30T23:21:19Z'};
  final estorno = {'tipo': 'debito', 'valor': 40, 'observacoes': 'Estorno De Diária - Loja', 'data': '2026-10-01', 'created_at': '2026-10-01T15:00:00Z'};

  test('diária soma, estorno subtrai', () {
    expect(valorDiaria(credito), 30);
    expect(valorDiaria(estorno), -40);
    expect(somaDiarias([credito]), 30);
    expect(somaDiarias([credito, {'tipo': 'credito', 'valor': 40}, estorno]), 30);
    expect(somaDiarias([]), 0);
  });

  test('dataIso no formato da coluna date', () {
    expect(dataIso(DateTime(2026, 9, 30, 23, 59)), '2026-09-30');
    expect(dataIso(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('extrato junta pedidos e diárias, mais recente primeiro, sem duplicar', () {
    final pedidos = [
      // horários em UTC convertidos pro fuso da máquina, igual ao created_at da diária
      {'numero': '101', 'v': 8.0, 'q': DateTime.parse('2026-09-30T15:00:00Z').toLocal()},
      {'numero': '102', 'v': 9.5, 'q': DateTime.parse('2026-09-30T23:00:00Z').toLocal()},
    ];
    final itens = juntarExtrato(pedidos, [credito], (p) => p['v'] as double, (p) => p['q'] as DateTime);
    expect(itens.length, 3);
    expect(itens.first.ehDiaria, isTrue); // 23:21Z é o mais recente (20:21 em Brasília)
    expect(itens.map((i) => i.ehDiaria ? 'diaria' : i.dados['numero']).toList(), ['diaria', '102', '101']);
    expect(itens.fold<double>(0, (s, i) => s + i.valor), 47.5);
    expect(itens.where((i) => i.ehDiaria).length, 1);
  });
}
