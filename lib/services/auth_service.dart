import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import 'push_service.dart';

class AuthService {
  static Future<void> registrar({
    required String correo,
    required String clave,
    required String nombre,
    required String telefono,
  }) async {
    await supabase.auth.signUp(
      email: correo.trim(),
      password: clave,
      data: {'nombre': nombre.trim(), 'telefono': telefono.trim()},
    );
  }

  static Future<void> entrar(String correo, String clave) async {
    await supabase.auth.signInWithPassword(email: correo.trim(), password: clave);
  }

  static Future<void> salir() async {
    await PushService.olvidar(); // este celular deja de recibir notificaciones de la cuenta
    await supabase.auth.signOut();
  }

  /// Convierte los errores de Supabase en mensajes para el usuario.
  static String mensajeError(Object e) {
    if (e is AuthException) {
      if (e.message.contains('Invalid login')) return 'Correo o contraseña incorrectos.';
      if (e.message.contains('already registered')) return 'Ese correo ya tiene cuenta.';
      return e.message;
    }
    if (e is PostgrestException) return e.message; // mensajes de las funciones SQL
    return 'Revisa tu conexión a internet e intenta de nuevo.';
  }
}