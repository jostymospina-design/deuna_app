import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Convierte coordenadas en una dirección legible ("Calle 45 #27-10, Cabecera")
/// con el geocodificador del celular (gratis, no usa la API de Google).
class Direcciones {
  static final Geocoding _geocoding = Geocoding();
  static final Map<String, String> _cache = {};

  static Future<String> nombre(LatLng p) async {
    // ~10 m de precisión en la clave: no repite consultas para el mismo punto.
    final clave = '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';
    final guardada = _cache[clave];
    if (guardada != null) return guardada;
    try {
      final lista = await _geocoding.placemarkFromCoordinates(p.latitude, p.longitude);
      if (lista.isEmpty) return 'Punto en el mapa';
      final pm = lista.first;
      final partes = <String?>[pm.street, pm.subLocality]
          .whereType<String>()
          .where((t) => t.trim().isNotEmpty)
          .toList();
      final texto = partes.isEmpty ? 'Punto en el mapa' : partes.join(', ');
      return _cache[clave] = texto;
    } catch (_) {
      return 'Punto en el mapa';
    }
  }

  /// Busca una dirección escrita ("Calle 45 # 27-10") y devuelve sus coordenadas.
  /// Si no menciona el municipio, se asume Bucaramanga. Devuelve null si no la encuentra.
  static Future<LatLng?> buscar(String texto) async {
    var consulta = texto.trim();
    if (consulta.isEmpty) return null;
    final minusculas = consulta.toLowerCase();
    const municipios = ['bucaramanga', 'floridablanca', 'girón', 'giron', 'piedecuesta'];
    if (!municipios.any(minusculas.contains)) {
      consulta = '$consulta, Bucaramanga, Santander, Colombia';
    }
    try {
      final lista = await _geocoding.locationFromAddress(consulta);
      if (lista.isEmpty) return null;
      return LatLng(lista.first.latitude, lista.first.longitude);
    } catch (_) {
      return null; // sin resultados o sin internet
    }
  }
}
