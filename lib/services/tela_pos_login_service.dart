import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../screens/login_screen.dart';
import '../screens/permissoes_screen.dart';
import '../screens/home_screen.dart';
import '../screens/entregador_home_screen.dart';
import '../screens/pedidos_disponiveis_screen.dart';
import '../screens/aguardo_aprovacao_screen.dart';
import '../screens/device_setup_screen.dart';
import '../screens/fullscreen_intent_reprompt_screen.dart';
import 'notification_service.dart';
import 'fullscreen_intent_permission_service.dart';

// Fonte única do gate de cadastro/permissões (2026-09-09, correção de
// brecha de segurança) — usada tanto pelo cold start do app (AuthGate,
// main.dart) quanto pelo login ativo (LoginScreen._fazerLogin). Antes
// dessa extração, LoginScreen navegava direto pra HomeScreen() depois de
// signInWithPassword(), sem passar por nenhuma checagem de documento
// aprovado — um entregador reprovado/em_análise conseguia navegar pelo
// app inteiro (mapa, telas internas) e só era barrado ao tentar ficar
// online. Cold start (AuthGate) sempre checou certo; login ativo, não.
// Mover a lógica pra cá garante que os dois caminhos cheguem exatamente
// no mesmo resultado — não dá mais pra um deles "esquecer" o gate.
Future<Widget> resolverTelaPosLogin() async {
  final tela = await _resolverTelaSemSetup();
  if (!await DeviceSetupScreen.jaConcluido()) {
    return DeviceSetupScreen(next: tela);
  }
  // Entregador já concluiu o setup obrigatório ANTES da etapa de
  // Full-Screen-Intent existir (jaConcluido() é uma flag única e global —
  // quem já passou por ela nunca mais vê DeviceSetupScreen, e por
  // consequência nunca seria perguntado sobre essa permissão
  // especificamente). Achado em auditoria 2026-09-02: pra apps não
  // classificados como chamada/alarme (nosso caso), o Google NÃO concede
  // essa permissão automaticamente desde 22/01/2025 — sem perguntar
  // ativamente, boa parte da base instalada nunca teria essa permissão,
  // mesmo com todo o resto do fluxo (som/vibração/loop) funcionando
  // normal. Não-bloqueante — "Agora não" sempre disponível, ver
  // fullscreen_intent_reprompt_screen.dart. Só perguntado uma vez
  // (jaFoiPerguntado()), independente de session != null aqui porque não
  // faz sentido perguntar antes do login existir.
  final session = Supabase.instance.client.auth.currentSession;
  if (session != null &&
      !await FullScreenIntentPermissionService.isGranted() &&
      !await FullScreenIntentPermissionService.jaFoiPerguntado()) {
    return FullScreenIntentRepromptScreen(next: tela);
  }
  return tela;
}

Future<Widget> _resolverTelaSemSetup() async {
  final locPerm = await Geolocator.checkPermission();
  final locFaltando = locPerm == LocationPermission.denied ||
      locPerm == LocationPermission.deniedForever;

  final notifOk = await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled() ??
      true;
  final notifFaltando = !notifOk;

  bool bateriaFaltando = false;
  try {
    final ignorandoOtimizacao =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    bateriaFaltando = !ignorandoOtimizacao;
  } catch (_) {}

  final precisaPermissoes = locFaltando || notifFaltando || bateriaFaltando;

  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) {
    if (precisaPermissoes) return const PermissoesScreen(next: LoginScreen());
    return const LoginScreen();
  }

  await NotificationService.saveFcmToken(session.user.id);

  try {
    final e = await Supabase.instance.client
        .from('entregadores')
        .select(
            'disponivel, status_cadastro, aprovado, status, '
            'foto_perfil_status, foto_cnh_status, foto_crlv_status, '
            'foto_comprovante_residencia_status, foto_placa_status')
        .eq('id', session.user.id)
        .single();

    final status = e['status']?.toString() ?? '';

    // Gate real fica nos 5 documentos, não em status_cadastro/aprovado
    // (auditoria 2026-09-08) — esses dois continuam existindo só como
    // espelho pro painel (badge/filtro/listagem), o painel já mantém os
    // dois em sincronia com os documentos (ver app.js,
    // _recalcularStatusCadastro), mas o app não pode CONFIAR nisso: se
    // esse espelho um dia dessincronizar por algum bug do lado do
    // painel, o gate real ainda precisa checar a fonte, não o reflexo.
    // status=='bloqueado' trava sempre, mesmo com os 5 aprovados — é um
    // kill-switch independente do admin, não relacionado a documento.
    const camposDocumento = [
      'foto_perfil_status',
      'foto_cnh_status',
      'foto_crlv_status',
      'foto_comprovante_residencia_status',
      'foto_placa_status',
    ];
    final todosDocumentosAprovados =
        camposDocumento.every((c) => e[c]?.toString() == 'aprovado');

    if (status != 'bloqueado' && todosDocumentosAprovados) {
      if (e['disponivel'] == true) {
        // App estava fechado/morto e foi aberto pelo fullScreenIntent da
        // notificação de novo pedido (não por toque manual) — nesse caso
        // onDidReceiveNotificationResponse (notification_service.dart)
        // não dispara, porque o plugin de notificações locais ainda não
        // tinha listener registrado no momento em que o Android lançou a
        // Activity. getNotificationAppLaunchDetails() é o jeito
        // documentado do flutter_local_notifications de recuperar esse
        // dado depois, direto no cold start.
        try {
          final detalhes = await FlutterLocalNotificationsPlugin()
              .getNotificationAppLaunchDetails();
          if (detalhes?.didNotificationLaunchApp == true &&
              detalhes?.notificationResponse?.payload == 'novo_pedido') {
            // App estava morto/background e só ficou "vivo" de verdade
            // agora via fullScreenIntent — o alerta insistente (canal
            // nativo, FLAG_INSISTENT) já estava tocando sozinho desde a
            // chegada da notificação, sem depender disso; só resta
            // navegar direto pra tela certa.
            return const PedidosDisponiveisScreen();
          }
        } catch (_) {}
        return const EntregadorHomeScreen();
      }
      return const HomeScreen();
    }

    return const AguardoAprovacaoScreen();
  } catch (_) {
    return const LoginScreen();
  }
}
