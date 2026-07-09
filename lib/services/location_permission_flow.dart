import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../screens/location_disclosure_screen.dart';

/// Garante que a permissão de localização (incluindo segundo plano) foi
/// concedida, mostrando a declaração em destaque antes de qualquer popup
/// nativo. Deve ser chamado antes de iniciar o rastreamento (ex: ao ligar
/// o status "disponível"), para cobrir usuários que já passaram pela
/// PermissoesScreen no primeiro acesso mas tiveram a permissão revogada,
/// ou que nunca passaram por ela (sessão antiga).
class LocationPermissionFlow {
  static Future<bool> garantir(BuildContext context) async {
    final perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.deniedForever) {
      if (!context.mounted) return false;
      return _mostrarDialogoConfiguracoes(context);
    }

    if (perm == LocationPermission.denied) {
      if (!context.mounted) return false;
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LocationDisclosureScreen()),
      );
      return ok == true;
    }

    if (perm == LocationPermission.whileInUse) {
      if (!context.mounted) return true;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const LocationDisclosureScreen(apenasBackground: true),
        ),
      );
    }

    return true;
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
