import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav_bar.dart';

enum EtapaEntrega { aceito, chegouLocal, emRota, finalizado }

class EntregaScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;
  const EntregaScreen({super.key, required this.pedido});
  @override
  State<EntregaScreen> createState() => _EntregaScreenState();
}

class _EntregaScreenState extends State<EntregaScreen> {
  final _supabase = Supabase.instance.client;
  final _codigoCtrl = TextEditingController();
  EtapaEntrega _etapa = EtapaEntrega.aceito;
  bool _carregando = false;
  String? _erro;

  String get _pedidoId => widget.pedido['id'].toString();

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _avancar() async {
    setState(() { _carregando = true; _erro = null; });
    try {
      switch (_etapa) {
        case EtapaEntrega.aceito:
          await _supabase.from('pedidos').update({
            'status': 'chegou_local',
            'status_detalhado': 'chegou_local',
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.chegouLocal);
          HapticFeedback.mediumImpact();
          break;

        case EtapaEntrega.chegouLocal:
          await _supabase.from('pedidos').update({
            'status': 'em_rota',
            'status_detalhado': 'em_rota',
            'em_rota_em': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.emRota);
          HapticFeedback.mediumImpact();
          break;

        case EtapaEntrega.emRota:
          final codigo = _codigoCtrl.text.trim();
          if (codigo.length != 4 || int.tryParse(codigo) == null) {
            setState(() { _erro = 'Digite os 4 dígitos do código'; _carregando = false; });
            return;
          }
          // Salva o código digitado pelo motoboy (futuramente virá da Otemos)
          await _supabase.from('pedidos').update({
            'status': 'finalizado',
            'status_detalhado': 'finalizado',
            'finalizado_em': DateTime.now().toIso8601String(),
            'codigo_confirmacao': codigo,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _pedidoId);
          setState(() => _etapa = EtapaEntrega.finalizado);
          HapticFeedback.heavyImpact();
          break;

        case EtapaEntrega.finalizado:
          if (mounted) Navigator.pop(context);
          break;
      }
    } catch (e) {
      setState(() => _erro = 'Erro de conexão. Tente novamente.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final numero = widget.pedido['numero'] ?? _pedidoId.substring(0, 6);
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        leading: _etapa != EtapaEntrega.finalizado
            ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context))
            : null,
        title: Text('Pedido #$numero',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Barra de progresso
            _buildProgresso(),
            const SizedBox(height: 28),

            // Card info do pedido
            _buildCardPedido(),
            const SizedBox(height: 28),

            // Instrução da etapa
            _buildInstrucao(),
            const SizedBox(height: 24),

            // Campo de código (só em emRota)
            if (_etapa == EtapaEntrega.emRota) ...[
              _buildCampoCodigo(),
              const SizedBox(height: 8),
              if (_erro != null)
                Text(_erro!, style: const TextStyle(color: Color(0xFFef4444), fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 16),
            ],

            // Erro geral
            if (_erro != null && _etapa != EtapaEntrega.emRota)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_erro!, style: const TextStyle(color: Color(0xFFef4444), fontSize: 13), textAlign: TextAlign.center),
              ),

            // Tela de sucesso ou botão
            _etapa == EtapaEntrega.finalizado ? _buildFinalizado() : _buildBotao(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgresso() {
    final etapas = ['Aceito', 'No local', 'Em rota', 'Entregue'];
    final atual = _etapa.index;
    return Row(
      children: List.generate(etapas.length, (i) {
        final feito = i <= atual;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: feito ? const Color(0xFFec4899) : const Color(0xFF2a2a3e),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: feito && i < atual
                            ? const Icon(Icons.check, color: Colors.white, size: 14)
                            : Text('${i + 1}',
                                style: TextStyle(
                                    color: feito ? Colors.white : Colors.grey,
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(etapas[i],
                        style: TextStyle(color: feito ? Colors.white : Colors.grey, fontSize: 10)),
                  ],
                ),
              ),
              if (i < etapas.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 20),
                    color: i < atual ? const Color(0xFFec4899) : const Color(0xFF2a2a3e),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildCardPedido() {
    final valor = double.tryParse(widget.pedido['valor']?.toString() ?? '0') ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ENDEREÇO DE ENTREGA',
              style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, color: Color(0xFFec4899), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(widget.pedido['endereco'] ?? '—',
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('R\$ ${valor.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF10b981), fontSize: 22, fontWeight: FontWeight.bold)),
              if ((widget.pedido['cliente'] ?? '').toString().isNotEmpty)
                Text(widget.pedido['cliente'],
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstrucao() {
    final config = {
      EtapaEntrega.aceito: (Icons.store_outlined, 'Vá buscar o pedido', 'Dirija-se ao estabelecimento', const Color(0xFF8b5cf6)),
      EtapaEntrega.chegouLocal: (Icons.inventory_2_outlined, 'Chegou no local?', 'Pegue o pedido e confirme', const Color(0xFF6366f1)),
      EtapaEntrega.emRota: (Icons.pin_outlined, 'Digite o código do cliente', 'O cliente mostrará o código de 4 dígitos', const Color(0xFFec4899)),
      EtapaEntrega.finalizado: (Icons.check_circle_outline, 'Entrega concluída!', 'Parabéns!', const Color(0xFF10b981)),
    };
    final (icon, titulo, sub, cor) = config[_etapa]!;
    return Column(
      children: [
        Icon(icon, color: cor, size: 52),
        const SizedBox(height: 12),
        Text(titulo, style: TextStyle(color: cor, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildCampoCodigo() {
    return Column(
      children: [
        const Text('CÓDIGO DO CLIENTE', style: TextStyle(color: Color(0xFFec4899), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 12),
        TextField(
          controller: _codigoCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 16),
          decoration: InputDecoration(
            counterText: '',
            hintText: '0000',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 36, letterSpacing: 16),
            filled: true,
            fillColor: const Color(0xFF161820),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFec4899))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2A2D35))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFec4899), width: 2)),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Peça ao cliente para mostrar o código', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }

  Widget _buildBotao() {
    final config = {
      EtapaEntrega.aceito:      (const Color(0xFF8b5cf6), 'Cheguei no local',      Icons.store),
      EtapaEntrega.chegouLocal: (const Color(0xFF6366f1), 'Saí para entregar',     Icons.moped),
      EtapaEntrega.emRota:      (const Color(0xFFec4899), 'Finalizar entrega',     Icons.check_circle),
      EtapaEntrega.finalizado:  (const Color(0xFF10b981), 'Voltar para pedidos',   Icons.home),
    };
    final (cor, label, icon) = config[_etapa]!;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: cor, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: _carregando ? null : _avancar,
        child: _carregando
            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 10),
                  Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    );
  }

  Widget _buildFinalizado() {
    return Column(
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF10b981), size: 90),
        const SizedBox(height: 16),
        const Text('Entrega finalizada!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Pedido entregue com sucesso', style: TextStyle(color: Colors.white54, fontSize: 14)),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10b981), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: _avancar,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_back, size: 20),
                SizedBox(width: 8),
                Text('Voltar para pedidos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}