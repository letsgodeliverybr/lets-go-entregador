import 'package:flutter_test/flutter_test.dart';
import 'package:lets_go_entregador/utils/bloqueio_helper.dart';

void main() {
  test('lojaPermitida', () {
    final bloq = lojasDeLinhas([{'loja_id': 'a'}, {'loja_id': 'b'}, {'loja_id': null}]);
    expect(bloq, {'a', 'b'});
    expect(lojaPermitida('a', bloq), isFalse);
    expect(lojaPermitida('c', bloq), isTrue);
    expect(lojaPermitida(null, bloq), isTrue);
    expect(lojaPermitida('', bloq), isTrue);
  });

  test('erro do gatilho vira mensagem amigável', () {
    final e = Exception('PostgrestException(message: ENTREGADOR_BLOQUEADO_NA_LOJA: entregador x bloqueado na loja y, code: P0001)');
    expect(erroDeBloqueio(e), isTrue);
    expect(mensagemErroAceite(e, 'Erro: $e'), mensagemBloqueado);
    expect(mensagemErroAceite(Exception('timeout'), 'Erro: timeout'), 'Erro: timeout');
  });
}
