import 'package:flutter/material.dart';
import '../../core/tema.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  bool _registro = false;
  bool _cargando = false;

  @override
  void dispose() {
    for (final c in [_correo, _clave, _nombre, _telefono]) c.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _cargando = true);
    try {
      if (_registro) {
        await AuthService.registrar(
          correo: _correo.text, clave: _clave.text,
          nombre: _nombre.text, telefono: _telefono.text,
        );
      } else {
        await AuthService.entrar(_correo.text, _clave.text);
      }
      // No se navega: PuertaSesion cambia de pantalla sola al detectar la sesión.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String? _requerido(String? v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 40),
              const Text('DeUna', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Paleta.verde)),
              const SizedBox(height: 32),
              if (_registro) ...[
                TextFormField(controller: _nombre, validator: _requerido,
                    decoration: const InputDecoration(labelText: 'Nombre completo')),
                TextFormField(controller: _telefono, validator: _requerido,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Celular')),
              ],
              TextFormField(controller: _correo, validator: _requerido,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo')),
              TextFormField(controller: _clave, obscureText: true,
                  validator: (v) => (v ?? '').length < 6 ? 'Mínimo 6 caracteres' : null,
                  decoration: const InputDecoration(labelText: 'Contraseña')),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _cargando ? null : _enviar,
                child: Text(_cargando ? 'Un momento...' : (_registro ? 'Crear cuenta' : 'Entrar')),
              ),
              TextButton(
                onPressed: () => setState(() => _registro = !_registro),
                child: Text(_registro ? 'Ya tengo cuenta' : 'Crear una cuenta nueva'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}