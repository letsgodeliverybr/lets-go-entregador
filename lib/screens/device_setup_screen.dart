import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/miui_autostart_service.dart';

/// Tela obrigatória de configuração do aparelho — mostrada uma vez, antes
/// do entregador poder ver pedidos, bloqueando até confirmar. Diferente de
/// [PermissoesScreen] (que pede várias permissões em sequência mas sempre
/// avança, mesmo se negadas): aqui os passos são de verdade obrigatórios,
/// porque sem eles a notificação de novo pedido não toca som — não dá pra
/// depender do entregador descobrir isso sozinho.
///
/// Passo 1 (todo Android): exceção de otimização de bateria — verificável
/// de verdade via FlutterForegroundTask.isIgnoringBatteryOptimizations
/// (já usada em main.dart pro cold-start check; aqui reconfere depois do
/// pedido e não deixa passar se recusado).
/// Passo 2 (só Xiaomi/MIUI): Início automático — sem API do Android pra
/// isso, então a confirmação é manual (checkbox), depois de abrir a tela
/// nativa da MIUI.
///
/// Concluído = grava flag em disco (jaConcluido()) e nunca mais mostra —
/// não reconfere automaticamente se a notificação parar de funcionar depois
/// (fica pra uma versão futura).
class DeviceSetupScreen extends StatefulWidget {
  final Widget next;
  const DeviceSetupScreen({super.key, required this.next});

  static const _chaveConcluido = 'device_setup_concluido';

  static Future<bool> jaConcluido() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chaveConcluido) ?? false;
  }

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

enum _Etapa { carregando, bateria, autostart }

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  _Etapa _etapa = _Etapa.carregando;
  bool _isXiaomi = false;
  bool _bateriaNegadaUmaVez = false;
  bool _autostartAbriu = false;
  bool _autostartCheckbox = false;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    _isXiaomi = await MiuiAutostartService.isXiaomi();
    await _checarBateria();
  }

  Future<void> _checarBateria() async {
    final ignorando = await _isIgnoringBatteryOptimizations();
    if (ignorando) {
      _avancarParaAutostartOuFim();
    } else if (mounted) {
      setState(() => _etapa = _Etapa.bateria);
    }
  }

  Future<bool> _isIgnoringBatteryOptimizations() async {
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  void _avancarParaAutostartOuFim() {
    if (_isXiaomi) {
      if (mounted) setState(() => _etapa = _Etapa.autostart);
    } else {
      _finalizar();
    }
  }

  Future<void> _finalizar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(DeviceSetupScreen._chaveConcluido, true);
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => widget.next));
  }

  Future<void> _pedirBateria() async {
    if (_processando) return;
    setState(() {
      _processando = true;
      _bateriaNegadaUmaVez = false;
    });
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {}
    final ignorando = await _esperarRetornoDoApp(_isIgnoringBatteryOptimizations);
    if (!mounted) return;
    setState(() => _processando = false);
    if (ignorando) {
      _avancarParaAutostartOuFim();
    } else {
      setState(() => _bateriaNegadaUmaVez = true);
    }
  }

  Future<void> _abrirAutostart() async {
    setState(() => _autostartAbriu = true);
    await MiuiAutostartService.openAutostartSettings();
  }

  // Mesmo idioma de DndPermissionService/FullScreenIntentPermissionService —
  // o Android não devolve resultado direto do intent de bateria; espera o
  // app voltar ao primeiro plano (resumed) pra reconferir o estado real.
  Future<bool> _esperarRetornoDoApp(Future<bool> Function() checar) async {
    final completer = Completer<bool>();
    late final _ResumeObserver observer;
    final timeout = Timer(const Duration(minutes: 3), () {
      if (!completer.isCompleted) completer.complete(false);
      WidgetsBinding.instance.removeObserver(observer);
    });

    observer = _ResumeObserver(() async {
      if (completer.isCompleted) return;
      final ok = await checar();
      completer.complete(ok);
      timeout.cancel();
      WidgetsBinding.instance.removeObserver(observer);
    });
    WidgetsBinding.instance.addObserver(observer);

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: switch (_etapa) {
            _Etapa.carregando => const Center(
                child: CircularProgressIndicator(color: Color(0xFF1A56DB)),
              ),
            _Etapa.bateria => _buildBateria(),
            _Etapa.autostart => _buildAutostart(),
          },
        ),
      ),
    );
  }

  Widget _cabecalho(IconData icone, Color cor, String titulo, String subtitulo) {
    return Column(
      children: [
        const SizedBox(height: 56),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(18)),
          child: Icon(icone, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 20),
        Text(titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(subtitulo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.4)),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildBateria() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecalho(
          Icons.battery_charging_full,
          const Color(0xFF059669),
          'Uma última configuração',
          'Pra receber notificação de pedido novo mesmo com o app fechado, '
              'seu celular precisa parar de "otimizar a bateria" desse app. '
              'Sem isso, o Android pode fechar o app sozinho e a notificação '
              'não toca.',
        ),
        if (_bateriaNegadaUmaVez)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C0A0A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF7F1D1D)),
            ),
            child: const Text(
              'Ainda não foi ativado. Isso é obrigatório — sem essa permissão, '
              'você pode perder pedidos novos sem perceber. Toca em "Ativar" '
              'de novo e escolhe "Permitir" na tela do sistema.',
              style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 13, height: 1.4),
            ),
          ),
        const Spacer(),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _processando ? null : _pedirBateria,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
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
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildAutostart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecalho(
          Icons.rocket_launch,
          const Color(0xFFEA580C),
          'Seu celular é Xiaomi',
          'Celulares Xiaomi (MIUI) têm um bloqueio próprio, separado do '
              'Android normal, que impede o app de tocar o som do pedido se o '
              '"Início automático" não estiver ativado. Sem isso, mesmo com '
              'tudo certo, a notificação chega muda.',
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161820),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2D35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Passo a passo:',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              const Text(
                '1. Toca no botão abaixo pra abrir a tela de Início automático.\n'
                '2. Procura "Let\'s Go Entregador" na lista.\n'
                '3. Ativa o toggle ao lado do nome do app.\n'
                '4. Volta aqui e marca a confirmação abaixo.',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: _abrirAutostart,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEA580C),
              side: const BorderSide(color: Color(0xFFEA580C)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Abrir Início automático', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 20),
        if (_autostartAbriu)
          InkWell(
            onTap: () => setState(() => _autostartCheckbox = !_autostartCheckbox),
            child: Row(
              children: [
                Checkbox(
                  value: _autostartCheckbox,
                  activeColor: const Color(0xFFEA580C),
                  onChanged: (v) => setState(() => _autostartCheckbox = v ?? false),
                ),
                const Expanded(
                  child: Text('Já ativei o Início automático pra esse app',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ],
            ),
          ),
        const Spacer(),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: (_autostartAbriu && _autostartCheckbox) ? _finalizar : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A56DB),
              disabledBackgroundColor: const Color(0xFF1A56DB).withOpacity(0.3),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ResumeObserver extends WidgetsBindingObserver {
  final Future<void> Function() onResume;
  _ResumeObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
