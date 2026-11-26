import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';
import '../models/perfil.dart';
import '../services/push_service.dart';

/// Datos de la cuenta que inició sesión y el modo activo (cliente, domiciliario o admin).
class SesionProvider extends ChangeNotifier {
  StreamSubscription<AuthState>? _sub;
  bool cargando = true;
  Perfil? perfil;
  InfoDomiciliario? domiciliario;
  Map<String, dynamic>? mensajeria; // la mensajería que administra (si tiene)
  Modo modo = Modo.cliente;

  List<Modo> get modosDisponibles => [
        Modo.cliente,
        if (domiciliario?.aprobado ?? false) Modo.domiciliario,
        if (mensajeria != null) Modo.admin,
      ];

  void iniciar() {
    // Emite un evento al arrancar (sesión guardada o no) y en cada login/logout.
    _sub = supabase.auth.onAuthStateChange.listen((evento) async {
      if (evento.session == null) {
        perfil = null;
        domiciliario = null;
        mensajeria = null;
        modo = Modo.cliente;
        cargando = false;
        notifyListeners();
      } else if (evento.event != AuthChangeEvent.tokenRefreshed) {
        if (perfil == null && !cargando) {
          cargando = true; // acaba de iniciar sesión: muestra la carga, no la pantalla de error
          notifyListeners();
        }
        await recargar();
        if (evento.event == AuthChangeEvent.signedIn ||
            evento.event == AuthChangeEvent.initialSession) {
          PushService.registrar(); // no se espera: no retrasa la entrada a la app
        }
      }
    });
  }

  /// Vuelve a leer perfil, rol de domiciliario y mensajería (3 consultas en paralelo).
  Future<void> recargar() async {
    final usuario = supabase.auth.currentUser;
    if (usuario == null) return;
    try {
      final Future<Map<String, dynamic>> fPerfil =
          supabase.from('perfiles').select().eq('id', usuario.id).single();
      final Future<Map<String, dynamic>?> fDomi =
          supabase.from('domiciliarios').select().eq('id', usuario.id).maybeSingle();
      final Future<Map<String, dynamic>?> fMensajeria =
          supabase.from('mensajerias').select().eq('admin_id', usuario.id).maybeSingle();
      final (p, d, m) = await (fPerfil, fDomi, fMensajeria).wait; // las 3 en paralelo
      perfil = Perfil.desdeMapa(p);
      domiciliario = d == null ? null : InfoDomiciliario.desdeMapa(d);
      mensajeria = m;

      if (cargando) {
        // Solo al abrir la app: recupera el último modo usado en este celular.
        final prefs = await SharedPreferences.getInstance();
        final guardado = prefs.getString('modo');
        modo = Modo.values.firstWhere((x) => x.name == guardado, orElse: () => Modo.cliente);
      }
      if (!modosDisponibles.contains(modo)) modo = Modo.cliente;
    } catch (e) {
      debugPrint('Error cargando la sesión: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> cambiarModo(Modo nuevo) async {
    if (!modosDisponibles.contains(nuevo) || nuevo == modo) return;
    if (modo == Modo.domiciliario) {
      // Al salir del modo domiciliario deja de recibir pedidos.
      try {
        await supabase.from('domiciliarios').update({'disponible': false}).eq('id', miId);
      } catch (_) {}
    }
    modo = nuevo;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('modo', nuevo.name);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
