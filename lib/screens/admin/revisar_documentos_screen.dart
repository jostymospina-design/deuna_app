import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../services/auth_service.dart';
import '../../services/documentos_service.dart';
import '../../services/saldo_service.dart';
import '../../widgets/componentes.dart';

/// El admin de la mensajería revisa cada documento de un domiciliario y, si todo está bien,
/// lo aprueba para trabajar.
class RevisarDocumentosScreen extends StatefulWidget {
  final String domiciliarioId;
  final String nombre;
  final String estado; // pendiente | aprobado | bloqueado

  const RevisarDocumentosScreen({
    super.key,
    required this.domiciliarioId,
    required this.nombre,
    required this.estado,
  });

  @override
  State<RevisarDocumentosScreen> createState() => _RevisarDocumentosScreenState();
}

class _RevisarDocumentosScreenState extends State<RevisarDocumentosScreen> {
  Map<String, Map<String, dynamic>> _docs = {};
  final Map<String, Future<String>> _urls = {}; // una dirección temporal por documento
  bool _cargando = true;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final docs = await DocumentosService.de(widget.domiciliarioId);
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _urls.clear();
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

  Future<String> _url(Map<String, dynamic> doc) =>
      _urls.putIfAbsent(doc['tipo'] as String, () => DocumentosService.urlParaVer(doc));

  Future<void> _revisar(TipoDocumento tipo, bool aprobar) async {
    String? motivo;
    if (!aprobar) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Rechazar: ${tipo.nombre}'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motivo (lo verá el domiciliario)',
              hintText: 'Ej. Foto borrosa, SOAT de otra placa',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Rechazar')),
          ],
        ),
      );
      if (ok != true) return;
      motivo = ctrl.text.trim();
    }
    setState(() => _ocupado = true);
    try {
      await DocumentosService.revisar(widget.domiciliarioId, tipo.id,
          aprobar: aprobar, motivo: motivo);
      await _cargar();
    } catch (e) {
      _aviso(AuthService.mensajeError(e));
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _aprobarDomiciliario() async {
    setState(() => _ocupado = true);
    try {
      await SaldoService.cambiarEstado(widget.domiciliarioId, 'aprobado');
      if (!mounted) return;
      _aviso('${widget.nombre} ya puede trabajar.');
      Navigator.pop(context, true);
      return;
    } catch (e) {
      _aviso(AuthService.mensajeError(e));
    }
    if (mounted) setState(() => _ocupado = false);
  }

  void _verGrande(String url, String titulo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(titulo),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          body: InteractiveViewer(
            maxScale: 5,
            child: Center(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(TipoDocumento tipo) {
    final doc = _docs[tipo.id];
    final estado = estadoDocumento(doc);
    final vence = doc?['vence_en'] as String?;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Paleta.borde),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: doc == null
                  ? Container(
                      decoration: BoxDecoration(
                        color: Paleta.fondo,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.hide_image_outlined, color: Paleta.gris),
                    )
                  : FutureBuilder<String>(
                      future: _url(doc),
                      builder: (_, snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                        }
                        return GestureDetector(
                          onTap: () => _verGrande(snap.data!, tipo.nombre),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: snap.data!,
                              // la dirección temporal cambia cada vez: se guarda por documento
                              cacheKey: '${doc['ruta']}_${doc['subido_en']}',
                              fit: BoxFit.cover,
                              memCacheWidth: 256,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tipo.nombre + (tipo.obligatorio ? '' : ' (opcional)'),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Paleta.marino),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    switch (estado) {
                      'falta' => 'No lo ha subido',
                      'pendiente' => 'Por revisar',
                      'aprobado' => 'Aprobado',
                      'rechazado' => 'Rechazado: ${doc?['motivo'] ?? ''}',
                      _ => 'Vencido',
                    },
                    style: TextStyle(
                      color: switch (estado) {
                        'aprobado' => Paleta.verde,
                        'pendiente' => Paleta.azul,
                        'falta' => Paleta.gris,
                        _ => Paleta.alerta,
                      },
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (vence != null)
                    Text('Vence: ${fechaCorta(vence)}',
                        style: const TextStyle(color: Paleta.gris, fontSize: 13)),
                  if (doc != null && estado != 'vencido')
                    Row(
                      children: [
                        if (estado != 'rechazado')
                          TextButton(
                            onPressed: _ocupado ? null : () => _revisar(tipo, false),
                            style: TextButton.styleFrom(foregroundColor: Paleta.alerta),
                            child: const Text('Rechazar'),
                          ),
                        if (estado != 'aprobado')
                          TextButton(
                            onPressed: _ocupado ? null : () => _revisar(tipo, true),
                            child: const Text('Aprobar'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final obligatorios = tiposDocumento.where((t) => t.obligatorio).toList();
    final todosAprobados =
        obligatorios.every((t) => estadoDocumento(_docs[t.id]) == 'aprobado') &&
            !_docs.values.any((d) => estadoDocumento(d) == 'vencido');

    return Scaffold(
      appBar: AppBar(title: Text(widget.nombre)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Toca una foto para verla en grande. El SOAT y la técnico-mecánica se pueden '
                    'confirmar por placa en la página del RUNT.',
                    style: TextStyle(color: Paleta.gris, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  for (final t in tiposDocumento) _tarjeta(t),
                  const SizedBox(height: 12),
                  if (widget.estado != 'aprobado')
                    BotonPrincipal(
                      texto: todosAprobados
                          ? 'Aprobar a ${widget.nombre.split(' ').first} para trabajar'
                          : 'Faltan documentos por aprobar',
                      icono: Icons.verified_rounded,
                      onPressed: todosAprobados && !_ocupado ? _aprobarDomiciliario : null,
                    ),
                ],
              ),
            ),
    );
  }
}
