import 'package:flutter_test/flutter_test.dart';
import 'package:lets_go_entregador/utils/saque_erro_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException erroBanco(String message, {String? hint}) =>
    PostgrestException(message: message, code: 'P0001', hint: hint);

void main() {
  test('carência da chave Pix mostra o texto do banco', () {
    const texto = 'Você alterou sua chave Pix há pouco. Por segurança, o saque libera em 3h 20min.';
    expect(mensagemErroSaque(erroBanco(texto, hint: 'chave_pix_em_carencia')), texto);
  });

  test('saque desativado e teto diário mostram o texto do banco', () {
    const desativado = 'Os saques estão temporariamente indisponíveis. Tente mais tarde.';
    const teto = 'O limite diário de saques foi atingido. Tente novamente amanhã.';
    expect(mensagemErroSaque(erroBanco(desativado, hint: 'saque_desativado')), desativado);
    expect(mensagemErroSaque(erroBanco(teto, hint: 'teto_diario_plataforma')), teto);
  });

  test('códigos sem texto pronto viram mensagem amigável', () {
    expect(mensagemErroSaque(erroBanco('sem_chave_pix')), 'Cadastre sua chave Pix em Minha Conta antes de sacar.');
    expect(mensagemErroSaque(erroBanco('entregador_bloqueado')),
        'Seu cadastro está bloqueado ou aguardando aprovação. Fale com o suporte.');
  });

  test('saldo_insuficiente e valor_invalido continuam como antes', () {
    expect(mensagemErroSaque(erroBanco('saldo_insuficiente: disponível R\$ 10, solicitado R\$ 50')),
        'Saldo insuficiente para este saque.');
    expect(mensagemErroSaque(erroBanco('valor_invalido: mínimo R\$ 20')), 'Informe um valor válido.');
    expect(mensagemErroSaque(Exception('saldo_insuficiente')), 'Saldo insuficiente para este saque.');
  });

  test('erro desconhecido continua genérico', () {
    expect(mensagemErroSaque(Exception('timeout')), mensagemSaqueGenerica);
    expect(mensagemErroSaque(erroBanco('nao_autenticado')), mensagemSaqueGenerica);
    expect(mensagemErroSaque(erroBanco('algo novo', hint: 'hint_desconhecido')), mensagemSaqueGenerica);
    expect(mensagemErroSaque(erroBanco('', hint: 'chave_pix_em_carencia')), mensagemSaqueGenerica);
  });
}
