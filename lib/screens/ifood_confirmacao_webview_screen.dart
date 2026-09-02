import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Confirmação de entrega própria do iFood, DENTRO do app (WebView, não
// navegador externo) — pra manter o entregador no nosso fluxo. Serviço
// público oficial do iFood (confirmacao-entrega-propria.ifood.com.br),
// não pede Merchant ID/CNPJ da loja, feito exatamente pra esse caso.
//
// Sem pré-preenchimento: investigação no bundle JS da página (sem
// ferramenta de navegador disponível pra testar ao vivo) não achou
// mecanismo de query string pra isso — o :orderUuid usado nas rotas
// internas da página só é resolvido DEPOIS que o próprio site consulta a
// API deles a partir do número do pedido digitado, então não dá pra
// simplesmente montar um link direto com segurança. Abre a URL real,
// igual o entregador acessaria fora do app — ele digita o número do
// pedido e o código lá dentro mesmo.
//
// Independente do que acontecer aqui (confirmado ou não no iFood), o
// fluxo de finalizar entrega no NOSSO sistema continua normal — essa
// tela não registra nada sozinha, só mostra a página e fecha quando o
// entregador quiser.
class IfoodConfirmacaoWebviewScreen extends StatefulWidget {
  const IfoodConfirmacaoWebviewScreen({super.key});

  @override
  State<IfoodConfirmacaoWebviewScreen> createState() => _IfoodConfirmacaoWebviewScreenState();
}

class _IfoodConfirmacaoWebviewScreenState extends State<IfoodConfirmacaoWebviewScreen> {
  static const _url = 'https://confirmacao-entrega-propria.ifood.com.br/';

  late final WebViewController _controller;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() { _carregando = true; _erro = null; });
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _carregando = false);
        },
        onWebResourceError: (error) {
          // Só marca erro pra falha do frame principal — recurso
          // secundário (analytics, fonte, etc.) não deve travar a tela
          // toda com uma mensagem de erro por causa de algo irrelevante.
          if (error.isForMainFrame != false && mounted) {
            setState(() {
              _carregando = false;
              _erro = 'Não foi possível carregar a página do iFood. Confira sua internet e tenta de novo.';
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(_url));
  }

  Future<void> _recarregar() async {
    setState(() { _erro = null; _carregando = true; });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEA1D2C),
        foregroundColor: Colors.white,
        title: const Text('Confirmar no iFood', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _carregando ? null : _recarregar,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Fechar e voltar',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_erro == null) WebViewWidget(controller: _controller),
          if (_erro != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 56),
                  const SizedBox(height: 16),
                  Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _recarregar,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA1D2C), foregroundColor: Colors.white),
                    child: const Text('Tentar de novo'),
                  ),
                ]),
              ),
            ),
          if (_carregando && _erro == null)
            const Center(child: CircularProgressIndicator(color: Color(0xFFEA1D2C))),
        ],
      ),
    );
  }
}
