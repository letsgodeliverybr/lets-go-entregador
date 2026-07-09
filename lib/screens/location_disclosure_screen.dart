import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

enum _Fase {
  foreground,
  solicitandoForeground,
  background,
  solicitandoBackground,
  negado,
}

/// Declaração em destaque (prominent disclosure) exibida ANTES de qualquer
/// popup nativo de permissão de localização, conforme exigido pela política
/// do Google Play. Faz o pedido em duas etapas separadas: primeiro a
/// localização em uso (whileInUse), depois — com uma explicação própria e
/// mais explícita — a localização em segundo plano (always).
///
/// Retorna `true` via Navigator.pop se a localização em uso foi concedida
/// (segundo plano é best-effort: seguir sem ela ainda retorna `true`).
class LocationDisclosureScreen extends StatefulWidget {
  /// Quando `true`, pula direto para a etapa de segundo plano — usado
  /// quando a localização em uso já foi concedida anteriormente e só falta
  /// a permissão de segundo plano.
  final bool apenasBackground;

  const LocationDisclosureScreen({super.key, this.apenasBackground = false});

  @override
  State<LocationDisclosureScreen> createState() =>
      _LocationDisclosureScreenState();
}

class _LocationDisclosureScreenState extends State<LocationDisclosureScreen> {
  late _Fase _fase =
      widget.apenasBackground ? _Fase.background : _Fase.foreground;

  Future<void> _solicitarForeground() async {
    setState(() => _fase = _Fase.solicitandoForeground);
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      setState(() => _fase = _Fase.negado);
      return;
    }
    if (perm == LocationPermission.always) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _fase = _Fase.background);
  }

  Future<void> _solicitarBackground() async {
    setState(() => _fase = _Fase.solicitandoBackground);
    await Geolocator.requestPermission();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _pularBackground() => Navigator.pop(context, true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _buildConteudo(),
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    switch (_fase) {
      case _Fase.foreground:
        return _Disclosure(
          icone: Icons.my_location,
          corIcone: const Color(0xFF1A56DB),
          titulo: 'Sua localização',
          paragrafos: const [
            "O Let's Go Delivery Parceiro usa sua localização em tempo real "
                'para exibir corridas disponíveis próximas a você e permitir '
                'que lojas e clientes acompanhem sua entrega.',
            'A seguir o Android vai pedir essa permissão — toque em '
                '"Permitir" para continuar usando o app normalmente.',
          ],
          botaoTexto: 'Continuar',
          onBotao: _solicitarForeground,
        );
      case _Fase.solicitandoForeground:
      case _Fase.solicitandoBackground:
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFF1A56DB)),
        );
      case _Fase.background:
        return _Disclosure(
          icone: Icons.location_history,
          corIcone: const Color(0xFFf59e0b),
          titulo: 'Localização em segundo plano',
          destaque: true,
          paragrafos: const [
            'Enquanto você estiver disponível para receber corridas ou com '
                'uma entrega em andamento, o app também acessa sua '
                'localização com a tela bloqueada ou minimizada.',
            'Isso é necessário para o rastreamento da entrega em tempo real '
                '— sem ele, lojas e clientes não conseguem acompanhar onde '
                'você está durante o trajeto.',
            'No próximo passo, escolha a opção "Permitir o tempo todo" '
                'quando o Android perguntar.',
          ],
          botaoTexto: 'Permitir sempre',
          onBotao: _solicitarBackground,
          botaoSecundarioTexto: 'Agora não',
          onBotaoSecundario: _pularBackground,
        );
      case _Fase.negado:
        return _Disclosure(
          icone: Icons.location_off,
          corIcone: const Color(0xFFef4444),
          titulo: 'Permissão necessária',
          paragrafos: const [
            'Sem acesso à localização não é possível exibir corridas nem '
                'permitir que lojas e clientes acompanhem sua entrega.',
            'Toque em "Tentar novamente" para conceder a permissão.',
          ],
          botaoTexto: 'Tentar novamente',
          onBotao: _solicitarForeground,
          botaoSecundarioTexto: 'Voltar',
          onBotaoSecundario: () => Navigator.pop(context, false),
        );
    }
  }
}

class _Disclosure extends StatelessWidget {
  final IconData icone;
  final Color corIcone;
  final String titulo;
  final List<String> paragrafos;
  final String botaoTexto;
  final VoidCallback onBotao;
  final String? botaoSecundarioTexto;
  final VoidCallback? onBotaoSecundario;
  final bool destaque;

  const _Disclosure({
    required this.icone,
    required this.corIcone,
    required this.titulo,
    required this.paragrafos,
    required this.botaoTexto,
    required this.onBotao,
    this.botaoSecundarioTexto,
    this.onBotaoSecundario,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 56),
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: corIcone.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icone, color: corIcone, size: 38),
        ),
        const SizedBox(height: 24),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: destaque
                ? const Color(0xFFf59e0b).withOpacity(0.08)
                : const Color(0xFF161820),
            borderRadius: BorderRadius.circular(16),
            border: destaque
                ? Border.all(color: const Color(0xFFf59e0b).withOpacity(0.4))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < paragrafos.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                Text(
                  paragrafos[i],
                  style: const TextStyle(
                      color: Color(0xFFD1D5DB), fontSize: 14.5, height: 1.5),
                ),
              ],
            ],
          ),
        ),
        const Spacer(),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: onBotao,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A56DB),
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(botaoTexto,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        if (botaoSecundarioTexto != null) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: onBotaoSecundario,
            child: Text(botaoSecundarioTexto!,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}
