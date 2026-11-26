import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Un punto del mapa con nombre (recogida o entrega).
class Lugar {
  final String nombre;
  final String detalle;
  final LatLng posicion;

  const Lugar({
    required this.nombre,
    required this.detalle,
    required this.posicion,
  });
}

/// Oferta de un repartidor en la subasta.
class Oferta {
  final String id;
  final String domiciliarioId;
  final String nombre;
  final double calificacion;
  final int envios; // ya no se muestra; se deja por compatibilidad
  final int precio;
  final String vehiculo;
  final int minutosLlegada;
  final String? fotoUrl;
  final bool verificado;

  const Oferta({
    required this.id,
    required this.domiciliarioId,
    required this.nombre,
    required this.calificacion,
    this.envios = 0,
    required this.precio,
    required this.vehiculo,
    required this.minutosLlegada,
    this.fotoUrl,
    this.verificado = false,
  });
}

/// Todo lo que el cliente va completando a lo largo de las pantallas.
class Pedido {
  final Lugar origen;
  final Lugar destino;

  /// Se llenan al crear el pedido en Supabase (PedidoService.crear).
  String? id;
  String? codigo; // código de recogida
  String? codigoEntrega; // código de entrega

  String tipoPaquete = 'Caja pequeña';
  String peso = '';
  String indicaciones = '';

  double distanciaKm = 0;
  int minutos = 0;
  int tarifaSugerida = 0;
  int tarifa = 0;

  Oferta? oferta;
  int propina = 0;
  int calificacion = 0;

  Pedido({required this.origen, required this.destino}) {
    final metros = Geolocator.distanceBetween(
      origen.posicion.latitude,
      origen.posicion.longitude,
      destino.posicion.latitude,
      destino.posicion.longitude,
    );
    // La distancia en línea recta se multiplica por 1,3 para aproximar el recorrido por calles.
    distanciaKm = max(0.5, (metros / 1000) * 1.3);
    // Velocidad promedio supuesta en moto por ciudad: 25 km/h.
    minutos = max(4, (distanciaKm / 25 * 60).round());
    // Tarifa base de 2.000 más 600 por km, redondeada a 500 y con mínimo de 4.000.
    var sugerida = ((2000 + 600 * distanciaKm) / 500).round() * 500;
    if (sugerida < 4000) sugerida = 4000;
    tarifaSugerida = sugerida;
    tarifa = sugerida;
  }

  int get total => (oferta?.precio ?? tarifa) + propina;
}
