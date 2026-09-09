import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Item 2 da leva de melhorias visuais (auditoria 2026-09-08): antes era
/// só "Documentos em análise" genérico, sem quebrar por documento. Agora
/// mostra o status individual dos 5 documentos (fonte de verdade: as
/// colunas foto_*_status em entregadores, ver AuthGate/main.dart e
/// _recalcularStatusCadastro em app.js). Continua sendo o gate obrigatório
/// plugado em AuthGate — só sai daqui aprovado nos 5 ou fazendo logout.
class AguardoAprovacaoScreen extends StatefulWidget {
  const AguardoAprovacaoScreen({super.key});

  @override
  State<AguardoAprovacaoScreen> createState() =>
      _AguardoAprovacaoScreenState();
}

class _DocumentoInfo {
  final String campo;
  final String label;
  const _DocumentoInfo(this.campo, this.label);
}

// Rótulos como o usuário pediu (ex: "RENAVAM") mesmo onde a coluna real
// tem outro nome (foto_crlv) — no Brasil a informação de RENAVAM vem
// junto do CRLV, não existe coluna separada pra isso.
const _documentos = [
  _DocumentoInfo('foto_perfil', 'Foto do rosto'),
  _DocumentoInfo('foto_comprovante_residencia', 'Comprovante de residência'),
  _DocumentoInfo('foto_cnh', 'CNH'),
  _DocumentoInfo('foto_crlv', 'RENAVAM'),
  _DocumentoInfo('foto_placa', 'Foto da placa'),
];

class _AguardoAprovacaoScreenState extends State<AguardoAprovacaoScreen> {
  final _supabase = Supabase.instance.client;
  bool _carregando = true;
  bool _verificando = false;
  Map<String, dynamic>? _entregador;

  String get _uid => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    debugPrint('[GATE-DEBUG] *** AguardoAprovacaoScreen ABRIU/MONTOU ***');
    _carregar();
  }

  Future<void> _carregar() async {
    if (_uid.isEmpty) return;
    setState(() => _carregando = true);
    try {
      final e = await _supabase
          .from('entregadores')
          .select()
          .eq('id', _uid)
          .single();

      final todosAprovados = _documentos
          .every((d) => e['${d.campo}_status']?.toString() == 'aprovado');
      final bloqueado = e['status']?.toString() == 'bloqueado';

      if (!mounted) return;

      if (todosAprovados && !bloqueado) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
        return;
      }

      setState(() {
        _entregador = e;
        _carregando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar cadastro: $e'),
            backgroundColor: const Color(0xFFef4444),
          ),
        );
      }
    }
  }

  Future<void> _atualizarStatus() async {
    setState(() => _verificando = true);
    await _carregar();
    if (mounted) setState(() => _verificando = false);
  }

  Future<void> _sair() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _entregador;
    return Scaffold(
      backgroundColor: const Color(0xFF161820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161820),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Status do cadastro',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        // Sem tela anterior de verdade pra voltar (AuthGate substitui a
        // pilha inteira ao chegar aqui) — "voltar" aqui é sair da conta,
        // não desbloquear o app. Único jeito de escapar dessa tela sem
        // estar 100% aprovado.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Sair',
          onPressed: _sair,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2D35)),
        ),
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1A56DB)))
          : e == null
              ? const Center(
                  child: Text('Cadastro não encontrado.',
                      style: TextStyle(color: Colors.white70)))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  color: const Color(0xFF1A56DB),
                  backgroundColor: const Color(0xFF1E1E1E),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCardTopo(e),
                        const SizedBox(height: 24),
                        const Text('STATUS DOS DOCUMENTOS ENVIADOS',
                            style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0)),
                        const SizedBox(height: 10),
                        ..._documentos.map((d) => _buildLinhaDocumento(e, d)),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _verificando ? null : _atualizarStatus,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A56DB),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  const Color(0xFF1A56DB).withOpacity(.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: _verificando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.5))
                                : const Text('Atualizar status',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildRodape(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildCardTopo(Map<String, dynamic> e) {
    final nome = e['nome']?.toString() ?? '—';
    final fotoUrl = e['foto_perfil']?.toString() ?? '';
    final modal = e['modal_veiculo']?.toString() ?? '';
    // Sem coluna de estado/UF em entregadores (nem no formulário de
    // cadastro) — mostra só o veículo. Se um dia a operação virar
    // multi-estado, precisa desse campo antes de completar "Moto • SP".
    final veiculoLabel = {
      'moto': 'Moto',
      'carro': 'Carro',
      'bicicleta': 'Bicicleta',
      'van': 'Van',
    }[modal] ?? (modal.isEmpty ? '—' : modal);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E212B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFF2A2D35),
            backgroundImage: fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
            child: fotoUrl.isEmpty
                ? const Icon(Icons.person, color: Colors.white38, size: 32)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.two_wheeler,
                        color: Colors.white54, size: 15),
                    const SizedBox(width: 4),
                    Text(veiculoLabel,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinhaDocumento(Map<String, dynamic> e, _DocumentoInfo d) {
    final status = e['${d.campo}_status']?.toString() ?? 'em_analise';
    final motivo = e['${d.campo}_motivo']?.toString() ?? '';

    late final IconData icone;
    late final Color cor;
    late final String textoStatus;
    switch (status) {
      case 'aprovado':
        icone = Icons.check_circle;
        cor = const Color(0xFF10b981);
        textoStatus = 'Aprovado';
        break;
      case 'reprovado':
        icone = Icons.cancel;
        cor = const Color(0xFFef4444);
        textoStatus = 'Documento reprovado, envie novamente';
        break;
      default:
        icone = Icons.access_time_filled;
        cor = const Color(0xFFeab308);
        textoStatus = 'Em análise';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E212B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(textoStatus,
                    style: TextStyle(
                        color: cor, fontSize: 12.5, fontWeight: FontWeight.w600)),
                if (status == 'reprovado' && motivo.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(motivo,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12, height: 1.3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRodape() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A56DB).withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1A56DB).withOpacity(.25)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nossa equipe está avaliando seu cadastro',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text(
            'Se tiver algum documento reprovado, reenvie com um líder de '
            'expansão da sua região. Qualquer dúvida sobre o andamento do '
            'seu cadastro, fale com o SAC.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}
