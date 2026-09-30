import 'package:supabase_flutter/supabase_flutter.dart';

// Mensagem do erro de solicitar_saque (2026-09-30). Antes a tela só
// reconhecia saldo_insuficiente e valor_invalido; todo o resto virava
// "Erro ao solicitar saque", inclusive a recusa da carência de 24h depois
// de trocar a chave Pix, que o banco já manda com o texto pronto.
//
// O banco devolve dois tipos de recusa:
//   - com texto pronto em `message` e o motivo em `hint`
//     (chave_pix_em_carencia, saque_desativado, teto_diario_plataforma):
//     mostra o texto do banco (ex.: "o saque libera em 3h 20min");
//   - com o código em `message` (sem_chave_pix, entregador_bloqueado,
//     saldo_insuficiente, valor_invalido): traduz aqui.
const mensagemSaqueGenerica = 'Erro ao solicitar saque. Tente novamente.';

const _hintsComTextoDoBanco = {
  'chave_pix_em_carencia',
  'saque_desativado',
  'teto_diario_plataforma',
};

String mensagemErroSaque(Object e) {
  final message = e is PostgrestException ? e.message : null;
  final hint = e is PostgrestException ? e.hint : null;
  final texto = message ?? e.toString();

  if (texto.contains('saldo_insuficiente')) return 'Saldo insuficiente para este saque.';
  if (texto.contains('valor_invalido')) return 'Informe um valor válido.';
  if (hint != null && _hintsComTextoDoBanco.contains(hint) && message != null && message.trim().isNotEmpty) {
    return message.trim();
  }
  if (texto.contains('sem_chave_pix')) return 'Cadastre sua chave Pix em Minha Conta antes de sacar.';
  if (texto.contains('entregador_bloqueado')) {
    return 'Seu cadastro está bloqueado ou aguardando aprovação. Fale com o suporte.';
  }
  return mensagemSaqueGenerica;
}
