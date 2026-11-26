import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/formato.dart';
import '../../core/supabase_config.dart';
import '../../core/tema.dart';
import '../../data/datos_demo.dart';
import '../../providers/sesion_provider.dart';
import '../../services/auth_service.dart';
import '../../services/pedido_service.dart';
import '../../services/rastreo_service.dart';
import '../../services/ubicacion.dart';
import '../../widgets/componentes.dart';
import '../../widgets/mapa_deuna.dart';
import '../../widgets/menu_deuna.dart';
import 'entrega_domiciliario_screen.dart';
import 'recargas_screen.dart';

/// Inicio del modo domiciliario: conectarse, ver pedidos cercanos y ofertar.
class InicioDomiciliarioScreen extends StatefulWidget {
  const InicioDomiciliarioScreen({super.key});

  @override
  State<InicioDomiciliarioScreen> createState() => _InicioDomiciliarioScreenState();
}

class _InicioDomiciliarioScreenState extends State<InicioDomiciliarioScreen> {
  static const double _alturaPanel = 330;

  final ControladorMapa _mapa = ControladorMapa();
  LatLng? _miPos;
  String? _errorGps;
  bool _disponible = false;
  bool _cargando = false;
  List<Map<String, dynamic>> _pedidos = [];
  double _porcentaje = 10;

  RealtimeChannel? _canal;
  Timer? _espera; // agrupa varios avisos de pedidos nuevos en una sola consulta
  Timer? _refresco; // refresca la lista cada 20 s (quita pedidos que ya tomó otro)
  Timer? _sondeo; // mientras espera la respuesta del cliente
  String? _esperandoPedido;
  Map<String, dynamic>? _pedidoActivo; // entrega en curso (asignado o recogido)

  @override
  void initState() {
    super.initState();
    _ubicar();
    _cargarPorcentaje();
    _revisarPedidoActivo();
  }

  @override
  void dispose() {
    _desconectar(guardar: false);
    _sondeo?.cancel();
    _mapa.liberar();
    super.dispose();
  }

  Future<void> _ubicar() async {
    final rapida = await ServicioUbicacion.rapida();
    if (rapida != null && mounted) {
      setState(() => _miPos = rapida);
      _mapa.moverA(rapida, zoom: 14);
    }
    final r = await ServicioUbicacion.obtener();
    if (!mounted) return;
    setState(() {
      _miPos = r.posicion ?? _miPos;
      _errorGps = r.error;
    });
    if (r.posicion != null) _mapa.moverA(r.posicion!, zoom: 14);
  }

  Future<void> _cargarPorcentaje() async {
    final dom = context.read<SesionProvider>().domiciliario;
    if (dom == null) return;
    try {
      final m = await supabase
          .from('mensajerias')
          .select('porcentaje_comision')
          .eq('id', dom.mensajeriaId)
          .single();
      if (mounted) setState(() => _porcentaje = (m['porcentaje_comision'] as num).toDouble());
    } catch (_) {}
  }

  /// ¿Tiene una entrega en curso? (por ejemplo, si cerró la app o salió de la pantalla)
  Future<void> _revisarPedidoActivo({bool abrir = true}) async {
    try {
      final activo = await supabase
          .from('pedidos')
          .select()
          .eq('domiciliario_id', miId)
          .inFilter('estado', ['asignado', 'recogido'])
          .limit(1)
          .maybeSingle();
      // Si el pedido ya terminó o lo cancelaron, el GPS deja de enviar.
      final rastreo = RastreoService.instancia;
      if (rastreo.pedidoActual != null && rastreo.pedidoActual != activo?['id']) {
        rastreo.detener();
      }
      if (!mounted) return;
      setState(() => _pedidoActivo = activo);
      if (activo != null && abrir) _abrirEntrega(activo);
    } catch (_) {}
  }

  Future<void> _cambiarDisponible(bool valor) async {
    if (valor && _pedidoActivo != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Termina tu entrega en curso antes de buscar más pedidos.')));
      return;
    }
    if (valor) {
      if (_miPos == null) {
        await _ubicar();
        if (_miPos == null) return;
      }
      setState(() => _disponible = true);
      try {
        await supabase.from('domiciliarios').update({
          'disponible': true,
          'lat': _miPos!.latitude,
          'lng': _miPos!.longitude,
          'ubicacion_en': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', miId);
      } catch (_) {}
      _conectar();
    } else {
      _desconectar();
      setState(() {
        _disponible = false;
        _pedidos = [];
      });
    }
  }

  void _conectar() {
    _cargar();
    _canal = supabase
        .channel('pedidos-nuevos-$miId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pedidos',
          callback: (_) {
            _espera?.cancel();
            _espera = Timer(const Duration(seconds: 1), _cargar);
          },
        )
        .subscribe();
    _refresco = Timer.periodic(const Duration(seconds: 20), (_) => _cargar());
  }

  void _desconectar({bool guardar = true}) {
    _espera?.cancel();
    _refresco?.cancel();
    final canal = _canal;
    _canal = null;
    if (canal != null) supabase.removeChannel(canal);
    if (guardar) {
      supabase
          .from('domiciliarios')
          .update({'disponible': false})
          .eq('id', miId)
          .then((_) {}, onError: (_) {});
    }
  }

  Future<void> _cargar() async {
    final pos = _miPos;
    if (pos == null || _cargando) return;
    _cargando = true;
    try {
      final lista = await PedidoService.cercanos(pos.latitude, pos.longitude);
      if (mounted) setState(() => _pedidos = lista);
    } catch (_) {}
    _cargando = false;
  }

  int _comision(int precio) => (precio * _porcentaje / 100).ceil();

  Future<void> _ofertar(Map<String, dynamic> p) async {
    final saldo = context.read<SesionProvider>().domiciliario?.saldo ?? 0;
    int precio = p['tarifa_ofrecida'] as int;
    int minutos = 10;

    final enviar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (c) => StatefulBuilder(
        builder: (c, actualizar) {
          final comision = _comision(precio);
          final alcanza = saldo >= comision;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RutaResumen(
                    origen: p['origen_nombre'] as String,
                    destino: p['destino_nombre'] as String,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${p['tipo_paquete']} · '
                    '${kilometros((p['distancia_km'] as num).toDouble())}'
                    '${(p['indicaciones'] as String? ?? '').isEmpty ? '' : '\n${p['indicaciones']}'}',
                    style: const TextStyle(color: Paleta.gris),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        onPressed: precio > 3000 ? () => actualizar(() => precio -= 500) : null,
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        pesos(precio),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Paleta.azul,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton.filledTonal(
                        onPressed: () => actualizar(() => precio += 500),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  Center(
                    child: Text(
                      'El cliente ofreció ${pesos(p['tarifa_ofrecida'] as int)} · '
                      'comisión ${pesos(comision)}',
                      style: const TextStyle(fontSize: 12.5, color: Paleta.gris),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Llego a recoger en',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Paleta.marino)),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in const [5, 10, 15, 20])
                        ChoiceChip(
                          label: Text('$m min'),
                          selected: minutos == m,
                          onSelected: (_) => actualizar(() => minutos = m),
                        ),
                    ],
                  ),
                  if (!alcanza) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Tu saldo (${pesosConSigno(saldo)}) no cubre la comisión. Recarga para ofertar.',
                      style: const TextStyle(color: Paleta.alerta),
                    ),
                  ],
                  const SizedBox(height: 16),
                  BotonPrincipal(
                    texto: 'Enviar oferta',
                    onPressed: alcanza ? () => Navigator.pop(c, true) : null,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (enviar != true) return;
    try {
      await PedidoService.ofertar(p['id'] as String, precio, minutos);
      _esperarRespuesta(p['id'] as String);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
      _cargar();
    }
  }

  /// Revisa cada 4 s si el cliente aceptó la oferta.
  /// (Si eligen a otro domiciliario, la seguridad de la BD oculta el pedido: por eso se consulta.)
  void _esperarRespuesta(String pedidoId) {
    _sondeo?.cancel();
    setState(() => _esperandoPedido = pedidoId);
    _sondeo = Timer.periodic(const Duration(seconds: 4), (_) async {
      Map<String, dynamic>? p;
      try {
        p = await PedidoService.consultar(pedidoId);
      } catch (_) {
        return; // sin internet: vuelve a intentar en 4 s
      }
      if (!mounted || _esperandoPedido != pedidoId) return;
      if (p != null && p['estado'] == 'buscando') return; // sigue esperando
      _dejarDeEsperar();
      if (p != null && p['domiciliario_id'] == miId) {
        _abrirEntrega(p);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('El cliente eligió otra oferta o canceló el pedido.')));
        _cargar();
      }
    });
  }

  void _dejarDeEsperar() {
    _sondeo?.cancel();
    if (mounted) setState(() => _esperandoPedido = null);
  }

  Future<void> _abrirEntrega(Map<String, dynamic> pedido) async {
    _desconectar();
    setState(() {
      _disponible = false;
      _pedidoActivo = pedido;
      _pedidos = [];
    });
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EntregaDomiciliarioScreen(pedido: pedido)),
    );
    // Al volver: ¿la entrega terminó o solo salió de la pantalla?
    _revisarPedidoActivo(abrir: false);
  }

  List<MarcadorMapa> get _marcadores => [
        for (final p in _pedidos)
          MarcadorMapa(
            id: p['id'] as String,
            posicion: LatLng(
              (p['origen_lat'] as num).toDouble(),
              (p['origen_lng'] as num).toDouble(),
            ),
            tipo: TipoMarcador.recogida,
            titulo: pesos(p['tarifa_ofrecida'] as int),
            detalle: p['origen_nombre'] as String,
          ),
      ];

  Widget _panel() {
    final activo = _pedidoActivo;
    if (activo != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tienes una entrega en curso',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Paleta.marino),
          ),
          const SizedBox(height: 6),
          Text(
            '${activo['origen_nombre']} → ${activo['destino_nombre']}\n'
            '${activo['estado'] == 'recogido' ? 'Paquete recogido: llévalo al destino.' : 'Ve a recoger el paquete.'}',
            style: const TextStyle(color: Paleta.gris),
          ),
          const SizedBox(height: 16),
          BotonPrincipal(
            texto: 'Volver a la entrega',
            icono: Icons.two_wheeler_rounded,
            onPressed: () => _abrirEntrega(activo),
          ),
        ],
      );
    }
    if (_esperandoPedido != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            'Oferta enviada. Esperando la respuesta del cliente…',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, color: Paleta.marino),
          ),
          TextButton(onPressed: _dejarDeEsperar, child: const Text('Ver otros pedidos')),
        ],
      );
    }
    if (!_disponible) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Estás desconectado',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Paleta.marino),
          ),
          const SizedBox(height: 4),
          Text(
            _errorGps ?? 'Conéctate para ver los pedidos a menos de 5 km.',
            style: TextStyle(color: _errorGps == null ? Paleta.gris : Paleta.alerta),
          ),
          const SizedBox(height: 16),
          BotonPrincipal(
            texto: 'Conectarme',
            icono: Icons.power_settings_new_rounded,
            onPressed: () => _cambiarDisponible(true),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _pedidos.isEmpty ? 'Buscando pedidos cerca…' : 'Pedidos cerca (${_pedidos.length})',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Paleta.marino,
                ),
              ),
            ),
            IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        SizedBox(
          height: 200,
          child: _pedidos.isEmpty
              ? const Center(
                  child: Text(
                    'Los pedidos nuevos aparecen aquí solos.',
                    style: TextStyle(color: Paleta.gris),
                  ),
                )
              : ListView.separated(
                  itemCount: _pedidos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = _pedidos[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2_rounded, color: Paleta.verde),
                      title: Text(
                        '${p['origen_nombre']} → ${p['destino_nombre']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${p['tipo_paquete']} · '
                        '${kilometros((p['distancia_km'] as num).toDouble())}',
                      ),
                      trailing: Text(
                        pesos(p['tarifa_ofrecida'] as int),
                        style: const TextStyle(
                          color: Paleta.azul,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      onTap: () => _ofertar(p),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final saldo = context.select<SesionProvider, int>((s) => s.domiciliario?.saldo ?? 0);

    return Scaffold(
      drawer: const MenuDeUna(),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapaDeUna(
              controlador: _mapa,
              centroInicial: _miPos ?? centroBucaramanga,
              zoomInicial: 13.5,
              miUbicacion: _miPos != null,
              relleno: const EdgeInsets.only(top: 80, bottom: _alturaPanel),
              marcadores: _marcadores,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => BotonRedondo(
                      icono: Icons.menu_rounded,
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: saldo < 2000 ? Paleta.alerta : Paleta.marino,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RecargasScreen()),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.account_balance_wallet_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              saldo < 2000 ? 'Recarga · ${pesosConSigno(saldo)}' : pesos(saldo),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _disponible ? 'Conectado' : 'Desconectado',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _disponible ? Paleta.verde : Paleta.gris,
                          ),
                        ),
                        Switch(value: _disponible, onChanged: _cambiarDisponible),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: PanelInferior(child: _panel()),
          ),
        ],
      ),
    );
  }
}
