import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../core/supabase_config.dart';
import '../../providers/sesion_provider.dart';
import '../../services/auth_service.dart';
import '../../services/documentos_service.dart';
import '../../widgets/componentes.dart';

/// El domiciliario sube sus documentos y ve si fueron aprobados, rechazados o están por vencer.
class MisDocumentosScreen extends StatefulWidget {
  const MisDocumentosScreen({super.key});

  @override
  State<MisDocumentosScreen> createState() => _MisDocumentosScreenState();
}

class _MisDocumentosScreenState extends State<MisDocumentosScreen> {
  bool _cargando = true;
  bool _autorizado = false;
  bool _acepto = false;
  Map<String, Map<String, dynamic>> _docs = {};
  String? _subiendo; // tipo que se está subiendo

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final (autorizado, docs) =
          await (DocumentosService.autorizacionAceptada(), DocumentosService.de(miId)).wait;
      if (!mounted) return;
      setState(() {
        _autorizado = autorizado;
        _docs = docs;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _aviso(AuthService.mensajeError(e));
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _aceptarAutorizacion() async {
    try {
      await DocumentosService.aceptarAutorizacion();
      if (mounted) setState(() => _autorizado = true);
    } catch (e) {
      if (mounted) _aviso(AuthService.mensajeError(e));
    }
  }

  Future<void> _subir(TipoDocumento tipo) async {
    final camara = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(tipo.nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(tipo.ayuda),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(c, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(c, false),
            ),
          ],
        ),
      ),
    );
    if (camara == null || !mounted) return;

    DateTime? vence;
    if (tipo.vence) {
      final hoy = DateTime.now();
      vence = await showDatePicker(
        context: context,
        helpText: 'Fecha de vencimiento de: ${tipo.nombre}',
        initialDate: hoy.add(const Duration(days: 365)),
        firstDate: hoy,
        lastDate: DateTime(hoy.year + 15),
      );
      if (vence == null || !mounted) return;
    }

    final foto = await DocumentosService.elegirFoto(camara: camara, selfie: tipo.id == 'selfie');
    if (foto == null || !mounted) return;

    setState(() => _subiendo = tipo.id);
    try {
      await DocumentosService.subir(tipo, foto, venceEn: vence);
      if (tipo.id == 'selfie' && mounted) {
        await context.read<SesionProvider>().recargar(); // muestra la foto nueva en el perfil
      }
      _aviso('${tipo.nombre}: enviado a revisión.');
    } catch (e) {
      _aviso(AuthService.mensajeError(e));
    }
    if (!mounted) return;
    setState(() => _subiendo = null);
    _cargar();
  }

  Widget _chipEstado(String estado) {
    final (texto, color) = switch (estado) {
      'aprobado' => ('Aprobado', Paleta.verde),
      'pendiente' => ('En revisión', Paleta.azul),
      'rechazado' => ('Rechazado', Paleta.alerta),
      'vencido' => ('Vencido', Paleta.alerta),
      _ => ('Falta', Paleta.gris),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _filaDocumento(TipoDocumento tipo) {
    final doc = _docs[tipo.id];
    final estado = estadoDocumento(doc);
    final vence = doc?['vence_en'] as String?;
    final detalles = <String>[
      if (!tipo.obligatorio) 'Opcional',
      if (vence != null) 'Vence: ${fechaCorta(vence)}',
      if (estado == 'rechazado' && doc?['motivo'] != null) 'Motivo: ${doc!['motivo']}',
    ];
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Paleta.borde),
      ),
      child: ListTile(
        title: Text(tipo.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          detalles.isEmpty ? tipo.ayuda : detalles.join(' · '),
          style: TextStyle(color: estado == 'rechazado' ? Paleta.alerta : Paleta.gris),
        ),
        trailing: _subiendo == tipo.id
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _chipEstado(estado),
                  const SizedBox(height: 4),
                  Text(
                    estado == 'falta' ? 'Subir' : 'Cambiar',
                    style: const TextStyle(color: Paleta.verde, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
        onTap: _subiendo != null ? null : () => _subir(tipo),
      ),
    );
  }

  Widget _autorizacion() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Autorización de tratamiento de datos',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Paleta.marino),
        ),
        const SizedBox(height: 12),
        const Text(
          'Para trabajar en DeUna debes subir fotos de tu cédula, licencia, SOAT y tarjeta de '
          'propiedad. Las usamos solo para que tu mensajería verifique tu identidad y tu '
          'vehículo. Solo tú y el administrador de tu mensajería pueden verlas; los clientes '
          'únicamente ven tu foto, tu nombre y si estás verificado.\n\n'
          'Puedes pedir que se eliminen escribiendo a tu mensajería. Esta autorización se da '
          'conforme a la Ley 1581 de 2012 de protección de datos personales.',
          style: TextStyle(height: 1.45),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _acepto,
          onChanged: (v) => setState(() => _acepto = v ?? false),
          title: const Text('Autorizo el tratamiento de mis datos personales'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 12),
        BotonPrincipal(texto: 'Continuar', onPressed: _acepto ? _aceptarAutorizacion : null),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final obligatorios = tiposDocumento.where((t) => t.obligatorio);
    final listos = obligatorios.where((t) => estadoDocumento(_docs[t.id]) == 'aprobado').length;

    return Scaffold(
      appBar: AppBar(title: const Text('Mis documentos')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : !_autorizado
              ? _autorizacion()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '$listos de ${obligatorios.length} documentos obligatorios aprobados',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Paleta.marino,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: listos / obligatorios.length,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                        color: Paleta.verde,
                        backgroundColor: Paleta.borde,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tu mensajería revisa cada documento. Cuando todos estén aprobados podrás '
                        'recibir pedidos. Te avisaremos antes de que se venza alguno.',
                        style: TextStyle(color: Paleta.gris, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      for (final t in tiposDocumento) _filaDocumento(t),
                    ],
                  ),
                ),
    );
  }
}
