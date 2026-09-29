import 'package:flutter_test/flutter_test.dart';
import 'package:lets_go_entregador/utils/vagas_utils.dart';

Map<String, dynamic> vaga(String data, String status, {String ini = '08:00:00', String fim = '12:00:00', int id = 1}) =>
    {'id': id, 'data': data, 'status': status, 'horario_inicio': ini, 'horario_fim': fim};

void main() {
  final agora = DateTime(2026, 9, 29, 10, 30);

  group('situacaoVaga', () {
    test('status do painel têm prioridade', () {
      expect(situacaoVaga(vaga('2026-09-29', 'cancelada'), agora), SituacaoVaga.cancelada);
      expect(situacaoVaga(vaga('2026-09-29', 'finalizada'), agora), SituacaoVaga.finalizada);
      expect(situacaoVaga(vaga('2026-09-29', 'disponivel'), agora), SituacaoVaga.disponivel);
    });
    test('preenchida de hoje depende do horário', () {
      expect(situacaoVaga(vaga('2026-09-29', 'preenchida'), agora), SituacaoVaga.emAndamento);
      expect(situacaoVaga(vaga('2026-09-29', 'preenchida', ini: '14:00:00', fim: '18:00:00'), agora), SituacaoVaga.hoje);
      expect(situacaoVaga(vaga('2026-09-29', 'preenchida', ini: '06:00:00', fim: '10:00:00'), agora),
          SituacaoVaga.aguardandoFinalizacao);
    });
    test('preenchida futura e passada', () {
      expect(situacaoVaga(vaga('2026-10-01', 'preenchida'), agora), SituacaoVaga.confirmada);
      expect(situacaoVaga(vaga('2026-09-28', 'preenchida'), agora), SituacaoVaga.aguardandoFinalizacao);
    });
  });

  test('agruparMinhasVagas separa e ordena', () {
    final g = agruparMinhasVagas([
      vaga('2026-10-03', 'preenchida', id: 1),
      vaga('2026-09-29', 'preenchida', ini: '14:00:00', fim: '18:00:00', id: 2),
      vaga('2026-09-30', 'preenchida', id: 3),
      vaga('2026-09-27', 'finalizada', id: 4),
      vaga('2026-09-28', 'cancelada', id: 5),
      vaga('2026-09-29', 'preenchida', id: 6),
      vaga('2026-09-29', 'disponivel', id: 7),
    ], agora);
    expect(g.destaque.map((v) => v['id']), [6, 2]);
    expect(g.proximas.map((v) => v['id']), [3, 1]);
    expect(g.historico.map((v) => v['id']), [5, 4]);
  });

  test('formatação', () {
    expect(dataBr('2026-09-05'), '05/09/2026');
    expect(dataBr(null), '—');
    expect(periodo(vaga('2026-09-29', 'preenchida')), '08:00 – 12:00');
    expect(valorBr(40), 'R\$ 40,00');
    expect(valorBr(null), 'R\$ 0,00');
  });
}
