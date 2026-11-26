import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/formato.dart';
import '../core/supabase_config.dart';
import '../core/tema.dart';
import '../models/perfil.dart';
import '../providers/sesion_provider.dart';
import '../services/auth_service.dart';
import '../widgets/componentes.dart';
import 'domiciliario/mis_documentos_screen.dart';

/// Perfil del usuario: ver y editar sus datos. Usa lo que ya está en SesionProvider
/// (no hace consultas nuevas al abrirse).
class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  Future<void> _editar(BuildContext context) async {
    final s = context.read<SesionProvider>();
    final nombre = TextEditingController(text: s.perfil!.nombre);
    final tel = TextEditingController(text: s.perfil!.telefono ?? '');
    final guardar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Editar perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Celular'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true || nombre.text.trim().isEmpty) return;
    try {
      await supabase
          .from('perfiles')
          .update({'nombre': nombre.text.trim(), 'telefono': tel.text.trim()})
          .eq('id', miId);
      await s.recargar();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
    }
  }

  Future<void> _cambiarCorreo(BuildContext context) async {
    final s = context.read<SesionProvider>();
    final actual = supabase.auth.currentUser?.email ?? '';
    final correo = TextEditingController(text: actual);
    final guardar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cambiar correo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: correo,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Correo nuevo'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Con este correo iniciarás sesión de ahora en adelante.',
              style: TextStyle(fontSize: 12.5, color: Paleta.gris),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    );
    final nuevo = correo.text.trim().toLowerCase();
    if (guardar != true || nuevo == actual.toLowerCase()) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(nuevo)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Escribe un correo válido.')));
      }
      return;
    }
    try {
      final r = await supabase.auth.updateUser(UserAttributes(email: nuevo));
      await s.recargar(); // vuelve a dibujar el perfil con el correo nuevo
      if (!context.mounted) return;
      // Si en Supabase está activo "Confirm email", el cambio queda pendiente
      // hasta que el usuario abra el enlace que llega al correo nuevo.
      final cambiado = r.user?.email?.toLowerCase() == nuevo;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(cambiado
            ? 'Correo actualizado.'
            : 'Te enviamos un enlace a $nuevo. Ábrelo para confirmar el cambio.'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      final texto = e is AuthException && e.message.contains('already been registered')
          ? 'Ese correo ya lo usa otra cuenta.'
          : AuthService.mensajeError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
    }
  }

  Widget _dato(IconData icono, String titulo, String valor, {VoidCallback? alTocar}) => ListTile(
        onTap: alTocar,
        trailing: alTocar == null ? null : const Icon(Icons.edit_outlined, size: 20),
        leading: Icon(icono, color: Paleta.verde),
        title: Text(titulo, style: const TextStyle(color: Paleta.gris, fontSize: 13)),
        subtitle: Text(
          valor,
          style: const TextStyle(
            color: Paleta.marino,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  String _nombreModo(Modo m) => switch (m) {
        Modo.cliente => 'Cliente',
        Modo.domiciliario => 'Domiciliario',
        Modo.admin => 'Administrador de mensajería',
      };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SesionProvider>();
    final p = s.perfil;
    if (p == null) return const Scaffold();
    final d = s.domiciliario;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Editar',
            onPressed: () => _editar(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: s.recargar,
        child: ListView(
          children: [
            const SizedBox(height: 16),
            Center(child: FotoPerfil(url: p.fotoUrl, nombre: p.nombre, radio: 44)),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '★ ${p.calificacion.toStringAsFixed(1)}',
                style: const TextStyle(color: Paleta.estrella, fontWeight: FontWeight.w800),
              ),
            ),
            _dato(Icons.person_rounded, 'Nombre', p.nombre),
            _dato(
              Icons.mail_rounded,
              'Correo (toca para cambiarlo)',
              supabase.auth.currentUser?.email ?? '',
              alTocar: () => _cambiarCorreo(context),
            ),
            _dato(Icons.phone_rounded, 'Celular',
                (p.telefono ?? '').isEmpty ? 'Sin registrar' : p.telefono!),
            _dato(Icons.badge_rounded, 'Perfiles disponibles',
                s.modosDisponibles.map(_nombreModo).join(' · ')),
            if (d != null) ...[
              const Divider(),
              _dato(Icons.two_wheeler_rounded, 'Vehículo', '${d.vehiculo} · ${d.placa}'),
              _dato(Icons.verified_rounded, 'Estado como domiciliario', d.estado),
              _dato(Icons.account_balance_wallet_rounded, 'Saldo', pesosConSigno(d.saldo)),
              _dato(
                Icons.folder_shared_rounded,
                'Mis documentos',
                'Cédula, licencia, SOAT y más',
                alTocar: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MisDocumentosScreen()),
                ),
              ),
            ],
            if (s.mensajeria != null) ...[
              const Divider(),
              _dato(
                Icons.store_rounded,
                'Mi mensajería',
                '${s.mensajeria!['nombre']} · comisión ${s.mensajeria!['porcentaje_comision']} %',
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
