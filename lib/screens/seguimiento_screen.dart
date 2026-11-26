import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/supabase_config.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../services/auth_service.dart';
import '../services/pedido_service.dart';
import '../services/rastreo_service.dart';
import '../widgets/componentes.dart';
import '../widgets/mapa_deuna.dart';
import 'entrega_screen.dart';

enum Fase { recogiendo, enCamino, entregado }

/// Pantalla 6 (cliente): seguimiento en tiempo real del domiciliario.
/// - El estado del pedido llega por Realtime (Postgres Changes).
/// - La posición del domiciliario llega por Broadcast y solo redibuja el mapa.
/// - Muestra el código de recogida y luego el código de entrega.
class SeguimientoScreen extends StatefulWidget {
  final Pedido pedido;

  const SeguimientoScreen({super.key, required this.pedido});

  @override
  State<SeguimientoScreen> createState() => _SeguimientoScreenState();
}

class _SeguimientoScreenState extends State<SeguimientoScreen> {
  static const double _alturaPanel = 420;

  final ControladorMapa _mapa = ControladorMapa();
  final ValueNotifier<LatLng?> _posDomi = ValueNotifier(null);
  StreamSubscription<Map<String, dynamic>>? _subPedido;
  RealtimeChannel? _canal;
  Fase _fase = Fase.recogiendo;
  LatLng? _inicioDomi; // dónde estaba el domiciliario al aceptar (para la barra de progreso)
  String? _telefonoDomi;
  bool _saliendo = false;

  Oferta get _oferta => widget.pedido.oferta!;
  String get _id => widget.pedido.id!;
  LatLng get _origen => widget.pedido.origen.posicion;
  LatLng get _destino => widget.pedido.destino.posicion;

  @override
  void initState() {
    super.initState();

    // 1. Estado del pedido en vivo.
    _subPedido = PedidoService.pedido(_id).listen(_alCambiarPedido);

    // 2. Posición del domiciliario en vivo (la emite RastreoService en su celular).
    _canal = supabase
        .channel(RastreoService.nombreCanal(_id))
        .onBroadcast(
          event: 'pos',
          callback: (mensaje) {
            // Según la versión del paquete, los datos llegan directos o dentro de 'payload'.
            final datos = (mensaje['payload'] ?? mensaje) as Map;
            final lat = datos['lat'];
            final lng = datos['lng'];
            if (lat is num && lng is num) {
              _posDomi.value = LatLng(lat.toDouble(), lng.toDouble());
              _inicioDomi ??= _posDomi.value;
            }
          },
        )
        .subscribe();

    // 3. Última posición guardada y teléfono, mientras llega el primer mensaje.
    PedidoService.domiciliario(_oferta.domiciliarioId).then((d) {
      final perfil = d['perfiles'] as Map<String, dynamic>?;
      _telefonoDomi = perfil?['telefono'] as String?;
      final lat = d['lat'];
      final lng = d['lng'];
      if (_posDomi.value == null && lat is num && lng is num) {
        _posDomi.value = LatLng(lat.toDouble(), lng.toDouble());
        _inicioDomi ??= _posDomi.value;
      }
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _subPedido?.cancel();
    final canal = _canal;
    if (canal != null) supabase.removeChannel(canal);
    _posDomi.dispose();
    _mapa.liberar();
    super.dispose();
  }

  void _alCambiarPedido(Map<String, dynamic> p) {
    if (!mounted || _saliendo) return;
    final estado = p['estado'] as String;
    if (estado == 'cancelado') {
      _saliendo = true;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('El pedido fue cancelado.')));
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    final nueva = switch (estado) {
      'recogido' => Fase.enCamino,
      'entregado' => Fase.entregado,
      _ => Fase.recogiendo,
    };
    if (nueva == _fase) return;
    setState(() => _fase = nueva);
    _enfocar();
    if (nueva == Fase.entregado) _verResumen();
  }

  void _enfocar() {
    final pos = _posDomi.value;
    switch (_fase) {
      case Fase.recogiendo:
        _mapa.ajustar(pos ?? _origen, _origen, margen: 80);
      case Fase.enCamino:
        _mapa.ajustar(pos ?? _origen, _destino, margen: 80);
      case Fase.entregado:
        _mapa.ajustar(_origen, _destino, margen: 80);
    }
  }

  double _metros(LatLng a, LatLng b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

  /// Avance de la fase actual (0 a 1) según qué tan cerca está el domiciliario.
  double _progreso(LatLng? pos) {
    if (_fase == Fase.entregado) return 1;
    if (pos == null) return 0;
    final meta = _fase == Fase.recogiendo ? _origen : _destino;
    final inicio = _fase == Fase.recogiendo ? (_inicioDomi ?? pos) : _origen;
    final total = _metros(inicio, meta);
    if (total < 30) return 1;
    return (1 - _metros(pos, meta) / total).clamp(0.0, 1.0).toDouble();
  }

  String _textoEstimado(LatLng? pos) {
    if (_fase == Fase.entregado) return 'Paquete entregado';
    final meta = _fase == Fase.recogiendo ? _origen : _destino;
    if (pos == null) {
      return _fase == Fase.recogiendo
          ? 'Llega en: ~${_oferta.minutosLlegada} min'
          : 'En camino a la entrega';
    }
    // Moto en ciudad: ~25 km/h y 1,3 veces la línea recta.
    final minutos = max(1, (_metros(pos, meta) * 1.3 / 1000 / 25 * 60).round());
    return _fase == Fase.recogiendo ? 'Llega en: $minutos min' : 'Entrega en: $minutos min';
  }

  Future<void> _cancelar() async {
    if (_fase != Fase.recogiendo) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El domiciliario ya tiene tu paquete; no se puede cancelar.')));
      return;
    }
    final cancelar = await showDialog<bool>(
      context: context,
      builder: (contexto) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            '¿Cancelar el pedido?',
            style: TextStyle(fontWeight: FontWeight.w800, color: Paleta.marino),
          ),
          content: const Text('El domiciliario ya va en camino a recoger tu paquete.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contexto, false),
              child: const Text('Seguir con el pedido'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(contexto, true),
              style: FilledButton.styleFrom(backgroundColor: Paleta.alerta),
              child: const Text('Cancelar pedido'),
            ),
          ],
        );
      },
    );
    if (cancelar != true || !mounted) return;
    try {
      await PedidoService.cancelar(_id);
      // La suscripción recibe 'cancelado' y vuelve al inicio.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
    }
  }

  /// Respaldo: el cliente confirma la entrega sin código (por si el domiciliario no la marca).
  Future<void> _yaRecibi() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Ya recibieron el paquete?'),
        content: const Text('Confírmalo solo si el paquete ya llegó a su destino.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Todavía no')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, llegó')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PedidoService.finalizar(_id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
    }
  }

  void _llamar() {
    final tel = _telefonoDomi;
    if (tel == null || tel.isEmpty) return;
    launchUrl(Uri(scheme: 'tel', path: tel));
  }

  void _whatsapp() {
    final tel = (_telefonoDomi ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (tel.isEmpty) return;
    final numero = tel.length == 10 ? '57$tel' : tel; // celulares de Colombia
    launchUrl(Uri.parse('https://wa.me/$numero'), mode: LaunchMode.externalApplication);
  }

  void _compartirCodigoEntrega() {
    final codigo = widget.pedido.codigoEntrega ?? '';
    final texto = 'Tu pedido DeUna va en camino. Cuando llegue el domiciliario, '
        'dile este código de entrega: $codigo';
    launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Vuelve a la pantalla principal sin cancelar: el pedido sigue en curso.
  void _salirAlInicio() {
    _saliendo = true;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _verResumen() {
    _saliendo = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => EntregaScreen(pedido: widget.pedido)),
    );
  }

  Widget _tarjetaCodigo() {
    final recogiendo = _fase == Fase.recogiendo;
    final codigo = recogiendo ? widget.pedido.codigo : widget.pedido.codigoEntrega;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: recogiendo ? Paleta.verdeClaro : Paleta.azulClaro,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            recogiendo
                ? 'Código de recogida: dáselo al domiciliario cuando recoja el paquete'
                : 'Código de entrega: quien recibe se lo dice al domiciliario',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Paleta.marino, fontSize: 13),
          ),
          Text(
            codigo ?? '----',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 12,
              color: recogiendo ? Paleta.verde : Paleta.azul,
            ),
          ),
          if (!recogiendo)
            TextButton.icon(
              onPressed: _compartirCodigoEntrega,
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Enviar a quien recibe'),
            )
          else
            const Text(
              'No lo compartas antes de que llegue.',
              style: TextStyle(fontSize: 11.5, color: Paleta.gris),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oferta = _oferta;

    // "Atrás" no cancela: vuelve al inicio y el pedido sigue (se retoma con "Ver mi pedido").
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _salirAlInicio();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              // Solo el mapa se redibuja cuando el domiciliario se mueve.
              child: ValueListenableBuilder<LatLng?>(
                valueListenable: _posDomi,
                builder: (context, pos, _) => MapaDeUna(
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
                      detalle: widget.pedido.origen.nombre,
                    ),
                    MarcadorMapa(
                      id: 'destino',
                      posicion: _destino,
                      tipo: TipoMarcador.entrega,
                      titulo: 'Entrega',
                      detalle: widget.pedido.destino.nombre,
                    ),
                    if (pos != null)
                      MarcadorMapa(
                        id: 'repartidor',
                        posicion: pos,
                        tipo: TipoMarcador.repartidor,
                        titulo: oferta.nombre,
                        detalle: oferta.vehiculo,
                      ),
                  ],
                  ruta: [
                    if (pos != null && _fase != Fase.entregado) pos,
                    if (_fase == Fase.recogiendo) _origen,
                    _destino,
                  ],
                  onListo: () {
                    Future.delayed(const Duration(milliseconds: 400), () {
                      if (mounted) _enfocar();
                    });
                  },
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    BotonRedondo(icono: Icons.arrow_back_rounded, onPressed: _salirAlInicio),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Paleta.marino,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _fase == Fase.entregado
                                ? Icons.check_circle_rounded
                                : Icons.schedule_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          ValueListenableBuilder<LatLng?>(
                            valueListenable: _posDomi,
                            builder: (_, pos, __) => Text(
                              _textoEstimado(pos),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    BotonRedondo(icono: Icons.center_focus_strong_rounded, onPressed: _enfocar),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: PanelInferior(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        FotoPerfil(
                          url: oferta.fotoUrl,
                          nombre: oferta.nombre,
                          radio: 24,
                          verificado: oferta.verificado,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                oferta.nombre,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Paleta.marino,
                                ),
                              ),
                              Text(
                                oferta.vehiculo,
                                style: const TextStyle(fontSize: 13, color: Paleta.gris),
                              ),
                            ],
                          ),
                        ),
                        if (_telefonoDomi != null) ...[
                          _AccionRepartidor(
                            icono: Icons.chat_bubble_outline_rounded,
                            onPressed: _whatsapp,
                          ),
                          const SizedBox(width: 8),
                          _AccionRepartidor(icono: Icons.phone_outlined, onPressed: _llamar),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_fase != Fase.entregado) ...[
                      _tarjetaCodigo(),
                      const SizedBox(height: 14),
                    ],
                    ValueListenableBuilder<LatLng?>(
                      valueListenable: _posDomi,
                      builder: (_, pos, __) => _PasosEntrega(fase: _fase, progreso: _progreso(pos)),
                    ),
                    const SizedBox(height: 14),
                    if (_fase == Fase.enCamino)
                      BotonSecundario(texto: 'Ya recibieron mi paquete', onPressed: _yaRecibi)
                    else
                      BotonPrincipal(
                        texto: 'Ver resumen de la entrega',
                        onPressed: _fase == Fase.entregado ? _verResumen : null,
                      ),
                    if (_fase == Fase.recogiendo)
                      Center(
                        child: TextButton(
                          onPressed: _cancelar,
                          style: TextButton.styleFrom(foregroundColor: Paleta.alerta),
                          child: const Text('Cancelar pedido'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccionRepartidor extends StatelessWidget {
  final IconData icono;
  final VoidCallback onPressed;

  const _AccionRepartidor({required this.icono, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Paleta.azulClaro,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icono, color: Paleta.azul, size: 22),
        ),
      ),
    );
  }
}

/// Barra de tres tramos: Recogiendo, En camino y Entregado.
class _PasosEntrega extends StatelessWidget {
  final Fase fase;
  final double progreso;

  const _PasosEntrega({required this.fase, required this.progreso});

  @override
  Widget build(BuildContext context) {
    double valor(Fase tramo) {
      if (fase.index > tramo.index) return 1;
      if (fase.index == tramo.index) return fase == Fase.entregado ? 1 : progreso;
      return 0;
    }

    Widget tramo(String texto, Fase f) {
      final activo = fase.index >= f.index;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: valor(f),
                  minHeight: 6,
                  color: Paleta.azul,
                  backgroundColor: Paleta.borde,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                texto,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: activo ? FontWeight.w800 : FontWeight.w500,
                  color: activo ? Paleta.azul : Paleta.gris,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        tramo('Recogiendo', Fase.recogiendo),
        tramo('En camino', Fase.enCamino),
        tramo('Entregado', Fase.entregado),
      ],
    );
  }
}
