import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class VagaDetalheScreen extends StatefulWidget {
  final Map<String, dynamic> vaga;
  const VagaDetalheScreen({super.key, required this.vaga});

  @override
  State<VagaDetalheScreen> createState() => _VagaDetalheScreenState();
}

class _VagaDetalheScreenState extends State<VagaDetalheScreen> {
  final _supabase = Supabase.instance.client;
  bool _processando = false;

  Future<void> _aceitar() async {
    if (_processando) return;
    setState(() => _processando = true);
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final result = await _supabase
          .from('vagas_motoboy_fixo')
          .update({
            'status': 'preenchida',
            'entregador_id': user.id,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('status', 'disponivel')
          .eq('id', widget.vaga['id'])
          .select();

      if (!mounted) return;
      if (result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Essa vaga já foi preenchida por outro motoboy'),
          backgroundColor: Colors.red,
        ));
        Navigator.pop(context, true);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Vaga aceita com sucesso!'),
        backgroundColor: Color(0xFF16A34A),
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _processando = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _ligar(String telefone) async {
    final numero = telefone.replaceAll(RegExp(r'[^0-9]'), '');
    if (numero.isEmpty) return;
    final uri = Uri.parse('tel:$numero');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final loja = widget.vaga['lojas'] as Map<String, dynamic>?;
    final nomeLoja = (loja?['nome'] ?? 'Loja').toString();
    final endereco = (loja?['endereco'] ?? '—').toString();
    final telefone = (loja?['telefone'] ?? '').toString();
    final valor = (widget.vaga['valor'] as num?)?.toDouble() ?? 0;
    final horarioInicio = (widget.vaga['horario_inicio'] ?? '—').toString();
    final horarioFim = (widget.vaga['horario_fim'] ?? '—').toString();
    final data = DateTime.tryParse(widget.vaga['data']?.toString() ?? '');
    final dataStr = data != null
        ? '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}'
        : '—';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Detalhes da Vaga', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.store, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(nomeLoja,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 24),
          _linha(Icons.calendar_today, 'Data', dataStr),
          _linha(Icons.access_time, 'Horário', '$horarioInicio - $horarioFim'),
          _linha(Icons.location_on_outlined, 'Endereço', endereco),
          _linha(Icons.attach_money, 'Valor da diária', 'R\$ ${valor.toStringAsFixed(2)}'),
          GestureDetector(
            onTap: telefone.isNotEmpty ? () => _ligar(telefone) : null,
            child: _linha(Icons.phone_outlined, 'Telefone', telefone.isEmpty ? '—' : telefone,
                cor: telefone.isNotEmpty ? const Color(0xFF1A56DB) : null),
          ),
          const Spacer(),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _processando ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2A2D35)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Voltar', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _processando ? null : _aceitar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A56DB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _processando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Aceitar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ]),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ]),
      ),
    );
  }

  Widget _linha(IconData icon, String label, String valor, {Color? cor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: const Color(0xFF1A56DB), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 2),
            Text(valor, style: TextStyle(color: cor ?? Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}
