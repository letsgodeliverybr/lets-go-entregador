import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Acesso especial do Android 14+ (Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
/// pra permitir que a notificação de novo pedido abra a tela sozinha por cima
/// de qualquer app, igual uma chamada chegando. Sem esse grant, mesmo com
/// fullScreenIntent:true e USE_FULL_SCREEN_INTENT no manifest, o Android 14+
/// rebaixa a notificação pra um heads-up comum.
///
/// Segue o mesmo idioma de [DndPermissionService]: marca em disco quando o
/// motoboy já passou pela solicitação, pra não interromper de novo a cada
/// abertura do app — só volta a pedir se o SO disser que não está mais
/// concedida.
class FullScreenIntentPermissionService {
  static const _channel = MethodChannel('letsgo/fullscreen_intent');
  static const _chaveJaSolicitado = 'fullscreen_intent_disclosure_concluido';

  static Future<bool> isGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  // Abre a tela de configurações direto, sem passar pelo gate de "já
  // solicitei antes, não pergunta de novo" do garantir() abaixo — usado
  // pelo DeviceSetupScreen (gate obrigatório, ação explícita de toque no
  // botão "Ativar"), onde faz sentido sempre reabrir a tela quando pedido,
  // diferente de uma checagem oportunista em background.
  static Future<void> abrirConfiguracoes() async {
    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {}
  }

  static Future<bool> _jaSolicitado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chaveJaSolicitado) ?? false;
  }

  // Público — usado por main.dart (AuthGate) pra decidir se mostra
  // FullScreenIntentRepromptScreen pra um entregador que já passou pelo
  // DeviceSetupScreen antes dessa etapa existir (ver comentário grande em
  // fullscreen_intent_reprompt_screen.dart).
  static Future<bool> jaFoiPerguntado() => _jaSolicitado();

  static Future<void> _marcarSolicitado(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveJaSolicitado, valor);
  }

  // Público, usado por FullScreenIntentRepromptScreen quando o entregador
  // toca "Agora não" — marca como já perguntado mesmo sem ter aberto as
  // configurações, pra não repetir esse prompt em toda abertura do app.
  static Future<void> marcarJaPerguntado() => _marcarSolicitado(true);

  /// Pede o acesso especial se ainda não concedido. Abre a tela de
  /// configurações do Android e espera o usuário voltar pro app pra
  /// reconferir o estado real (o SO não devolve resultado direto desse
  /// intent). Retorna o estado final (concedida ou não).
  static Future<bool> garantir() async {
    if (await isGranted()) {
      await _marcarSolicitado(true);
      return true;
    }

    if (await _jaSolicitado()) {
      // Já pedimos antes; não interrompe de novo a cada abertura do app.
      return false;
    }

    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {
      return false;
    }

    final concedida = await _esperarRetornoDoApp();
    await _marcarSolicitado(concedida);
    return concedida;
  }

  static Future<bool> _esperarRetornoDoApp() async {
    final completer = Completer<bool>();
    late final _ResumeObserver observer;
    final timeout = Timer(const Duration(minutes: 3), () {
      if (!completer.isCompleted) completer.complete(false);
      WidgetsBinding.instance.removeObserver(observer);
    });

    observer = _ResumeObserver(() async {
      if (completer.isCompleted) return;
      final granted = await isGranted();
      completer.complete(granted);
      timeout.cancel();
      WidgetsBinding.instance.removeObserver(observer);
    });
    WidgetsBinding.instance.addObserver(observer);

    return completer.future;
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
