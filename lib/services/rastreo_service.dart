import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

/// Lo usa el domiciliario durante una entrega: emite su posición en vivo al cliente.
/// - Broadcast de Supabase: no escribe en la base de datos cada vez (rápido y barato).
/// - Cada 30 s guarda la última posición en la tabla domiciliarios.
class RastreoService {
  RastreoService._();

  /// Una sola instancia para toda la app: el GPS sigue enviando aunque el domiciliario
  /// salga de la pantalla de entrega. Se detiene solo cuando el pedido termina o se cancela.
  static final RastreoService instancia = RastreoService._();

  String? pedidoActual;
  RealtimeChannel? _canal;
  StreamSubscription<Position>? _gps;
  DateTime _ultimoGuardado = DateTime(2000);

  /// Canal compartido entre cliente y domiciliario para un pedido.
  static String nombreCanal(String pedidoId) => 'pedido-$pedidoId';

  void iniciar(String pedidoId) {
    if (_gps != null && pedidoActual == pedidoId) return; // ya está enviando
    if (_gps != null) detener();
    pedidoActual = pedidoId;
    _canal = supabase.channel(nombreCanal(pedidoId));
    _canal!.subscribe();

    _gps = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // solo avisa si se movió 5 m o más
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'DeUna',
          notificationText: 'Compartiendo tu ubicación con el cliente',
          enableWakeLock: true,
        ),
      ),
    ).listen(_enviar, onError: (_) {});
  }

  void _enviar(Position p) {
    if (p.accuracy > 50) return; // descarta lecturas malas que harían "saltar" el marcador
    _canal?.sendBroadcastMessage(
      event: 'pos',
      payload: {'lat': p.latitude, 'lng': p.longitude, 'rumbo': p.heading},
    );
    if (DateTime.now().difference(_ultimoGuardado).inSeconds >= 30) {
      _ultimoGuardado = DateTime.now();
      supabase
          .from('domiciliarios')
          .update({
            'lat': p.latitude,
            'lng': p.longitude,
            'ubicacion_en': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', miId)
          .then((_) {}, onError: (_) {});
    }
  }

  Future<void> detener() async {
    pedidoActual = null;
    final gps = _gps;
    _gps = null;
    await gps?.cancel();
    final canal = _canal;
    _canal = null;
    if (canal != null) await supabase.removeChannel(canal);
  }
}
