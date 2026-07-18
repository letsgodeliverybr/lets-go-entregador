import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/dnd_permission_service.dart';
import '../services/location_permission_flow.dart';

enum _Status { pendente, processando, concedida, negada }
enum _FaseTela { disclosure, solicitando }

class _Item {
  final IconData icone;
  final String titulo;
  final String descricao;
  final Color cor;
  _Status status = _Status.pendente;

  _Item({
    required this.icone,
    required this.titulo,
    required this.descricao,
    required this.cor,
  });
}

class PermissoesScreen extends StatefulWidget {
  final Widget next;
  const PermissoesScreen({super.key, required this.next});

  @override
  State<PermissoesScreen> createState() => _PermissoesScreenState();
}

class _PermissoesScreenState extends State<PermissoesScreen> {
  late final List<_Item> _itens;
  _FaseTela _fase = _FaseTela.disclosure;

  @override
  void initState() {
    super.initState();
    _itens = [
      _Item(
        icone: Icons.location_on,
        titulo: 'Localização',
        descricao: 'Rastrear sua posição durante as entregas',
        cor: const Color(0xFF1A56DB),
      ),
      _Item(
        icone: Icons.notifications,
        titulo: 'Notificações',
        descricao: 'Avisar sobre novos pedidos disponíveis',
        cor: const Color(0xFF7C3AED),
      ),
      _Item(
        icone: Icons.battery_charging_full,
        titulo: 'Bateria',
        descricao: 'Manter GPS ativo em segundo plano',
        cor: const Color(0xFF059669),
      ),
      _Item(
        icone: Icons.do_not_disturb_on_outlined,
        titulo: 'Não perturbe',
        descricao: 'Tocar o alerta de pedido mesmo nesse modo',
        cor: const Color(0xFFDC2626),
      ),
    ];
  }

  void _confirmarDisclosure() {
    setState(() => _fase = _FaseTela.solicitando);
    _solicitar(0);
  }

  Future<void> _solicitar(int i) async {
    if (i >= _itens.length) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => widget.next),
        );
      }
      return;
    }

    setState(() => _itens[i].status = _Status.processando);

    bool concedida = false;
    try {
      switch (i) {
        case 0:
          // Via LocationPermissionFlow (não Navigator direto pra
          // LocationDisclosureScreen) — é quem marca a conclusão em
          // SharedPreferences; sem isso, a primeira checagem de
          // entregador_home_screen.dart (garantir()) acha que ainda não
          // concluiu e pede de novo a etapa de segundo plano logo em seguida.
          concedida = await LocationPermissionFlow.garantir(context);
          break;
        case 1:
          final ok = await FlutterLocalNotificationsPlugin()
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission();
          concedida = ok == true;
          break;
        case 2:
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
          concedida = true;
          break;
        case 3:
          concedida = await DndPermissionService.garantir();
          break;
      }
    } catch (_) {
      concedida = true;
    }

    setState(() => _itens[i].status =
        concedida ? _Status.concedida : _Status.negada);
    await Future.delayed(const Duration(milliseconds: 700));
    _solicitar(i + 1);
  }

  @override
  Widget build(BuildContext context) {
    final tudo = _itens.every(
        (p) => p.status == _Status.concedida || p.status == _Status.negada);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _fase == _FaseTela.disclosure
              ? _buildDisclosure()
              : Column(
                  children: [
                    const SizedBox(height: 56),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A56DB),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.delivery_dining,
                          color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Permissões necessárias',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Precisamos de acesso para funcionar corretamente durante as entregas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 40),
                    ...List.generate(_itens.length, _buildItem),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: tudo ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 400),
                      child: const Column(
                        children: [
                          Icon(Icons.check_circle,
                              color: Color(0xFF16A34A), size: 36),
                          SizedBox(height: 8),
                          Text('Tudo pronto!',
                              style: TextStyle(
                                  color: Color(0xFF16A34A),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDisclosure() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 56),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF1A56DB),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.delivery_dining,
              color: Colors.white, size: 36),
        ),
        const SizedBox(height: 20),
        const Text(
          'Precisamos de alguns acessos',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF161820),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LinhaDisclosure(
                icone: Icons.location_on,
                cor: Color(0xFF1A56DB),
                texto:
                    "O Let's Go Delivery Parceiro usa sua localização em tempo "
                    'real para exibir corridas disponíveis próximas a você e '
                    'permitir que lojas e clientes acompanhem sua entrega. '
                    'Na próxima tela explicamos os detalhes antes de pedir '
                    'essa permissão.',
              ),
              SizedBox(height: 16),
              _LinhaDisclosure(
                icone: Icons.notifications,
                cor: Color(0xFF7C3AED),
                texto: 'Notificações avisam sobre novos pedidos disponíveis.',
              ),
              SizedBox(height: 16),
              _LinhaDisclosure(
                icone: Icons.battery_charging_full,
                cor: Color(0xFF059669),
                texto:
                    'A exceção de otimização de bateria mantém o GPS ativo '
                    'durante a entrega, mesmo com o app em segundo plano.',
              ),
              SizedBox(height: 16),
              _LinhaDisclosure(
                icone: Icons.do_not_disturb_on_outlined,
                cor: Color(0xFFDC2626),
                texto:
                    'Pedimos também a exceção de "Não perturbe", pra você não '
                    'perder um pedido se o celular estiver nesse modo.',
              ),
            ],
          ),
        ),
        const Spacer(),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _confirmarDisclosure,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A56DB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Continuar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildItem(int i) {
    final p = _itens[i];
    final ativa = p.status == _Status.processando;
    final concluida = p.status == _Status.concedida;
    final negada = p.status == _Status.negada;
    final pendente = p.status == _Status.pendente;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: concluida
            ? const Color(0xFF052E16)
            : negada
                ? const Color(0xFF1C0A0A)
                : ativa
                    ? const Color(0xFF161B2E)
                    : const Color(0xFF161820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: concluida
              ? const Color(0xFF16A34A)
              : negada
                  ? const Color(0xFF7F1D1D)
                  : ativa
                      ? p.cor
                      : const Color(0xFF2A2D35),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: concluida
                  ? const Color(0xFF16A34A).withOpacity(0.2)
                  : negada
                      ? Colors.red.withOpacity(0.1)
                      : p.cor.withOpacity(ativa ? 0.18 : 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              concluida
                  ? Icons.check_circle
                  : negada
                      ? Icons.cancel
                      : p.icone,
              color: concluida
                  ? const Color(0xFF16A34A)
                  : negada
                      ? Colors.red
                      : ativa
                          ? p.cor
                          : Colors.white24,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.titulo,
                  style: TextStyle(
                    color: pendente ? Colors.white38 : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.descricao,
                  style: TextStyle(
                    color: pendente
                        ? Colors.white24
                        : const Color(0xFF9CA3AF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (ativa)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: p.cor),
            )
          else if (concluida)
            const Icon(Icons.check, color: Color(0xFF16A34A), size: 22)
          else if (negada)
            const Icon(Icons.close, color: Colors.red, size: 22)
          else
            const Icon(Icons.lock_outline, color: Colors.white24, size: 22),
        ],
      ),
    );
  }
}

class _LinhaDisclosure extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String texto;

  const _LinhaDisclosure({
    required this.icone,
    required this.cor,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, color: cor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
                color: Color(0xFFD1D5DB), fontSize: 13.5, height: 1.45),
          ),
        ),
      ],
    );
  }
}
