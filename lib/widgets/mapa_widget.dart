import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapaWidget extends StatelessWidget {
  final LatLng center;
  final List<Marker> markers;
  final double zoom;

  const MapaWidget({
    super.key,
    required this.center,
    required this.markers,
    this.zoom = 15,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.letsgo.entregador',
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }
}
