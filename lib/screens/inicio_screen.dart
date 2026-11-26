import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../core/supabase_config.dart';
import '../core/tema.dart';
import '../data/datos_demo.dart';
import '../models/modelos.dart';
import '../providers/sesion_provider.dart';
import '../services/auth_service.dart';
import '../services/direcciones.dart';
import '../services/ubicacion.dart';
import '../widgets/componentes.dart';
import '../widgets/mapa_deuna.dart';
import '../widgets/menu_deuna.dart';
import '../services/pedido_service.dart';
import 'abrir_pedido.dart';
import 'detalles_paquete_screen.dart';
import 'historial_screen.dart';

/// Pantalla 1 (cliente): ¿A dónde enviamos hoy?
/// Los puntos se eligen con un pin fijo en el centro del mapa (como Uber).
class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  // Debe coincidir con el relleno del mapa: el centro de la cámara es el centro de esa zona.
  static const double _rellenoArriba = 90;
  static const double _rellenoAbajo = 380;

  final ControladorMapa _mapa = ControladorMapa();
  Lugar? _origen;
  Lugar? _destino;
  bool _buscandoGps = true;
  bool _permisoListo = false;
  String? _errorGps;
  String? _avisoPrecision;
  List<Lugar> _guardados = [];
  Map<String, dynamic>? _activo; // pedido en curso (buscando, asignado o recogido)
  StreamSubscription<List<Map<String, dynamic>>>? _subActivo;

  // Selección con pin central
  bool? _eligiendoOrigen; // null = no está eligiendo; true = recogida; false = entrega
  LatLng _centro = centroBucaramanga;
  String _direccionCentro = '';
  bool _buscandoDireccion = false;
  final TextEditingController _busqueda = TextEditingController();
  bool _buscandoTexto = false;

  @override
  void initState() {
    super.initState();
    _usarMiUbicacion();
    _cargarGuardados();
    _escucharActivo();
  }

  /// ¿Hay un pedido en curso? Se escucha en vivo: si el pedido termina, se cancela o se crea
  /// uno nuevo, el panel cambia solo. Si lo hay, el panel muestra "Ver mi pedido".
  void _escucharActivo() {
    _subActivo = PedidoService.ultimosDelCliente().listen((lista) {
      Map<String, dynamic>? activo;
      for (final p in lista) {
        if (const ['buscando', 'asignado', 'recogido'].contains(p['estado'])) {
          activo = p;
          break;
        }
      }
      if (mounted) setState(() => _activo = activo);
    }, onError: (_) {});
  }

  Future<void> _abrirActivo() async {
    final activo = _activo;
    if (activo == null) return;
    await abrirPedidoEnCurso(context, activo);
  }

  @override
  void dispose() {
    _subActivo?.cancel();
    _busqueda.dispose();
    _mapa.liberar();
    super.dispose();
  }

  Future<void> _usarMiUbicacion() async {
    setState(() {
      _buscandoGps = true;
      _errorGps = null;
      _avisoPrecision = null;
    });
    final rapida = await ServicioUbicacion.rapida();
    if (rapida != null && mounted) _mapa.moverA(rapida, zoom: 15);

    final resultado = await ServicioUbicacion.obtener();
    if (!mounted) return;

    final posicion = resultado.posicion;
    if (posicion == null) {
      setState(() {
        _errorGps = resultado.error;
        _buscandoGps = false;
      });
      return;
    }
    final direccion = await Direcciones.nombre(posicion);
    if (!mounted) return;
    setState(() {
      _permisoListo = true;
      _origen = Lugar(nombre: direccion, detalle: 'Mi ubicación (GPS)', posicion: posicion);
      _buscandoGps = false;
      if (resultado.aproximada) {
        _avisoPrecision = 'Ubicación aproximada (±${resultado.precisionM!.round()} m). '
            'Toca la recogida para ajustar el punto.';
      }
    });
    _ajustarCamara();
  }

  Future<void> _cargarGuardados() async {
    try {
      final filas = await supabase
          .from('lugares_guardados')
          .select('nombre, direccion, lat, lng')
          .order('nombre');
      if (!mounted) return;
      setState(() {
        _guardados = [
          for (final f in filas)
            Lugar(
              nombre: f['nombre'] as String,
              detalle: f['direccion'] as String,
              posicion: LatLng((f['lat'] as num).toDouble(), (f['lng'] as num).toDouble()),
            ),
        ];
      });
    } catch (_) {}
  }

  void _ajustarCamara() {
    final origen = _origen;
    final destino = _destino;
    if (origen == null) return;
    if (destino == null) {
      _mapa.moverA(origen.posicion, zoom: 15);
    } else {
      _mapa.ajustar(origen.posicion, destino.posicion, margen: 110);
    }
  }

  // ---------- Pin central ----------

  void _empezarAElegir(bool esOrigen) {
    final actual = esOrigen ? _origen : _destino;
    _busqueda.clear();
    setState(() {
      _eligiendoOrigen = esOrigen;
      _direccionCentro = '';
      _buscandoDireccion = true;
    });
    final punto = actual?.posicion ?? _origen?.posicion ?? _centro;
    _centro = punto;
    _mapa.moverA(punto, zoom: 17);
    _alDetenerCamara();
  }

  // Se llama muchas veces por segundo: NO usa setState.
  void _alMoverCamara(LatLng centro) => _centro = centro;

  // Se llama una vez cuando el mapa se detiene.
  Future<void> _alDetenerCamara() async {
    if (_eligiendoOrigen == null) return;
    final consultado = _centro;
    setState(() => _buscandoDireccion = true);
    final texto = await Direcciones.nombre(consultado);
    if (!mounted || consultado != _centro) return; // el usuario siguió moviendo el mapa
    setState(() {
      _direccionCentro = texto;
      _buscandoDireccion = false;
    });
  }

  /// Busca la dirección escrita y lleva el pin a ese punto (el usuario confirma o ajusta).
  Future<void> _buscarDireccion() async {
    final texto = _busqueda.text.trim();
    if (texto.length < 3 || _buscandoTexto) return;
    FocusScope.of(context).unfocus(); // cierra el teclado
    setState(() => _buscandoTexto = true);
    final punto = await Direcciones.buscar(texto);
    if (!mounted) return;
    setState(() => _buscandoTexto = false);
    if (punto == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No encontramos esa dirección. Escribe calle y número '
            '(ej. Calle 45 # 27-10) o mueve el mapa hasta el punto.'),
      ));
      return;
    }
    _centro = punto;
    _mapa.moverA(punto, zoom: 18);
    // Al detenerse la cámara se muestra la dirección exacta del punto encontrado.
  }

  void _confirmarPunto() {
    final lugar = Lugar(nombre: _direccionCentro, detalle: 'Punto elegido en el mapa', posicion: _centro);
    setState(() {
      if (_eligiendoOrigen!) {
        _origen = lugar;
        _avisoPrecision = null;
      } else {
        _destino = lugar;
      }
      _eligiendoOrigen = null;
    });
    _ajustarCamara();
  }

  Future<void> _guardarPunto() async {
    final nombre = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Guardar lugar'),
        content: TextField(
          controller: nombre,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre (ej. Casa, Trabajo, UTS)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || nombre.text.trim().isEmpty) return;
    try {
      await supabase.from('lugares_guardados').insert({
        'nombre': nombre.text.trim(),
        'direccion': _direccionCentro,
        'lat': _centro.latitude,
        'lng': _centro.longitude,
      });
      await _cargarGuardados();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('"${nombre.text.trim()}" guardado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
    }
  }

  // ---------- Hoja de opciones ----------

  Future<void> _elegirLugar({required bool esOrigen}) async {
    final elegido = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (contexto) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(contexto).size.height * 0.7),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              children: [
                Text(
                  esOrigen ? 'Dirección de recogida' : 'Dirección de entrega',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Paleta.marino,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.pin_drop_rounded, color: Paleta.verde),
                  title: const Text('Escribir dirección o elegir en el mapa',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Busca la dirección y ajusta el pin al punto exacto'),
                  onTap: () => Navigator.pop(contexto, 'mapa'),
                ),
                if (esOrigen)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.my_location_rounded, color: Paleta.verde),
                    title: const Text('Mi ubicación actual',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () => Navigator.pop(contexto, 'gps'),
                  ),
                if (_guardados.isNotEmpty) ...[
                  const Divider(),
                  const Text('Mis lugares', style: TextStyle(color: Paleta.gris)),
                ],
                for (final lugar in _guardados)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bookmark_rounded, color: Paleta.marino),
                    title: Text(lugar.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(lugar.detalle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(contexto, lugar),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (elegido == null || !mounted) return;
    if (elegido == 'mapa') {
      _empezarAElegir(esOrigen);
      return;
    }
    if (elegido == 'gps') {
      _usarMiUbicacion();
      return;
    }
    if (elegido is Lugar) {
      setState(() {
        if (esOrigen) {
          _origen = elegido;
        } else {
          _destino = elegido;
        }
      });
      _ajustarCamara();
    }
  }

  bool get _puedeContinuar {
    final origen = _origen;
    final destino = _destino;
    if (origen == null || destino == null) return false;
    final metros = Geolocator.distanceBetween(
      origen.posicion.latitude,
      origen.posicion.longitude,
      destino.posicion.latitude,
      destino.posicion.longitude,
    );
    return metros > 100;
  }

  Future<void> _continuar() async {
    final pedido = Pedido(origen: _origen!, destino: _destino!);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetallesPaqueteScreen(pedido: pedido)),
    );
  }

  Widget _panelActivo(Map<String, dynamic> activo) {
    final (titulo, detalle) = switch (activo['estado']) {
      'buscando' => ('Buscando domiciliario', 'Revisa las ofertas que te han llegado.'),
      'asignado' => ('El domiciliario va por tu paquete', 'Ten listo el código de recogida.'),
      _ => ('Tu paquete va en camino', 'Comparte el código de entrega con quien recibe.'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Tienes un pedido en curso',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Paleta.marino),
        ),
        const SizedBox(height: 12),
        RutaResumen(
          origen: activo['origen_nombre'] as String,
          destino: activo['destino_nombre'] as String,
        ),
        const SizedBox(height: 12),
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, color: Paleta.azul)),
        Text(detalle, style: const TextStyle(color: Paleta.gris)),
        const SizedBox(height: 16),
        BotonPrincipal(
          texto: 'Ver mi pedido',
          icono: Icons.arrow_forward_rounded,
          onPressed: _abrirActivo,
        ),
      ],
    );
  }

  List<MarcadorMapa> get _marcadores {
    if (_eligiendoOrigen != null) return const [];
    final origen = _origen;
    final destino = _destino;
    return [
      if (origen != null)
        MarcadorMapa(
          id: 'origen',
          posicion: origen.posicion,
          tipo: TipoMarcador.recogida,
          titulo: 'Recogida',
          detalle: origen.nombre,
        ),
      if (destino != null)
        MarcadorMapa(
          id: 'destino',
          posicion: destino.posicion,
          tipo: TipoMarcador.entrega,
          titulo: 'Entrega',
          detalle: destino.nombre,
        ),
    ];
  }

  Widget _panelEligiendo() {
    final esOrigen = _eligiendoOrigen!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _busqueda,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _buscarDireccion(),
          decoration: InputDecoration(
            hintText: 'Escribe la dirección (ej. Calle 45 # 27-10)',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _buscandoTexto
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: _buscarDireccion,
                  ),
            filled: true,
            fillColor: Paleta.fondo,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          esOrigen ? 'Punto de recogida' : 'Punto de entrega',
          style: const TextStyle(color: Paleta.gris, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          _buscandoDireccion ? 'Buscando dirección…' : _direccionCentro,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Paleta.marino),
        ),
        const SizedBox(height: 4),
        const Text(
          'Revisa que el pin quede en la puerta exacta; si no, mueve el mapa.',
          style: TextStyle(color: Paleta.gris, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        BotonPrincipal(
          texto: esOrigen ? 'Confirmar recogida' : 'Confirmar entrega',
          onPressed: _buscandoDireccion ? null : _confirmarPunto,
        ),
        Row(
          children: [
            TextButton(
              onPressed: () {
                setState(() => _eligiendoOrigen = null);
                _ajustarCamara();
              },
              child: const Text('Cancelar'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _buscandoDireccion ? null : _guardarPunto,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Guardar lugar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _panelNormal() {
    final origen = _origen;
    final destino = _destino;
    final mismoPunto = origen != null && destino != null && !_puedeContinuar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '¿A dónde enviamos hoy?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Paleta.marino),
        ),
        const SizedBox(height: 14),
        _CampoDireccion(
          icono: Icons.my_location_rounded,
          colorIcono: Paleta.verde,
          etiqueta: 'Dirección de recogida',
          valor: origen?.nombre ??
              (_buscandoGps ? 'Obteniendo tu ubicación…' : 'Elige el punto de recogida'),
          vacio: origen == null,
          onTap: () => _elegirLugar(esOrigen: true),
        ),
        const SizedBox(height: 10),
        _CampoDireccion(
          icono: Icons.location_on_rounded,
          colorIcono: Paleta.azul,
          etiqueta: 'Dirección de entrega',
          valor: destino?.nombre ?? 'Elige el punto de entrega',
          vacio: destino == null,
          onTap: () => _elegirLugar(esOrigen: false),
        ),
        if (_errorGps != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _errorGps!,
                  style: const TextStyle(color: Paleta.alerta, fontSize: 12.5),
                ),
              ),
              TextButton(onPressed: _usarMiUbicacion, child: const Text('Reintentar')),
            ],
          ),
        ],
        if (_avisoPrecision != null) ...[
          const SizedBox(height: 8),
          Text(_avisoPrecision!, style: const TextStyle(color: Paleta.azul, fontSize: 12.5)),
        ],
        if (mismoPunto) ...[
          const SizedBox(height: 8),
          const Text(
            'La entrega debe estar a más de 100 m de la recogida.',
            style: TextStyle(color: Paleta.alerta, fontSize: 12.5),
          ),
        ],
        if (_guardados.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final lugar in _guardados)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(lugar.nombre),
                      avatar: const Icon(Icons.bookmark_rounded, size: 18),
                      backgroundColor: Paleta.fondo,
                      side: const BorderSide(color: Paleta.borde),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Paleta.marino,
                      ),
                      onPressed: () {
                        setState(() => _destino = lugar);
                        _ajustarCamara();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        BotonPrincipal(
          texto: 'Continuar',
          onPressed: _puedeContinuar ? _continuar : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = context.select<SesionProvider, String>((s) => s.perfil?.nombre ?? '');
    final primerNombre = nombre.trim().isEmpty ? 'Hola' : nombre.trim().split(' ').first;
    final eligiendo = _eligiendoOrigen;

    return Scaffold(
      drawer: const MenuDeUna(),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapaDeUna(
              controlador: _mapa,
              centroInicial: centroBucaramanga,
              zoomInicial: 13.5,
              relleno: const EdgeInsets.only(top: _rellenoArriba, bottom: _rellenoAbajo),
              marcadores: _marcadores,
              miUbicacion: _permisoListo,
              onCamaraMovida: _alMoverCamara,
              onCamaraQuieta: _alDetenerCamara,
              onListo: _ajustarCamara,
            ),
          ),
          if (eligiendo != null)
            Positioned(
              top: _rellenoArriba,
              bottom: _rellenoAbajo,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, -22), // la punta del pin cae en el centro exacto
                    child: Icon(
                      Icons.location_on_rounded,
                      size: 44,
                      color: eligiendo ? Paleta.verde : Paleta.azul,
                      shadows: const [Shadow(color: Color(0x551B2340), blurRadius: 8)],
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      elevation: 3,
                      shadowColor: const Color(0x331B2340),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap: () => Scaffold.of(ctx).openDrawer(),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AvatarIniciales(nombre: nombre.isEmpty ? '?' : nombre, radio: 17),
                              const SizedBox(width: 10),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Hola 👋',
                                    style: TextStyle(fontSize: 11, color: Paleta.gris),
                                  ),
                                  Text(
                                    primerNombre,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Paleta.marino,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.menu_rounded, color: Paleta.marino, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  BotonRedondo(
                    icono: Icons.history_rounded,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistorialScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: PanelInferior(
              child: _activo != null
                  ? _panelActivo(_activo!)
                  : eligiendo != null
                      ? _panelEligiendo()
                      : _panelNormal(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoDireccion extends StatelessWidget {
  final IconData icono;
  final Color colorIcono;
  final String etiqueta;
  final String valor;
  final bool vacio;
  final VoidCallback onTap;

  const _CampoDireccion({
    required this.icono,
    required this.colorIcono,
    required this.etiqueta,
    required this.valor,
    required this.vacio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Paleta.fondo,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icono, color: colorIcono),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      etiqueta,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Paleta.gris,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: vacio ? Paleta.gris : Paleta.marino,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Paleta.gris),
            ],
          ),
        ),
      ),
    );
  }
}
