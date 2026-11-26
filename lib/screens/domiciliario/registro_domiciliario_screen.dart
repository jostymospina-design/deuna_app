import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/supabase_config.dart';
import '../../providers/sesion_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/componentes.dart';
import 'mis_documentos_screen.dart';

/// Solicitud para trabajar como domiciliario de una mensajería. El admin la aprueba.
class RegistroDomiciliarioScreen extends StatefulWidget {
  const RegistroDomiciliarioScreen({super.key});

  @override
  State<RegistroDomiciliarioScreen> createState() => _RegistroDomiciliarioScreenState();
}

class _RegistroDomiciliarioScreenState extends State<RegistroDomiciliarioScreen> {
  late final Future<List<Map<String, dynamic>>> _mensajerias =
      supabase.from('mensajerias').select('id, nombre').order('nombre');
  final _vehiculo = TextEditingController();
  final _placa = TextEditingController();
  String? _mensajeriaId;
  bool _enviando = false;

  @override
  void dispose() {
    _vehiculo.dispose();
    _placa.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_mensajeriaId == null || _vehiculo.text.trim().isEmpty || _placa.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Completa todos los campos.')));
      return;
    }
    setState(() => _enviando = true);
    final sesion = context.read<SesionProvider>();
    try {
      await supabase.from('domiciliarios').insert({
        'id': miId,
        'mensajeria_id': _mensajeriaId,
        'vehiculo': _vehiculo.text.trim(),
        'placa': _placa.text.trim().toUpperCase(),
      });
      await sesion.recargar();
      if (!mounted) return;
      // Siguiente paso: subir los documentos para que la mensajería los revise.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MisDocumentosScreen()),
      );
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
      appBar: AppBar(title: const Text('Quiero ser domiciliario')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _mensajerias,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('No se pudieron cargar las mensajerías.'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aún no hay mensajerías registradas. Primero alguien debe crear una '
                  'desde el menú: "Registrar mi mensajería".',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Elige la mensajería con la que trabajas. Ellos aprueban tu cuenta y '
                'reciben tus recargas.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _mensajeriaId,
                decoration: const InputDecoration(labelText: 'Mensajería'),
                items: [
                  for (final m in snap.data!)
                    DropdownMenuItem(value: m['id'] as String, child: Text(m['nombre'] as String)),
                ],
                onChanged: (v) => setState(() => _mensajeriaId = v),
              ),
              TextField(
                controller: _vehiculo,
                decoration:
                    const InputDecoration(labelText: 'Vehículo (ej. Moto Honda CB azul)'),
              ),
              TextField(
                controller: _placa,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Placa'),
              ),
              const SizedBox(height: 24),
              BotonPrincipal(
                texto: _enviando ? 'Enviando…' : 'Enviar solicitud',
                onPressed: _enviando ? null : _enviar,
              ),
            ],
          );
        },
      ),
    );
  }
}
