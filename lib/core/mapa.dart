import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Estilo del mapa: oculta los negocios y los íconos de transporte
/// para que el mapa se vea limpio y los marcadores de DeUna destaquen.
const String estiloMapa =
    '[{"featureType":"poi.business","stylers":[{"visibility":"off"}]},'
    '{"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}]';

/// Mueve la cámara para que los puntos [a] y [b] queden visibles.
Future<void> ajustarCamara(
  GoogleMapController controlador,
  LatLng a,
  LatLng b, {
  double margen = 90,
}) async {
  final muyCerca = (a.latitude - b.latitude).abs() < 0.0003 &&
      (a.longitude - b.longitude).abs() < 0.0003;
  try {
    if (muyCerca) {
      await controlador.animateCamera(CameraUpdate.newLatLngZoom(a, 16));
      return;
    }
    final limites = LatLngBounds(
      southwest: LatLng(min(a.latitude, b.latitude), min(a.longitude, b.longitude)),
      northeast: LatLng(max(a.latitude, b.latitude), max(a.longitude, b.longitude)),
    );
    await controlador.animateCamera(CameraUpdate.newLatLngBounds(limites, margen));
  } catch (_) {
    // Si el mapa todavía no tiene tamaño, se ignora y la cámara queda donde estaba.
  }
}
