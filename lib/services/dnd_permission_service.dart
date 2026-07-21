import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Permissão especial do Android para o app tocar som mesmo com o aparelho
/// em modo "Não perturbe" (Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).
/// Sem ela, o canal de notificação de novo pedido pode ficar mudo mesmo com
/// tudo o resto (FCM, canal, som customizado) funcionando corretamente.
///
/// Segue o mesmo idioma de [LocationPermissionFlow]: marca em disco
/// (SharedPreferences) quando o motoboy já passou pela solicitação, pra não
/// interromper de novo a cada abertura do app — só volta a pedir se o SO
/// disser que a permissão não está mais concedida.
class DndPermissionService {
  static const _channel = MethodChannel('letsgo/dnd');
  static const _chaveJaSolicitado = 'dnd_disclosure_concluido';

  static Future<bool> isGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _jaSolicitado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chaveJaSolicitado) ?? false;
  }

  static Future<void> _marcarSolicitado(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveJaSolicitado, valor);
  }

  /// Pede a exceção de Não Perturbe se ainda não concedida. Abre a tela de
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
