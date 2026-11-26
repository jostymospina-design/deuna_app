import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/supabase_config.dart';
import '../../models/perfil.dart';
import '../../providers/sesion_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/componentes.dart';

/// Crea la mensajería (empresa de domicilios). Quien la crea queda como administrador.
class CrearMensajeriaScreen extends StatefulWidget {
  const CrearMensajeriaScreen({super.key});

  @override
  State<CrearMensajeriaScreen> createState() => _CrearMensajeriaScreenState();
}

class _CrearMensajeriaScreenState extends State<CrearMensajeriaScreen> {
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (_nombre.text.trim().isEmpty) return;
    setState(() => _enviando = true);
    final sesion = context.read<SesionProvider>();
    try {
      await supabase.from('mensajerias').insert({
        'nombre': _nombre.text.trim(),
        'telefono': _telefono.text.trim(),
        'admin_id': miId,
      });
      await sesion.recargar();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      await sesion.cambiarModo(Modo.admin);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar mi mensajería')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Serás el administrador: apruebas a tus domiciliarios, registras sus recargas '
            'y recibes la comisión de cada pedido (10 % por defecto).',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre de la mensajería'),
          ),
          TextField(
            controller: _telefono,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono'),
          ),
          const SizedBox(height: 24),
          BotonPrincipal(
            texto: _enviando ? 'Creando…' : 'Crear mensajería',
            onPressed: _enviando ? null : _crear,
          ),
        ],
      ),
    );
  }
}
