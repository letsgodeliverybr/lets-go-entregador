import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lets_go_entregador/services/location_permission_flow.dart';
import 'package:lets_go_entregador/screens/location_disclosure_screen.dart';

/// Simula o estado de permissão de localização do Android e conta quantas
/// vezes cada método nativo do geolocator é chamado, pra provar que:
/// (1) o disclosure só aparece quando de fato precisa, e
/// (2) "Permitir sempre" não tenta mais abrir um popup nativo que não
///     existe mais no Android 11+ — abre Configurações.
class _FakeGeolocatorPlatform {
  static const _channel = MethodChannel('flutter.baseflow.com/geolocator_android');

  /// 0=denied, 1=deniedForever, 2=whileInUse, 3=always
  int permissaoAtual = 0;
  int chamadasOpenAppSettings = 0;
  int chamadasRequestPermission = 0;

  void instalar() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return permissaoAtual;
        case 'requestPermission':
          chamadasRequestPermission++;
          // No Android real, uma segunda chamada aqui (já com whileInUse)
          // não muda nada — o app não deveria mais depender disso pra
          // conseguir "always".
          if (permissaoAtual == 0) permissaoAtual = 2; // primeira concessão: whileInUse
          return permissaoAtual;
        case 'openAppSettings':
          chamadasOpenAppSettings++;
          return true;
        case 'isLocationServiceEnabled':
          return true;
        default:
          return null;
      }
    });
  }

  void desinstalar() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = _FakeGeolocatorPlatform();

  setUp(() async {
    // Sem isso, Geolocator.checkPermission() não usa o canal de método que
    // estamos mockando — em `flutter test` (plataforma vm) o plugin não é
    // registrado automaticamente como aconteceria num app Android real.
    GeolocatorPlatform.instance = GeolocatorAndroid();
    SharedPreferences.setMockInitialValues({});
    fake.permissaoAtual = 0;
    fake.chamadasOpenAppSettings = 0;
    fake.chamadasRequestPermission = 0;
    fake.instalar();
  });

  tearDown(() => fake.desinstalar());

  Widget appDeTeste(VoidCallback onDisparar) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: onDisparar,
            child: const Text('disparar'),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'ciclo completo: negar -> conceder só-durante-uso -> conceder sempre -> não reabre depois',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      bool? resultado;
      late BuildContext ctx;

      await tester.pumpWidget(appDeTeste(() {}));
      ctx = tester.element(find.byType(ElevatedButton));

      // ── 1ª chamada: permissão totalmente negada (fresh install / 1º login) ──
      fake.permissaoAtual = 0; // denied
      final future1 = LocationPermissionFlow.garantir(ctx);
      await tester.pumpAndSettle();

      // Deve ter navegado pra tela de disclosure completa (foreground).
      expect(find.byType(LocationDisclosureScreen), findsOneWidget);
      expect(find.text('Sua localização'), findsOneWidget);

      // Usuário toca "Continuar" -> pede permissão em uso -> mock concede whileInUse.
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(fake.permissaoAtual, 2); // whileInUse concedida
      expect(fake.chamadasRequestPermission, 1);

      // Deve ter avançado pra etapa de segundo plano (não voltou pro app ainda).
      expect(find.byType(LocationDisclosureScreen), findsOneWidget);
      expect(find.text('Localização em segundo plano'), findsOneWidget);

      // Usuário toca "Abrir configurações" (não deve mais chamar requestPermission).
      await tester.tap(find.text('Abrir configurações'));
      await tester.pumpAndSettle();

      expect(fake.chamadasOpenAppSettings, 1,
          reason: 'segundo plano deve abrir Configurações, não popup nativo');
      expect(fake.chamadasRequestPermission, 1,
          reason: 'não deve tentar requestPermission() de novo pro segundo plano');

      resultado = await future1;
      expect(resultado, isTrue);
      expect(find.byType(LocationDisclosureScreen), findsNothing);

      // Confirma que a conclusão do disclosure ficou persistida.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('location_disclosure_concluido'), isTrue);

      // ── Simula: usuário voltou nas Configurações do Android e ativou
      //    "Permitir o tempo todo" manualmente (fluxo real no Android 11+) ──
      fake.permissaoAtual = 3; // always

      // ── 2ª chamada: simula reabrir o app / voltar de uma entrega /
      //    pedido desalocado — TrackingService.iniciar chamando o gate de novo ──
      final resultado2 = await LocationPermissionFlow.garantir(ctx);
      await tester.pumpAndSettle();

      expect(resultado2, isTrue);
      expect(find.byType(LocationDisclosureScreen), findsNothing,
          reason: 'com "sempre" já concedido, não deve reabrir a tela');

      // ── 3ª chamada, ainda em whileInUse mas já com disclosure concluído
      //    (o caso real mais comum: usuário nunca vai em Configurações,
      //    fica só em "durante o uso") — também não deve reabrir. ──
      fake.permissaoAtual = 2; // whileInUse
      final resultado3 = await LocationPermissionFlow.garantir(ctx);
      await tester.pumpAndSettle();

      expect(resultado3, isTrue);
      expect(find.byType(LocationDisclosureScreen), findsNothing,
          reason: 'já visto uma vez — não deve interromper o fluxo de novo '
              'só por ainda estar em whileInUse');
    },
  );

  testWidgets(
    'permissão revogada depois de já concluído o disclosure -> reabre',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(appDeTeste(() {}));
      ctx = tester.element(find.byType(ElevatedButton));

      // Já tinha passado pelo disclosure antes.
      SharedPreferences.setMockInitialValues({
        'location_disclosure_concluido': true,
      });
      fake.permissaoAtual = 0; // usuário revogou tudo nas configurações

      // Não dá "await" direto: garantir() só retorna quando a tela
      // empurrada for fechada (ex: usuário tocando um botão), e aqui só
      // queremos confirmar que ela reabriu — sem isso o teste trava.
      unawaited(LocationPermissionFlow.garantir(ctx));
      await tester.pumpAndSettle();

      expect(find.byType(LocationDisclosureScreen), findsOneWidget,
          reason: 'permissão revogada (denied) deve reabrir o disclosure '
              'mesmo já tendo sido concluído antes');
    },
  );
}
