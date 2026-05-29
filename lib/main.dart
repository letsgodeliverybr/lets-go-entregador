import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/entregador_home_screen.dart';
import 'screens/pedidos_disponiveis_screen.dart';
import 'screens/extrato_screen.dart';
import 'services/notification_service.dart';

// Handler de mensagem FCM com app fechado — top-level obrigatório.
// Roda em isolate separado: mostra notificação de alta prioridade com o
// som letsgo configurado no canal. Áudio 10x requer app em foreground.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await NotificationService.initLocal();
  await NotificationService.showNovoPedidoLocal();
}

Future<void> _salvarFcmToken(String token) async {
  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await Supabase.instance.client
        .from('entregadores')
        .update({'fcm_token': token})
        .eq('id', user.id);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  // Registra handler de background antes de qualquer listener
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

  await Supabase.initialize(
    url: 'https://astbkmpegcmqljltmdpx.supabase.co',
    anonKey: 'sb_publishable_8ocBGGO6EM8GYlg-6HBdmQ_LA6VDL9O',
  );

  await NotificationService.initLocal();

  // Permissão FCM (Android 13+)
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Salva token atual e escuta renovações
  final fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken != null) _salvarFcmToken(fcmToken);
  FirebaseMessaging.instance.onTokenRefresh.listen(_salvarFcmToken);

  // Notificações FCM com app em foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    await NotificationService.showNovoPedidoLocal();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return MaterialApp(
      title: 'Lets Go Delivery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A56DB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: session != null
          ? const EntregadorHomeScreen()
          : const LoginScreen(),
      routes: {
        '/pedidos': (context) => const PedidosDisponiveisScreen(),
        '/login':   (context) => const LoginScreen(),
        '/extrato': (context) => const ExtratoScreen(),
      },
    );
  }
}
