import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/config.dart';
import '../core/mapa.dart';
import '../core/tema.dart';

enum TipoMarcador { recogida, entrega, repartidor }

/// Marcador independiente del proveedor de mapas.
class MarcadorMapa {
  final String id;
  final LatLng posicion;
  final TipoMarcador tipo;
  final String titulo;
  final String detalle;

  const MarcadorMapa({
    required this.id,
    required this.posicion,
    required this.tipo,
    this.titulo = '',
    this.detalle = '',
  });
}

ll.LatLng _aOsm(LatLng p) => ll.LatLng(p.latitude, p.longitude);

/// Mueve la cámara del mapa, sea de Google o de OpenStreetMap.
class ControladorMapa {
  GoogleMapController? _google;
  final osm.MapController _osm = osm.MapController();
  bool _osmListo = false;
  EdgeInsets _relleno = EdgeInsets.zero;

  bool get listo => usarGoogleMaps ? _google != null : _osmListo;

  /// Centra el mapa en [punto] dentro de la zona visible (sin el panel inferior).
  void moverA(LatLng punto, {double zoom = 15}) {
    if (!listo) return;
    if (usarGoogleMaps) {
      _google!.animateCamera(CameraUpdate.newLatLngZoom(punto, zoom));
    } else {
      _ajustarOsm(
        [
          ll.LatLng(punto.latitude - 0.0002, punto.longitude - 0.0002),
          ll.LatLng(punto.latitude + 0.0002, punto.longitude + 0.0002),
        ],
        margen: 20,
        zoomMaximo: zoom,
      );
    }
  }

  /// Ajusta la cámara para que [a] y [b] queden visibles.
  Future<void> ajustar(LatLng a, LatLng b, {double margen = 90}) async {
    if (!listo) return;
    if (usarGoogleMaps) {
      await ajustarCamara(_google!, a, b, margen: margen);
      return;
    }
    final muyCerca = (a.latitude - b.latitude).abs() < 0.0003 &&
        (a.longitude - b.longitude).abs() < 0.0003;
    if (muyCerca) {
      moverA(a, zoom: 16);
    } else {
      _ajustarOsm([_aOsm(a), _aOsm(b)], margen: margen, zoomMaximo: 17);
    }
  }

  void _ajustarOsm(
    List<ll.LatLng> puntos, {
    required double margen,
    required double zoomMaximo,
  }) {
    try {
      _osm.fitCamera(
        osm.CameraFit.coordinates(
          coordinates: puntos,
          padding: EdgeInsets.fromLTRB(
            margen,
            margen + _relleno.top,
            margen,
            margen + _relleno.bottom,
          ),
          maxZoom: zoomMaximo,
        ),
      );
    } catch (_) {
      // Si el mapa aún no está listo, se ignora.
    }
  }

  void liberar() {
    try {
      _google?.dispose();
      _osm.dispose();
    } catch (_) {}
  }
}

/// Mapa de DeUna: usa Google Maps u OpenStreetMap según core/config.dart.
class MapaDeUna extends StatelessWidget {
  final ControladorMapa controlador;
  final LatLng centroInicial;
  final double zoomInicial;
  final List<MarcadorMapa> marcadores;
  final List<LatLng> ruta;
  final EdgeInsets relleno;
  final bool interactivo;
  final ValueChanged<LatLng>? onTap;
  final VoidCallback? onListo;

  /// Se llama muchas veces por segundo mientras el mapa se mueve (no usar setState ahí).
  final ValueChanged<LatLng>? onCamaraMovida;

  /// Se llama una vez cuando el mapa deja de moverse.
  final VoidCallback? onCamaraQuieta;

  /// Muestra el punto azul de la ubicación propia. Lo mueve Android solo, en tiempo real.
  final bool miUbicacion;

  const MapaDeUna({
    super.key,
    required this.controlador,
    required this.centroInicial,
    this.zoomInicial = 14,
    this.marcadores = const [],
    this.ruta = const [],
    this.relleno = EdgeInsets.zero,
    this.interactivo = true,
    this.onTap,
    this.onListo,
    this.onCamaraMovida,
    this.onCamaraQuieta,
    this.miUbicacion = false,
  });

  @override
  Widget build(BuildContext context) {
    controlador._relleno = relleno;
    return usarGoogleMaps ? _google() : _openStreetMap();
  }

  /// Íconos creados una sola vez (no en cada reconstrucción del mapa).
  static final Map<TipoMarcador, BitmapDescriptor> _iconos = {
    TipoMarcador.recogida: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    TipoMarcador.entrega: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    TipoMarcador.repartidor: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
  };

  Widget _google() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: centroInicial, zoom: zoomInicial),
      style: estiloMapa,
      padding: relleno,
      markers: {
        for (final m in marcadores)
          Marker(
            markerId: MarkerId(m.id),
            position: m.posicion,
            icon: _iconos[m.tipo]!,
            infoWindow: InfoWindow(
              title: m.titulo.isEmpty ? null : m.titulo,
              snippet: m.detalle.isEmpty ? null : m.detalle,
            ),
          ),
      },
      polylines: {
        if (ruta.length > 1)
          Polyline(
            polylineId: const PolylineId('ruta'),
            points: ruta,
            color: Paleta.azul,
            width: 5,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
      },
      onMapCreated: (c) {
        controlador._google = c;
        onListo?.call();
      },
      onTap: onTap,
      onCameraMove: onCamaraMovida == null ? null : (pos) => onCamaraMovida!(pos.target),
      onCameraIdle: onCamaraQuieta,
      myLocationEnabled: miUbicacion,
      scrollGesturesEnabled: interactivo,
      zoomGesturesEnabled: interactivo,
      rotateGesturesEnabled: interactivo,
      tiltGesturesEnabled: interactivo,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
    );
  }

  Widget _iconoOsm(TipoMarcador tipo) {
    switch (tipo) {
      case TipoMarcador.recogida:
        return const Icon(Icons.location_on_rounded, color: Paleta.verde, size: 44);
      case TipoMarcador.entrega:
        return const Icon(Icons.location_on_rounded, color: Paleta.azul, size: 44);
      case TipoMarcador.repartidor:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFF8A00),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 6)],
          ),
          child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 22),
        );
    }
  }

  Widget _openStreetMap() {
    return Stack(
      children: [
        osm.FlutterMap(
          mapController: controlador._osm,
          options: osm.MapOptions(
            initialCenter: _aOsm(centroInicial),
            initialZoom: zoomInicial,
            backgroundColor: const Color(0xFFE8ECF4),
            interactionOptions: osm.InteractionOptions(
              flags: interactivo
                  ? osm.InteractiveFlag.all & ~osm.InteractiveFlag.rotate
                  : osm.InteractiveFlag.none,
            ),
            onTap: onTap == null
                ? null
                : (posicionToque, punto) => onTap!(LatLng(punto.latitude, punto.longitude)),
            onMapReady: () {
              controlador._osmListo = true;
              onListo?.call();
            },
          ),
          children: [
            osm.TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: paqueteApp,
            ),
            if (ruta.length > 1)
              osm.PolylineLayer(
                polylines: [
                  osm.Polyline(
                    points: [for (final p in ruta) _aOsm(p)],
                    color: Paleta.azul,
                    strokeWidth: 5,
                  ),
                ],
              ),
            osm.MarkerLayer(
              markers: [
                for (final m in marcadores)
                  osm.Marker(
                    point: _aOsm(m.posicion),
                    width: 44,
                    height: 44,
                    alignment: m.tipo == TipoMarcador.repartidor
                        ? Alignment.center
                        : Alignment.topCenter,
                    child: _iconoOsm(m.tipo),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 10,
          bottom: relleno.bottom + 6,
          child: const IgnorePointer(
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 10, color: Paleta.marino),
            ),
          ),
        ),
      ],
    );
  }
}
