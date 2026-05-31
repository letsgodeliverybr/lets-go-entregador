import 'package:supabase_flutter/supabase_flutter.dart';

const _tabelaId = '7bf1cf41-b3f2-4694-b326-d4e830dae8e1';

List<Map<String, dynamic>> faixasGlobais = [];

Future<void> carregarFaixas() async {
  if (faixasGlobais.isNotEmpty) return;
  try {
    final data = await Supabase.instance.client
        .from('tabelas_preco_faixas')
        .select('km_ate, valor_sem_retorno, valor_com_retorno')
        .eq('tabela_id', _tabelaId)
        .order('km_ate', ascending: true);
    faixasGlobais = List<Map<String, dynamic>>.from(data);
  } catch (_) {}
}

double calcularTaxaMotoboy(
  double distanciaKm,
  bool comRetorno,
  List<Map<String, dynamic>> faixas,
) {
  if (faixas.isEmpty) return 0;
  final faixa = faixas.firstWhere(
    (f) => (f['km_ate'] as num).toDouble() >= distanciaKm,
    orElse: () => faixas.last,
  );
  if (comRetorno) {
    return (faixa['valor_com_retorno'] as num).toDouble();
  }
  return (faixa['valor_sem_retorno'] as num).toDouble();
}
