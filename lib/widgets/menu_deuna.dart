import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/formato.dart';
import '../core/tema.dart';
import '../models/perfil.dart';
import '../providers/sesion_provider.dart';
import '../screens/admin/crear_mensajeria_screen.dart';
import '../screens/domiciliario/mis_documentos_screen.dart';
import '../screens/domiciliario/recargas_screen.dart';
import '../screens/domiciliario/registro_domiciliario_screen.dart';
import '../screens/historial_screen.dart';
import '../screens/perfil_screen.dart';
import '../services/auth_service.dart';
import 'componentes.dart';

/// Menú lateral de las tres pantallas principales. Permite cambiar de modo como en inDrive.
class MenuDeUna extends StatelessWidget {
  const MenuDeUna({super.key});

  void _abrir(BuildContext context, Widget pantalla) {
    Navigator.pop(context); // cierra el menú
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
  }

  void _cambiar(BuildContext context, Modo modo) {
    final sesion = context.read<SesionProvider>();
    Navigator.of(context).popUntil((r) => r.isFirst);
    sesion.cambiarModo(modo);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SesionProvider>();
    final p = s.perfil;
    if (p == null) return const Drawer();
    final dom = s.domiciliario;

    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              leading: FotoPerfil(url: p.fotoUrl, nombre: p.nombre, radio: 24),
              title: Text(
                p.nombre,
                style: const TextStyle(fontWeight: FontWeight.w800, color: Paleta.marino),
              ),
              subtitle: Text('★ ${p.calificacion.toStringAsFixed(1)} · Ver perfil'),
              onTap: () => _abrir(context, const PerfilScreen()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Chip(
                avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(switch (s.modo) {
                  Modo.cliente => 'Modo cliente',
                  Modo.domiciliario => 'Modo domiciliario',
                  Modo.admin => 'Panel de mensajería',
                }),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(s.modo == Modo.domiciliario ? 'Mis entregas' : 'Mis pedidos'),
              onTap: () => _abrir(context, const HistorialScreen()),
            ),
            if (dom != null)
              ListTile(
                leading: const Icon(Icons.badge_rounded),
                title: const Text('Mis documentos'),
                onTap: () => _abrir(context, const MisDocumentosScreen()),
              ),
            if (s.modo == Modo.domiciliario && dom != null)
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_rounded),
                title: const Text('Saldo y recargas'),
                trailing: Text(pesosConSigno(dom.saldo)),
                onTap: () => _abrir(context, const RecargasScreen()),
              ),
            const Divider(),
            if (s.modo != Modo.cliente)
              ListTile(
                leading: const Icon(Icons.person_rounded, color: Paleta.verde),
                title: const Text('Cambiar a modo cliente'),
                onTap: () => _cambiar(context, Modo.cliente),
              ),
            if (s.modo != Modo.domiciliario && (dom?.aprobado ?? false))
              ListTile(
                leading: const Icon(Icons.two_wheeler_rounded, color: Paleta.verde),
                title: const Text('Cambiar a modo domiciliario'),
                onTap: () => _cambiar(context, Modo.domiciliario),
              ),
            if (dom == null)
              ListTile(
                leading: const Icon(Icons.two_wheeler_rounded),
                title: const Text('Quiero ser domiciliario'),
                onTap: () => _abrir(context, const RegistroDomiciliarioScreen()),
              ),
            if (dom != null && !dom.aprobado)
              ListTile(
                leading: const Icon(Icons.hourglass_top_rounded),
                title: Text(dom.estado == 'bloqueado'
                    ? 'Domiciliario: bloqueado'
                    : 'Domiciliario: en revisión'),
                subtitle: const Text('Toca para actualizar'),
                onTap: () => s.recargar(),
              ),
            if (s.mensajeria != null && s.modo != Modo.admin)
              ListTile(
                leading: const Icon(Icons.store_rounded, color: Paleta.verde),
                title: const Text('Panel de mi mensajería'),
                onTap: () => _cambiar(context, Modo.admin),
              ),
            if (s.mensajeria == null)
              ListTile(
                leading: const Icon(Icons.add_business_rounded),
                title: const Text('Registrar mi mensajería'),
                onTap: () => _abrir(context, const CrearMensajeriaScreen()),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Paleta.alerta),
              title: const Text('Cerrar sesión'),
              onTap: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                AuthService.salir();
              },
            ),
          ],
        ),
      ),
    );
  }
}
