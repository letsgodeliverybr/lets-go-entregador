import 'package:flutter/material.dart';
import '../services/tela_pos_login_service.dart';

// Estado intermediário OBRIGATÓRIO entre "login concluído" e "tela final" —
// 2026-09-09, corrige race condition real encontrada pelo usuário: sem essa
// tela, LoginScreen chamava resolverTelaPosLogin() e só navegava quando
// terminasse, mas nada IMPEDIA fisicamente algum outro trecho (ex: um
// rebuild em cima do Navigator ainda mostrando o frame anterior) de deixar
// o destino final (EntregadorHomeScreen) aparecer por uma fração de segundo
// antes do redirect — confirmado em teste real com conta 'pendente'. Agora
// o fluxo é sempre: LoginScreen -> (pushReplacement imediato) ->
// CarregandoPosLoginScreen (única coisa na tela) -> resolverTelaPosLogin()
// resolve -> pushReplacement pro destino certo. Não tem mais nenhum frame
// entre "saiu do login" e "chegou no destino final" que não seja essa tela.
//
// De propósito SEM duração mínima/animação de marca (diferente da Fase 2 do
// AuthGate, lib/main.dart) — aqui é login ATIVO, o usuário acabou de tocar
// em "Entrar" agora mesmo, então precisa navegar assim que
// resolverTelaPosLogin() terminar, sem atraso artificial nenhum.
class CarregandoPosLoginScreen extends StatefulWidget {
  const CarregandoPosLoginScreen({super.key});

  @override
  State<CarregandoPosLoginScreen> createState() =>
      _CarregandoPosLoginScreenState();
}

class _CarregandoPosLoginScreenState extends State<CarregandoPosLoginScreen> {
  @override
  void initState() {
    super.initState();
    _resolver();
  }

  Future<void> _resolver() async {
    final tela = await resolverTelaPosLogin();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => tela),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image:
                  AssetImage('assets/images/logo_icone_texto_circular.png'),
              width: 200,
            ),
            SizedBox(height: 36),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF1A56DB),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
