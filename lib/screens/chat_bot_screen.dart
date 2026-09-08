import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Chat "Parceiro Let's Go" — bot 100% local (sem servidor) que conduz o
/// motoboy até uma mensagem pronta, só gravada em mensagens_chat quando o
/// fluxo termina (nenhuma chamada de rede antes disso). Ponto de entrada:
/// botão flutuante 💬 em EntregadorHomeScreen (já existia, só trocou o
/// conteúdo — era um placeholder "Em breve").
///
/// Motivo em texto solto (não enum no banco) de propósito — pedido
/// explícito do usuário pra essas listas serem fáceis de editar depois.
/// motivoSairPedido precisa bater exatamente com MOTIVO_SAIR_PEDIDO em
/// app.js (painel) — é o que destaca a conversa na lista do admin.
const List<String> motivosPedido = [
  'Problema no endereço',
  'Cliente não atende',
  'Preciso sair do pedido',
  'Outro motivo',
];
const List<String> motivosConta = [
  'Pagamento',
  'Cadastro/documentos',
  'Problema no app',
  'Outro motivo',
];
const String motivoSairPedido = 'Preciso sair do pedido';
const String _motivoOutro = 'Outro motivo';

enum _EtapaBot { escolhaTipo, carregandoPedidos, escolhaPedido, escolhaMotivo, textoLivre, enviando, enviado, erro }

class ChatBotScreen extends StatefulWidget {
  final String nomeEntregador;
  const ChatBotScreen({super.key, required this.nomeEntregador});

  @override
  State<ChatBotScreen> createState() => _ChatBotScreenState();
}

class _ChatBotScreenState extends State<ChatBotScreen> {
  final _supabase = Supabase.instance.client;
  _EtapaBot _etapa = _EtapaBot.escolhaTipo;
  String? _tipo; // 'pedido' | 'conta'
  List<Map<String, dynamic>> _pedidosAtivos = [];
  Map<String, dynamic>? _pedidoSelecionado;
  String? _motivoSelecionado;
  final _outroCtrl = TextEditingController();
  String? _erroMsg;

  @override
  void dispose() {
    _outroCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherTipoPedido() async {
    setState(() {
      _tipo = 'pedido';
      _etapa = _EtapaBot.carregandoPedidos;
    });
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      setState(() { _erroMsg = 'Sessão expirada.'; _etapa = _EtapaBot.erro; });
      return;
    }
    try {
      // Busca própria pro bot — NÃO reaproveita _pedidosEmAndamento da tela
      // principal: aquela é filtrada por ter lat/lng (serve pra desenhar
      // marcador no mapa) e por um recorte de status mais curto
      // (aceito..em_rota), sem chegou_destino/retornando. Aqui precisa de
      // TODOS os pedidos que o motoboy ainda tem em mãos, com ou sem
      // coordenada — pra pedir ajuda sobre ele, ter coordenada é irrelevante.
      final data = await _supabase
          .from('pedidos')
          .select('id, numero, loja_id, lojas(nome)')
          .or('motoboy_id.eq.$uid,entregador_id.eq.$uid')
          .inFilter('status', ['aceito', 'no_local', 'chegou_local', 'em_rota', 'chegou_destino', 'retornando']);
      final lista = List<Map<String, dynamic>>.from(data);
      if (!mounted) return;
      if (lista.isEmpty) {
        setState(() { _pedidosAtivos = []; _etapa = _EtapaBot.escolhaMotivo; });
      } else if (lista.length == 1) {
        setState(() { _pedidoSelecionado = lista.first; _etapa = _EtapaBot.escolhaMotivo; });
      } else {
        setState(() { _pedidosAtivos = lista; _etapa = _EtapaBot.escolhaPedido; });
      }
    } catch (e) {
      if (mounted) setState(() { _erroMsg = 'Falha ao buscar seus pedidos: $e'; _etapa = _EtapaBot.erro; });
    }
  }

  void _escolherTipoConta() {
    setState(() { _tipo = 'conta'; _pedidoSelecionado = null; _etapa = _EtapaBot.escolhaMotivo; });
  }

  void _escolherPedido(Map<String, dynamic> p) {
    setState(() { _pedidoSelecionado = p; _etapa = _EtapaBot.escolhaMotivo; });
  }

  void _escolherMotivo(String motivo) {
    if (motivo == _motivoOutro) {
      setState(() { _motivoSelecionado = motivo; _etapa = _EtapaBot.textoLivre; });
    } else {
      setState(() => _motivoSelecionado = motivo);
      _enviar();
    }
  }

  String _montarTexto() {
    final motivoTxt = (_motivoSelecionado == _motivoOutro && _outroCtrl.text.trim().isNotEmpty)
        ? '$_motivoOutro: ${_outroCtrl.text.trim()}'
        : (_motivoSelecionado ?? '');
    if (_tipo == 'pedido' && _pedidoSelecionado != null) {
      final numero = _pedidoSelecionado!['numero']?.toString() ?? '—';
      final lojaNome = (_pedidoSelecionado!['lojas'] as Map?)?['nome']?.toString() ?? '—';
      return 'Pedido #$numero - $lojaNome - $motivoTxt';
    }
    return 'Conta - $motivoTxt';
  }

  Future<void> _enviar() async {
    setState(() => _etapa = _EtapaBot.enviando);
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      setState(() { _erroMsg = 'Sessão expirada.'; _etapa = _EtapaBot.erro; });
      return;
    }
    try {
      await _supabase.from('mensagens_chat').insert({
        'entregador_id': uid,
        'remetente_perfil': 'entregador',
        'remetente_usuario_id': uid,
        'remetente_nome': widget.nomeEntregador,
        'texto': _montarTexto(),
        'motivo': _motivoSelecionado,
        if (_tipo == 'pedido' && _pedidoSelecionado != null) 'pedido_id': _pedidoSelecionado!['id'],
        'lida': false,
      });
      if (mounted) setState(() => _etapa = _EtapaBot.enviado);
    } catch (e) {
      if (mounted) setState(() { _erroMsg = 'Falha ao enviar: $e'; _etapa = _EtapaBot.erro; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161820),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Parceiro Let\'s Go',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2D35)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildEtapa(),
        ),
      ),
    );
  }

  Widget _buildEtapa() {
    switch (_etapa) {
      case _EtapaBot.escolhaTipo:
        return _botMensagem(
          pergunta: 'Oi! Sou o assistente do Parceiro Let\'s Go. Como posso ajudar?',
          opcoes: [
            _OpcaoBot('📦 Preciso de suporte com um pedido', _escolherTipoPedido),
            _OpcaoBot('👤 Preciso de suporte com minha conta', _escolherTipoConta),
          ],
        );
      case _EtapaBot.carregandoPedidos:
        return const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)));
      case _EtapaBot.escolhaPedido:
        return _botMensagem(
          pergunta: 'Qual pedido você precisa de ajuda?',
          opcoes: _pedidosAtivos.map((p) {
            final numero = p['numero']?.toString() ?? '—';
            final lojaNome = (p['lojas'] as Map?)?['nome']?.toString() ?? '—';
            return _OpcaoBot('$lojaNome — #$numero', () => _escolherPedido(p));
          }).toList(),
        );
      case _EtapaBot.escolhaMotivo:
        final lista = _tipo == 'pedido' ? motivosPedido : motivosConta;
        return _botMensagem(
          pergunta: _tipo == 'pedido'
              ? 'Qual o motivo?'
              : 'Sobre o que você precisa de ajuda com a conta?',
          opcoes: lista.map((m) => _OpcaoBot(m, () => _escolherMotivo(m), destaque: m == motivoSairPedido)).toList(),
        );
      case _EtapaBot.textoLivre:
        return _buildTextoLivre();
      case _EtapaBot.enviando:
        return const Center(child: CircularProgressIndicator(color: Color(0xFF1A56DB)));
      case _EtapaBot.enviado:
        return _buildEnviado();
      case _EtapaBot.erro:
        return _buildErro();
    }
  }

  Widget _botMensagem({required String pergunta, required List<_OpcaoBot> opcoes}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E212B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2D35)),
          ),
          child: Text(pergunta,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
        ),
        const SizedBox(height: 16),
        ...opcoes.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: o.onTap,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    side: BorderSide(color: o.destaque ? const Color(0xFFef4444) : const Color(0xFF1A56DB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text(o.label,
                      style: TextStyle(
                          color: o.destaque ? const Color(0xFFef4444) : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildTextoLivre() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E212B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2D35)),
          ),
          child: const Text('Conta rapidinho o que está acontecendo:',
              style: TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _outroCtrl,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Descreva o que você precisa...',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF1E212B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2A2D35)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _enviar,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A56DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Enviar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildEnviado() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10b981), size: 56),
          const SizedBox(height: 16),
          const Text('Mensagem enviada!',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Nosso suporte já recebeu sua mensagem e vai te contatar em breve.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A56DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 28),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Fechar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFef4444), size: 56),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(_erroMsg ?? 'Algo deu errado.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => setState(() => _etapa = _EtapaBot.escolhaTipo),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A56DB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }
}

class _OpcaoBot {
  final String label;
  final VoidCallback onTap;
  final bool destaque;
  const _OpcaoBot(this.label, this.onTap, {this.destaque = false});
}
