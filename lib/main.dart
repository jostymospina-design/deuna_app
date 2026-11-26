import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase_config.dart';
import 'core/tema.dart';
import 'models/perfil.dart';
import 'providers/sesion_provider.dart';
import 'screens/admin/panel_admin_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/domiciliario/inicio_domiciliario_screen.dart';
import 'screens/inicio_screen.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseClave);
  await PushService.inicializar();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SesionProvider()..iniciar(),
      child: const DeUnaApp(),
    ),
  );
}

class DeUnaApp extends StatelessWidget {
  const DeUnaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeUna',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: mensajeroGlobal,
      theme: construirTema(),
      home: const PuertaSesion(),
    );
  }
}

/// Decide qué pantalla mostrar según la sesión y el modo activo (como inDrive).
class PuertaSesion extends StatelessWidget {
  const PuertaSesion({super.key});

  @override
  Widget build(BuildContext context) {
    // select: solo se reconstruye cuando cambian estos valores, no con cada notifyListeners.
    final (cargando, tienePerfil, modo) = context.select<SesionProvider, (bool, bool, Modo)>(
      (s) => (s.cargando, s.perfil != null, s.modo),
    );
    final conSesion = supabase.auth.currentSession != null;

    if (cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!conSesion) return const LoginScreen();
    if (!tienePerfil) return const _SinPerfil();

    return switch (modo) {
      Modo.cliente => const InicioScreen(),
      Modo.domiciliario => const InicioDomiciliarioScreen(),
      Modo.admin => const PanelAdminScreen(),
    };
  }
}

/// Hay sesión pero no se pudo leer el perfil (sin internet, o una cuenta creada
/// antes de ejecutar el script SQL).
class _SinPerfil extends StatelessWidget {
  const _SinPerfil();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 56, color: Paleta.gris),
              const SizedBox(height: 12),
              const Text(
                'No pudimos cargar tu perfil.\nRevisa tu conexión e intenta de nuevo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.read<SesionProvider>().recargar(),
                child: const Text('Reintentar'),
              ),
              TextButton(
                onPressed: AuthService.salir,
                child: const Text('Cerrar sesión y crear otra cuenta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
