import 'package:flutter/material.dart';

// Regras puras da aba de vagas (Motoboy Fixo / Entrega Dedicada) — separadas
// da tela pra serem testáveis (test/vagas_utils_test.dart).
//
// Status em vagas_motoboy_fixo (texto livre, definidos pelo painel):
//   disponivel  → aberta, sem entregador
//   preenchida  → aceita por um entregador
//   finalizada  → painel marcou como concluída
//   cancelada   → painel cancelou (entregador_id é mantido)
// Desatribuir no painel volta pra 'disponivel' com entregador_id null — a
// vaga some de "Minhas vagas" e reaparece em "Disponíveis".

String dataIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String dataBr(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String hora(dynamic h) {
  final s = (h ?? '').toString();
  return s.length >= 5 ? s.substring(0, 5) : (s.isEmpty ? '—' : s);
}

String periodo(Map<String, dynamic> v) =>
    '${hora(v['horario_inicio'])} – ${hora(v['horario_fim'])}';

String valorBr(dynamic v) {
  final n = (v as num?)?.toDouble() ?? 0;
  return 'R\$ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
}

/// Situação exibida pro entregador (selo do card).
enum SituacaoVaga { disponivel, emAndamento, hoje, confirmada, aguardandoFinalizacao, finalizada, cancelada }

SituacaoVaga situacaoVaga(Map<String, dynamic> v, DateTime agora) {
  final status = (v['status'] ?? '').toString();
  if (status == 'cancelada') return SituacaoVaga.cancelada;
  if (status == 'finalizada') return SituacaoVaga.finalizada;
  if (status == 'disponivel') return SituacaoVaga.disponivel;
  final data = (v['data'] ?? '').toString();
  final hoje = dataIso(agora);
  if (data.compareTo(hoje) > 0) return SituacaoVaga.confirmada;
  if (data.compareTo(hoje) < 0) return SituacaoVaga.aguardandoFinalizacao;
  final agoraHm = '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';
  final ini = hora(v['horario_inicio']);
  final fim = hora(v['horario_fim']);
  if (agoraHm.compareTo(ini) >= 0 && agoraHm.compareTo(fim) < 0) return SituacaoVaga.emAndamento;
  if (agoraHm.compareTo(fim) >= 0) return SituacaoVaga.aguardandoFinalizacao;
  return SituacaoVaga.hoje;
}

({String rotulo, Color cor}) seloSituacao(SituacaoVaga s) {
  switch (s) {
    case SituacaoVaga.disponivel:
      return (rotulo: 'Disponível', cor: const Color(0xFF1A56DB));
    case SituacaoVaga.emAndamento:
      return (rotulo: 'Em andamento', cor: const Color(0xFF22C55E));
    case SituacaoVaga.hoje:
      return (rotulo: 'Hoje', cor: const Color(0xFF22C55E));
    case SituacaoVaga.confirmada:
      return (rotulo: 'Confirmada', cor: const Color(0xFF1A56DB));
    case SituacaoVaga.aguardandoFinalizacao:
      return (rotulo: 'Aguardando finalização', cor: const Color(0xFFF59E0B));
    case SituacaoVaga.finalizada:
      return (rotulo: 'Finalizada', cor: const Color(0xFF9CA3AF));
    case SituacaoVaga.cancelada:
      return (rotulo: 'Cancelada', cor: const Color(0xFFEF4444));
  }
}

/// Separa as vagas do entregador em: destaque (hoje, ainda valendo),
/// próximas (datas futuras, crescente) e histórico (encerradas, mais recente
/// primeiro).
({List<Map<String, dynamic>> destaque, List<Map<String, dynamic>> proximas, List<Map<String, dynamic>> historico})
    agruparMinhasVagas(List<Map<String, dynamic>> vagas, DateTime agora) {
  final destaque = <Map<String, dynamic>>[];
  final proximas = <Map<String, dynamic>>[];
  final historico = <Map<String, dynamic>>[];
  for (final v in vagas) {
    switch (situacaoVaga(v, agora)) {
      case SituacaoVaga.emAndamento:
      case SituacaoVaga.hoje:
        destaque.add(v);
      case SituacaoVaga.confirmada:
        proximas.add(v);
      case SituacaoVaga.disponivel:
        break; // não é mais dele (desatribuída) — não deveria vir na busca
      case SituacaoVaga.aguardandoFinalizacao:
      case SituacaoVaga.finalizada:
      case SituacaoVaga.cancelada:
        historico.add(v);
    }
  }
  int cresc(Map<String, dynamic> a, Map<String, dynamic> b) {
    final c = (a['data'] ?? '').toString().compareTo((b['data'] ?? '').toString());
    return c != 0 ? c : hora(a['horario_inicio']).compareTo(hora(b['horario_inicio']));
  }
  destaque.sort(cresc);
  proximas.sort(cresc);
  historico.sort((a, b) => cresc(b, a));
  return (destaque: destaque, proximas: proximas, historico: historico);
}
