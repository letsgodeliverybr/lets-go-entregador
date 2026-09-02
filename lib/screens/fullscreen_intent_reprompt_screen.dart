import 'package:flutter/material.dart';
import '../services/fullscreen_intent_permission_service.dart';

// Reprompt do acesso especial de Full-Screen Intent (Android 14+) pra
// entregadores que JÁ concluíram o DeviceSetupScreen antes dessa etapa
// existir. DeviceSetupScreen.jaConcluido() é uma flag ÚNICA e global — quem
// já tinha completado o setup nunca mais vê aquela tela, e por
// consequência nunca seria perguntado sobre essa permissão específica
// (achado em auditoria, 2026-09-02, depois de descobrir que ela virou
// obrigatória pra apps não classificados como chamada/alarme pelo Google
// Play — não tem concessão automática nenhuma).
//
// Diferente do DeviceSetupScreen (que bloqueia o login até responder):
// esse aqui é opcional/não-bloqueante — o entregador já usa o app
// normalmente sem essa permissão (notificação + som continuam
// funcionando, só não abre a tela sozinho por cima de outro app/tela
// bloqueada), então "Agora não" fica sempre visível, sem precisar de uma
// tentativa recusada primeiro. Mostrado no máximo 1 vez — usa o mesmo
// controle de "já perguntei" do FullScreenIntentPermissionService
// (._chaveJaSolicitado), então não some no meio de outra tela nem volta a
// perguntar em toda abertura do app.
class FullScreenIntentRepromptScreen extends StatefulWidget {
  final Widget next;
  const FullScreenIntentRepromptScreen({super.key, required this.next});

  @override
  State<FullScreenIntentRepromptScreen> createState() => _FullScreenIntentRepromptScreenState();
}

class _FullScreenIntentRepromptScreenState extends State<FullScreenIntentRepromptScreen> {
  bool _processando = false;

  void _prosseguir() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.next));
  }

  // garantir() já cuida de tudo: abre configurações, espera o app voltar
  // do primeiro plano, reconfere o estado real e marca como "já
  // solicitado" (pra não perguntar de novo, concedido ou não).
  Future<void> _ativar() async {
    setState(() => _processando = true);
    await FullScreenIntentPermissionService.garantir();
    if (!mounted) return;
    _prosseguir();
  }

  Future<void> _pular() async {
    await FullScreenIntentPermissionService.marcarJaPerguntado();
    _prosseguir();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: const Color(0xFF1A56DB), borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.notifications_active, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'Novidade: pedido abrindo sozinho',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Agora dá pra tela de "Pedidos Disponíveis" abrir sozinha quando '
                'um pedido novo chegar — mesmo com o celular bloqueado ou outro '
                'app aberto. Pra isso funcionar, o Android pede uma permissão '
                'especial. Sem ela, o app continua funcionando normal, só que '
                'você precisa tocar na notificação na mão pra ver o pedido.',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.4),
              ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _processando ? null : _ativar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A56DB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _processando
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Ativar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton(
                  onPressed: _processando ? null : _pular,
                  child: const Text(
                    'Agora não',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
