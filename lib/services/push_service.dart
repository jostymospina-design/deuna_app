import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../core/firebase_config.dart';
import '../core/supabase_config.dart';

/// Permite mostrar avisos (SnackBar) desde cualquier parte, aunque no haya un context.
final GlobalKey<ScaffoldMessengerState> mensajeroGlobal = GlobalKey<ScaffoldMessengerState>();

/// Notificaciones push con Firebase Cloud Messaging.
/// - Con la app cerrada o en segundo plano, Android muestra la notificación solo.
/// - Con la app abierta, se muestra como aviso en la parte de abajo.
/// Quién recibe cada notificación lo decide la base de datos (cambio_notificaciones.sql).
class PushService {
  static bool _listo = false;
  static StreamSubscription<String>? _subToken;
  static StreamSubscription<RemoteMessage>? _subMensajes;

  /// Una vez, al abrir la app.
  static Future<void> inicializar() async {
    if (opcionesFirebase.apiKey == 'PEGAR_AQUI') {
      debugPrint('Push desactivado: faltan los datos de Firebase en core/firebase_config.dart');
      return;
    }
    try {
      await Firebase.initializeApp(options: opcionesFirebase);
      _listo = true;
    } catch (e) {
      debugPrint('No se pudo iniciar Firebase: $e');
      return;
    }
    _subMensajes = FirebaseMessaging.onMessage.listen((mensaje) {
      final n = mensaje.notification;
      if (n == null) return;
      mensajeroGlobal.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            [n.title, n.body].whereType<String>().join('\n'),
          ),
        ),
      );
    });
  }

  /// Después de iniciar sesión: pide permiso y registra este celular a nombre del usuario.
  static Future<void> registrar() async {
    if (!_listo || supabase.auth.currentUser == null) return;
    try {
      final fm = FirebaseMessaging.instance;
      final permiso = await fm.requestPermission();
      if (permiso.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await fm.getToken();
      if (token != null) await _guardar(token);
      _subToken ??= fm.onTokenRefresh.listen(_guardar);
    } catch (e) {
      debugPrint('No se pudo registrar el celular para notificaciones: $e');
    }
  }

  static Future<void> _guardar(String token) async {
    if (supabase.auth.currentUser == null) return;
    try {
      await supabase.rpc('registrar_dispositivo', params: {'p_token': token});
    } catch (e) {
      debugPrint('No se pudo guardar el token: $e');
    }
  }

  /// Antes de cerrar sesión: este celular deja de recibir las notificaciones de esa cuenta.
  static Future<void> olvidar() async {
    if (!_listo || supabase.auth.currentUser == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await supabase.rpc('olvidar_dispositivo', params: {'p_token': token});
      }
    } catch (_) {}
  }

  static void liberar() {
    _subToken?.cancel();
    _subMensajes?.cancel();
  }
}
