import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Confirmação de entrega própria do iFood, DENTRO do app (WebView, não
// navegador externo) — pra manter o entregador no nosso fluxo. Serviço
// público oficial do iFood (confirmacao-entrega-propria.ifood.com.br),
// não pede Merchant ID/CNPJ da loja, feito exatamente pra esse caso.
//
// Sem pré-preenchimento do código do PEDIDO/CLIENTE: investigação no bundle
// JS da página não achou mecanismo de query string pra isso — o :orderUuid
// usado nas rotas internas da página só é resolvido DEPOIS que o próprio
// site consulta a API deles a partir do número do pedido digitado. Abre a
// URL real, igual o entregador acessaria fora do app.
//
// Independente do que acontecer aqui (confirmado ou não no iFood), o
// fluxo de finalizar entrega no NOSSO sistema continua normal — essa
// tela não registra nada sozinha, só mostra a página e fecha quando o
// entregador quiser.
//
// ── Recoloração pra azul (item 1) ──────────────────────────────────────
// A página não usa CSS custom properties pra cor (conferido no bundle CSS
// publicado — só 3 variáveis, nenhuma de cor) e o botão/barra de progresso
// aparentam vir de um design system com estilo injetado em runtime (não
// aparecem no CSS estático), então sobrescrever seletor fixo por seletor
// fixo seria frágil e quebraria no primeiro redesign deles. Em vez disso,
// varre o DOM inteiro lendo a cor JÁ COMPUTADA (getComputedStyle) de cada
// elemento — funciona não importa se a cor vem de classe CSS, style inline
// ou CSS-in-JS, e não depende de nome de classe nenhum. Reaplica com
// MutationObserver porque é uma SPA (troca de tela = re-render React, sem
// reload de página → onPageFinished só dispara uma vez). Sem CSP na
// resposta do servidor nem <meta> de CSP no HTML (conferido antes de
// implementar) — a injeção via runJavaScript não é bloqueada.
//
// ── Botão cortado (item 2) ──────────────────────────────────────────────
// Causa provável: desde que subimos targetSdkVersion pra 36 (Android 16),
// edge-to-edge é obrigatório e não dá mais pra desligar — a janela do app
// passou a desenhar por baixo da barra de gestos do sistema. O Stack com a
// WebView não tinha SafeArea nenhuma, então a página (que já pede
// viewport-fit=cover) via mais altura "visível" do que realmente tinha
// livre de verdade, empurrando o footer fixo (que tem o botão
// "Cheguei no local"/"Continuar") pra debaixo da área de gestos.
//
// ── Câmera + OCR do código (item 3) ─────────────────────────────────────
// Só a tela "OrderNumber" (rota /numero-pedido, campo de 8 dígitos) tem
// esse botão — descoberto lendo o bundle JS: data-testid="order-number-
// -input", numInputs:8, um <input> por dígito (padrão de biblioteca de
// OTP-input, não é um <input maxlength=8> único). Preenche digitando em
// cada input separado, via setter nativo do HTMLInputElement (bypassa o
// tracking de valor do React) + evento 'input' de verdade, senão o React
// não percebe a mudança. Detecta em qual tela a SPA está via
// history.pushState/popstate hookado e reportado por JavaScript Channel —
// não dá pra confiar só no onPageFinished (SPA não recarrega a página ao
// trocar de tela interna).
class IfoodConfirmacaoWebviewScreen extends StatefulWidget {
  const IfoodConfirmacaoWebviewScreen({super.key});

  @override
  State<IfoodConfirmacaoWebviewScreen> createState() => _IfoodConfirmacaoWebviewScreenState();
}

class _IfoodConfirmacaoWebviewScreenState extends State<IfoodConfirmacaoWebviewScreen> {
  static const _url = 'https://confirmacao-entrega-propria.ifood.com.br/';
  static const _corAzul = Color(0xFF1A56DB);

  late final WebViewController _controller;
  bool _carregando = true;
  String? _erro;
  bool _naTelaNumeroPedido = false;
  bool _lendoOcr = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LetsGoRota',
        onMessageReceived: (msg) {
          final naTela = msg.message.contains('numero-pedido') || msg.message == '/';
          if (mounted && naTela != _naTelaNumeroPedido) setState(() => _naTelaNumeroPedido = naTela);
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() { _carregando = true; _erro = null; });
        },
        onPageFinished: (_) async {
          if (mounted) setState(() => _carregando = false);
          await _injetarObservadores();
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
    setState(() { _erro = null; _carregando = true; _naTelaNumeroPedido = false; });
    await _controller.reload();
  }

  // Injeta os dois observadores (cor + rota atual) de uma vez só —
  // idempotente (window.__letsgoInjetado), então rodar de novo depois de um
  // reload não duplica listener.
  Future<void> _injetarObservadores() async {
    try {
      await _controller.runJavaScript(_jsObservadores);
    } catch (_) {
      // Silencioso de propósito: se a injeção falhar (ex: página ainda não
      // terminou de montar), a página do iFood continua 100% funcional no
      // vermelho original — só perde o reskin, não trava nada pro
      // entregador.
    }
  }

  Future<void> _abrirCameraOcr() async {
    if (_lendoOcr) return;
    setState(() => _lendoOcr = true);
    TextRecognizer? recognizer;
    try {
      final picker = ImagePicker();
      final foto = await picker.pickImage(source: ImageSource.camera, imageQuality: 90, preferredCameraDevice: CameraDevice.rear);
      if (foto == null) return;
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final resultado = await recognizer.processImage(InputImage.fromFilePath(foto.path));
      final codigoDetectado = _extrairCodigo8Digitos(resultado);
      if (!mounted) return;
      final codigoConfirmado = await _confirmarCodigoDialog(codigoDetectado);
      if (codigoConfirmado != null && codigoConfirmado.length == 8) {
        await _preencherCodigoNaPagina(codigoConfirmado);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao ler a foto: $e'), backgroundColor: Colors.red));
      }
    } finally {
      await recognizer?.close();
      if (mounted) setState(() => _lendoOcr = false);
    }
  }

  // Tenta achar 8 dígitos com precisão em vez de só pegar os 8 primeiros
  // números do texto inteiro (a notinha pode ter outros números — telefone,
  // CNPJ, valor). 1ª tentativa: uma LINHA reconhecida cujo total de dígitos
  // (ignorando espaço/traço) dá exatamente 8 — mais confiável, porque o
  // código costuma vir sozinho numa linha própria. Se não achar em nenhuma
  // linha, cai pro texto inteiro procurando uma sequência de dígitos
  // isolada (não colada em outros números) de tamanho 8.
  String? _extrairCodigo8Digitos(RecognizedText resultado) {
    for (final bloco in resultado.blocks) {
      for (final linha in bloco.lines) {
        final soDigitos = linha.text.replaceAll(RegExp(r'[^0-9]'), '');
        if (soDigitos.length == 8) return soDigitos;
      }
    }
    final match = RegExp(r'(?<!\d)\d{8}(?!\d)').firstMatch(resultado.text);
    return match?.group(0);
  }

  // Diálogo de confirmação visual — OCR pode errar dígito, então SEMPRE
  // mostra antes de usar, com o campo editável (pré-preenchido com o que
  // foi lido, ou vazio se não achou nada — digitação manual continua
  // funcionando como fallback mesmo com OCR zerado).
  Future<String?> _confirmarCodigoDialog(String? codigoSugerido) async {
    final controller = TextEditingController(text: codigoSugerido ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B1B1B),
          title: Text(
            codigoSugerido == null ? 'Não consegui ler o código' : 'Confere o código',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (codigoSugerido == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('Digita o código de 8 dígitos manualmente.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(counterText: ''),
              onChanged: (_) => setDialogState(() {}),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: controller.text.length == 8 ? () => Navigator.pop(ctx, controller.text) : null,
              style: ElevatedButton.styleFrom(backgroundColor: _corAzul, foregroundColor: Colors.white),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _preencherCodigoNaPagina(String codigo) async {
    final digitosJs = codigo.split('').map((d) => "'$d'").join(',');
    try {
      final resultado = await _controller.runJavaScriptReturningResult(_jsPreencherCodigo.replaceFirst('__DIGITOS__', '[$digitosJs]'));
      final ok = resultado.toString().replaceAll('"', '') == 'OK';
      if (mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não encontrei o campo de código nessa tela. Confirma que você está em "Qual o código localizador do pedido?" e tenta de novo.'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao preencher o código: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: _corAzul,
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
      // SafeArea aqui é o fix do item 2 — sem isso, com targetSdk 36
      // (edge-to-edge obrigatório), a WebView desenha por baixo da barra de
      // gestos do Android e o footer fixo da página (botão "Cheguei no
      // local"/"Continuar") fica inacessível.
      body: SafeArea(
        top: false,
        child: Stack(
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
                      style: ElevatedButton.styleFrom(backgroundColor: _corAzul, foregroundColor: Colors.white),
                      child: const Text('Tentar de novo'),
                    ),
                  ]),
                ),
              ),
            if (_carregando && _erro == null)
              const Center(child: CircularProgressIndicator(color: _corAzul)),
            // Item 3 — só aparece na tela "Qual o código localizador do
            // pedido?" (os 8 dígitos), detectada via LetsGoRota. Fica acima
            // do footer da página (não colado no fundo) pra não brigar com
            // o botão "Continuar" deles.
            if (_naTelaNumeroPedido && _erro == null)
              Positioned(
                right: 16,
                bottom: 88,
                child: FloatingActionButton(
                  heroTag: 'ifood-ocr-camera',
                  backgroundColor: _corAzul,
                  onPressed: _lendoOcr ? null : _abrirCameraOcr,
                  child: _lendoOcr
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Icon(Icons.camera_alt_rounded, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Hookado uma vez só (window.__letsgoInjetado) — seguro rodar de novo em
// cada onPageFinished (ex: depois de um "Recarregar" manual).
const _jsObservadores = r'''
(function(){
  if (window.__letsgoInjetado) return;
  window.__letsgoInjetado = true;

  // ── Reportar rota atual pro Flutter (pra saber quando mostrar o botão
  // de câmera) — SPA troca de tela via history API, sem reload de página.
  function informarRota() {
    try { LetsGoRota.postMessage(location.pathname); } catch (e) {}
  }
  var _push = history.pushState;
  history.pushState = function() { _push.apply(history, arguments); informarRota(); };
  var _replace = history.replaceState;
  history.replaceState = function() { _replace.apply(history, arguments); informarRota(); };
  window.addEventListener('popstate', informarRota);
  informarRota();

  // ── Recoloração vermelho -> azul, baseada em cor computada real (não em
  // seletor/classe) — ver comentário grande no topo do .dart sobre o porquê.
  var AZUL = 'rgb(26, 86, 219)';
  var AZUL_CLARO = 'rgb(235, 243, 255)';
  var AZUL_ESCURO = 'rgb(18, 63, 158)';

  function parseRgb(str) {
    if (!str) return null;
    var m = str.match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    var partes = m[1].split(',').map(function(s){ return parseFloat(s.trim()); });
    if (partes.length < 3) return null;
    return { r: partes[0], g: partes[1], b: partes[2] };
  }

  function ehVermelho(c) {
    return !!c && c.r > 140 && (c.r - c.g) > 35 && (c.r - c.b) > 15;
  }

  function corSubstituta(c) {
    var luz = (c.r + c.g + c.b) / 3;
    if (luz > 195) return AZUL_CLARO;
    if (luz < 90) return AZUL_ESCURO;
    return AZUL;
  }

  function classeTexto(el) {
    var c = el.className;
    if (typeof c === 'string') return c;
    if (c && typeof c.baseVal === 'string') return c.baseVal;
    return '';
  }

  function aplicarEm(el) {
    // Não mexe em mensagem de erro/aviso (semântica de cor importa ali —
    // vermelho continua significando "deu errado").
    if (/error|erro/i.test(classeTexto(el))) return;
    var cs = window.getComputedStyle(el);
    var bg = parseRgb(cs.backgroundColor);
    if (ehVermelho(bg)) el.style.setProperty('background-color', corSubstituta(bg), 'important');
    var cor = parseRgb(cs.color);
    if (ehVermelho(cor)) el.style.setProperty('color', corSubstituta(cor), 'important');
    var borda = parseRgb(cs.borderColor);
    if (ehVermelho(borda)) el.style.setProperty('border-color', corSubstituta(borda), 'important');
    var tag = el.tagName;
    if (tag === 'svg' || tag === 'SVG' || tag === 'path' || tag === 'PATH' || tag === 'circle' || tag === 'CIRCLE' || tag === 'rect' || tag === 'RECT') {
      var preench = parseRgb(cs.fill);
      if (ehVermelho(preench)) el.style.setProperty('fill', corSubstituta(preench), 'important');
      var contorno = parseRgb(cs.stroke);
      if (ehVermelho(contorno)) el.style.setProperty('stroke', corSubstituta(contorno), 'important');
    }
  }

  function varrer() {
    try {
      var todos = document.querySelectorAll('*');
      for (var i = 0; i < todos.length; i++) aplicarEm(todos[i]);
      var meta = document.querySelector('meta[name="theme-color"]');
      if (meta) meta.setAttribute('content', '#1A56DB');
    } catch (e) {}
  }

  varrer();
  setTimeout(varrer, 400);
  setTimeout(varrer, 1200);
  setTimeout(varrer, 2500);

  var pendente = null;
  new MutationObserver(function() {
    if (pendente) clearTimeout(pendente);
    pendente = setTimeout(varrer, 150);
  }).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style'] });
})();
true;
''';

// __DIGITOS__ é substituído em runtime por um array JS tipo ['1','2',...].
// Usa o setter nativo de HTMLInputElement (bypassa o value-tracking interno
// do React) + dispatch de evento 'input' de verdade — só setar
// input.value direto NÃO dispara o onChange do React, o campo pareceria
// preenchido visualmente mas o estado interno da página continuaria vazio
// e o botão "Continuar" continuaria desabilitado.
const _jsPreencherCodigo = r'''
(function(){
  try {
    var wrapper = document.querySelector('[data-testid="order-number-input"]');
    if (!wrapper) return 'NO_WRAPPER';
    var inputs = wrapper.querySelectorAll('input');
    if (inputs.length !== 8) return 'WRONG_COUNT';
    var digitos = __DIGITOS__;
    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    for (var i = 0; i < 8; i++) {
      setter.call(inputs[i], digitos[i]);
      inputs[i].dispatchEvent(new Event('input', { bubbles: true }));
      inputs[i].dispatchEvent(new Event('change', { bubbles: true }));
    }
    return 'OK';
  } catch (e) {
    return 'ERRO:' + e.message;
  }
})();
''';
