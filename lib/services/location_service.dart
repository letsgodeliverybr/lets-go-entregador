import 'dart:io';
import 'package:geolocator/geolocator.dart';

class LocationService {
  // Agendamento 131: junto com lat/lng vai a precisão e se a posição é
  // simulada (GPS falso). O servidor só aceita a posição para a chegada na
  // base se veio do próprio entregador logado (carimba a hora do servidor) —
  // 't' muda a cada envio para o servidor saber que este dado é novo.
  static Map<String, dynamic> gpsMeta(Position p) => {
        'precisao': p.accuracy,
        'simulada': p.isMocked,
        't': DateTime.now().millisecondsSinceEpoch,
      };

  static Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }

    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  static Stream<Position> getPositionStream() {
    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'LetsGo está monitorando sua localização',
          notificationTitle: 'Localização ativa',
          enableWakeLock: true,
        ),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
