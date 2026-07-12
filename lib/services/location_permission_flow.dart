import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/location_disclosure_screen.dart';

/// Garante que a permissão de localização (incluindo segundo plano) foi
/// concedida, mostrando a declaração em destaque antes de qualquer popup
/// nativo. Deve ser chamado antes de iniciar o rastreamento (ex: ao ligar
/// o status "disponível"), para cobrir usuários que já passaram pela
/// PermissoesScreen no primeiro acesso mas tiveram a permissão revogada,
/// ou que nunca passaram por ela (sessão antiga).
///
/// Fica marcado em disco (SharedPreferences) quando o motoboy já passou
/// pelo disclosure — [garantir] é chamado toda vez que o rastreamento é
/// (re)iniciado (voltar de uma entrega, app reaberto após o Android matar
/// o processo, etc.), então sem essa memória a tela reapareceria a cada
/// reinício mesmo com a permissão já concedida.
class LocationPermissionFlow {
  static const _chaveDisclosureConcluido = 'location_disclosure_concluido';

  static Future<bool> garantir(BuildContext context) async {
    final perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.deniedForever) {
      await _marcarDisclosureConcluido(false);
      if (!context.mounted) return false;
      return _mostrarDialogoConfiguracoes(context);
    }

    if (perm == LocationPermission.denied) {
      // Permissão ausente/revogada — refaz o disclosure completo do zero.
      await _marcarDisclosureConcluido(false);
      if (!context.mounted) return false;
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LocationDisclosureScreen()),
      );
      if (ok == true) await _marcarDisclosureConcluido(true);
      return ok == true;
    }

    if (perm == LocationPermission.whileInUse) {
      // Só mostra a etapa de segundo plano se ainda não passou por ela —
      // sem isso, reaparece toda vez que o app reinicia com "sempre" ainda
      // não concedido (o normal no Android 11+, que exige ir em
      // Configurações e não deixa reconceder direto pelo popup do app).
      if (!await _disclosureJaConcluido()) {
        if (!context.mounted) return true;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => const LocationDisclosureScreen(apenasBackground: true),
          ),
        );
        await _marcarDisclosureConcluido(true);
      }
      return true;
    }

    // LocationPermission.always
    await _marcarDisclosureConcluido(true);
    return true;
  }

  static Future<bool> _disclosureJaConcluido() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chaveDisclosureConcluido) ?? false;
  }

  static Future<void> _marcarDisclosureConcluido(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveDisclosureConcluido, valor);
  }

  static Future<bool> _mostrarDialogoConfiguracoes(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161820),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.location_off, color: Color(0xFFef4444), size: 22),
          SizedBox(width: 8),
          Text('Localização bloqueada',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: const Text(
          'Você negou permanentemente o acesso à localização. Para ficar '
          'disponível e receber corridas, ative a permissão de localização '
          'nas configurações do app.',
          style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Agora não',
                style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('Abrir configurações',
                style: TextStyle(color: Color(0xFF1A56DB))),
          ),
        ],
      ),
    );
    return false;
  }
}
