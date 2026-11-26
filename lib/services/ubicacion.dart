import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ResultadoUbicacion {
  final LatLng? posicion;
  final String? error;

  /// Error estimado del GPS en metros (más bajo = más preciso).
  final double? precisionM;

  const ResultadoUbicacion({this.posicion, this.error, this.precisionM});

  bool get aproximada => (precisionM ?? 0) > 25;
}

class ServicioUbicacion {
  /// Última posición conocida (instantánea, puede ser vieja). Sirve para mover la cámara ya.
  static Future<LatLng?> rapida() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Pide permiso (si hace falta) y devuelve la ubicación actual del celular.
  static Future<ResultadoUbicacion> obtener() async {
    final gpsActivo = await Geolocator.isLocationServiceEnabled();
    if (!gpsActivo) {
      return const ResultadoUbicacion(
        error: 'El GPS está desactivado. Actívalo en los ajustes rápidos del celular.',
      );
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied) {
      return const ResultadoUbicacion(
        error: 'Sin el permiso de ubicación no podemos usar tu posición.',
      );
    }
    if (permiso == LocationPermission.deniedForever) {
      return const ResultadoUbicacion(
        error: 'El permiso está bloqueado. Actívalo en Ajustes > Aplicaciones > DeUna > Permisos.',
      );
    }

    try {
      final pos = await _mejorLectura();
      return ResultadoUbicacion(
        posicion: LatLng(pos.latitude, pos.longitude),
        precisionM: pos.accuracy,
      );
    } catch (_) {
      return const ResultadoUbicacion(
        error: 'No pudimos obtener tu ubicación. Intenta de nuevo en un lugar abierto.',
      );
    }
  }

  /// Escucha el GPS hasta 10 s y devuelve la primera lectura con menos de 25 m de error.
  /// Si no llega, devuelve la mejor que haya visto. Siempre cierra el GPS al terminar.
  static Future<Position> _mejorLectura() async {
    final listo = Completer<Position>();
    Position? mejor;
    final sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    ).listen(
      (p) {
        final m = mejor;
        if (m == null || p.accuracy < m.accuracy) mejor = p;
        if (p.accuracy <= 25 && !listo.isCompleted) listo.complete(p);
      },
      onError: (Object e) {
        if (!listo.isCompleted) listo.completeError(e);
      },
    );
    try {
      return await listo.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () async => mejor ?? await Geolocator.getCurrentPosition(),
      );
    } finally {
      await sub.cancel();
    }
  }
}
