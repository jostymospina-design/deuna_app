import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../providers/sesion_provider.dart';
import '../../services/auth_service.dart';
import '../../services/pedido_service.dart';
import '../../services/push_service.dart';
import '../../services/rastreo_service.dart';
import '../../widgets/componentes.dart';
import '../../widgets/mapa_deuna.dart';

/// Entrega en curso (domiciliario): comparte su ubicación en vivo,
/// verifica el código de recogida y luego el código de entrega.
class EntregaDomiciliarioScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const EntregaDomiciliarioScreen({super.key, required this.pedido});

  @override
  State<EntregaDomiciliarioScreen> createState() => _EntregaDomiciliarioScreenState();
}

class _EntregaDomiciliarioScreenState extends State<EntregaDomiciliarioScreen> {
  static const double _alturaPanel = 400;

  final ControladorMapa _mapa = ControladorMapa();
  final RastreoService _rastreo = RastreoService.instancia;
  final TextEditingController _codigo = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _subPedido;

  late String _estado = widget.pedido['estado'] as String; // asignado | recogido
  late final Future<Map<String, dynamic>?> _cliente =
      PedidoService.cliente(widget.pedido['cliente_id'] as String);
  bool _enviando = false;
  bool _terminado = false;

  String get _id => widget.pedido['id'] as String;
  LatLng get _origen => LatLng(
        (widget.pedido['origen_lat'] as num).toDouble(),
        (widget.pedido['origen_lng'] as num).toDouble(),
      );
  LatLng get _destino => LatLng(
        (widget.pedido['destino_lat'] as num).toDouble(),
        (widget.pedido['destino_lng'] as num).toDouble(),
      );
  bool get _recogido => _estado == 'recogido';
  int get _precio => (widget.pedido['precio_final'] ?? widget.pedido['tarifa_ofrecida']) as int;

  @override
  void initState() {
    super.initState();
    _rastreo.iniciar(_id);
    // Avisa si el cliente cancela o confirma la entrega desde su celular.
    _subPedido = PedidoService.pedido(_id).listen((p) {
      final estado = p['estado'] as String;
      if (!mounted || estado == _estado) return;
      if (estado == 'cancelado') {
        _salir('El cliente canceló el pedido.');
      } else if (estado == 'entregado') {
        _salir('Entrega confirmada. ¡Buen trabajo!');
      } else {
        setState(() => _estado = estado);
        _enfocar();
      }
    });
  }

  @override
  void dispose() {
    _subPedido?.cancel(); // el rastreo NO se detiene: sigue mientras dure la entrega
    _codigo.dispose();
    _mapa.liberar();
    super.dispose();
  }

  void _enfocar() => _mapa.ajustar(_origen, _destino, margen: 80);

  Future<void> _salir(String mensaje) async {
    if (_terminado) return;
    _terminado = true;
    _rastreo.detener(); // la entrega terminó o se canceló: el GPS deja de enviar
    final sesion = context.read<SesionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navegador = Navigator.of(context);
    await sesion.recargar(); // saldo actualizado después de la comisión
    messenger.showSnackBar(SnackBar(content: Text(mensaje)));
    navegador.popUntil((r) => r.isFirst);
  }

  Future<void> _verificar() async {
    final texto = _codigo.text.trim();
    if (texto.length != 4) return;
    setState(() => _enviando = true);
    try {
      if (!_recogido) {
        final ok = await PedidoService.verificarCodigo(_id, texto);
        if (!mounted) return;
        if (ok) {
          _codigo.clear();
          setState(() => _estado = 'recogido');
          _enfocar();
          _aviso('Código correcto. Lleva el paquete al destino.');
        } else {
          _aviso('Código de recogida incorrecto. Verifica con el cliente.');
        }
      } else {
        final ok = await PedidoService.finalizar(_id, codigo: texto);
        if (!mounted) return;
        if (ok) {
          await _salir('Entrega completada. Se descontó la comisión de tu saldo.');
          return;
        }
        _aviso('Código de entrega incorrecto. No entregues el paquete hasta confirmarlo.');
      }
    } catch (e) {
      if (mounted) _aviso(AuthService.mensajeError(e));
    }
    if (mounted) setState(() => _enviando = false);
  }

  void _aviso(String texto) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _navegar() async {
    final p = _recogido ? _destino : _origen;
    final app = Uri.parse('google.navigation:q=${p.latitude},${p.longitude}&mode=l');
    final web = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${p.latitude},${p.longitude}');
    if (!await launchUrl(app)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    final indicaciones = (pedido['indicaciones'] as String?) ?? '';

    // Se puede salir con "atrás": la entrega sigue activa y se retoma desde el inicio.
    return PopScope(
      onPopInvokedWithResult: (salio, _) {
        if (salio && !_terminado) {
          mensajeroGlobal.currentState?.showSnackBar(const SnackBar(
              content: Text('La entrega sigue en curso. Vuelve a ella desde el inicio.')));
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: MapaDeUna(
                controlador: _mapa,
                centroInicial: _origen,
                zoomInicial: 14,
                miUbicacion: true,
                relleno: const EdgeInsets.only(top: 80, bottom: _alturaPanel),
                marcadores: [
                  MarcadorMapa(
                    id: 'origen',
                    posicion: _origen,
                    tipo: TipoMarcador.recogida,
                    titulo: 'Recogida',
                    detalle: pedido['origen_nombre'] as String,
                  ),
                  MarcadorMapa(
                    id: 'destino',
                    posicion: _destino,
                    tipo: TipoMarcador.entrega,
                    titulo: 'Entrega',
                    detalle: pedido['destino_nombre'] as String,
                  ),
                ],
                ruta: [_origen, _destino],
                onListo: () => _mapa.ajustar(_origen, _destino, margen: 80),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    BotonRedondo(
                      icono: Icons.arrow_back_rounded,
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Paleta.marino,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        _recogido ? 'Paso 2 de 2 · Entregar' : 'Paso 1 de 2 · Recoger',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(),
                    BotonRedondo(icono: Icons.navigation_rounded, onPressed: _navegar),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              // Con el teclado abierto el panel se puede desplazar en vez de desbordarse.
              child: SingleChildScrollView(
               child: PanelInferior(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FutureBuilder<Map<String, dynamic>?>(
                      future: _cliente,
                      builder: (_, snap) {
                        final nombre = (snap.data?['nombre'] as String?) ?? 'Cliente';
                        final tel = (snap.data?['telefono'] as String?) ?? '';
                        return Row(
                          children: [
                            AvatarIniciales(nombre: nombre, radio: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nombre,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Paleta.marino,
                                    ),
                                  ),
                                  Text(
                                    'Cobra ${pesos(_precio)} en efectivo',
                                    style: const TextStyle(color: Paleta.azul, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                            if (tel.isNotEmpty)
                              BotonRedondo(
                                icono: Icons.phone_rounded,
                                onPressed: () => launchUrl(Uri(scheme: 'tel', path: tel)),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    RutaResumen(
                      origen: pedido['origen_nombre'] as String,
                      destino: pedido['destino_nombre'] as String,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${pedido['tipo_paquete']}'
                      '${indicaciones.isEmpty ? '' : ' · $indicaciones'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Paleta.gris, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _recogido
                          ? 'Al llegar, pide el código de entrega a quien recibe'
                          : 'Al recoger, pide al cliente el código de recogida',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Paleta.marino),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codigo,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        fontSize: 28,
                        letterSpacing: 14,
                        fontWeight: FontWeight.w900,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '----',
                        filled: true,
                        fillColor: Paleta.fondo,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _verificar(),
                    ),
                    const SizedBox(height: 12),
                    BotonPrincipal(
                      texto: _enviando
                          ? 'Verificando…'
                          : (_recogido ? 'Confirmar entrega' : 'Verificar código de recogida'),
                      icono: _recogido ? Icons.check_circle_rounded : Icons.lock_open_rounded,
                      onPressed: _enviando ? null : _verificar,
                    ),
                  ],
                ),
              ),
             ),
            ),
          ],
        ),
      ),
    );
  }
}
