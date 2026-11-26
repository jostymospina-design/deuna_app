import 'package:flutter/material.dart';
import '../core/formato.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../services/auth_service.dart';
import '../services/pedido_service.dart';
import '../widgets/componentes.dart';
import '../widgets/mapa_deuna.dart';
import 'buscando_screen.dart';

/// Pantalla 3: Tarifa del envío.
class TarifaScreen extends StatefulWidget {
  final Pedido pedido;

  const TarifaScreen({super.key, required this.pedido});

  @override
  State<TarifaScreen> createState() => _TarifaScreenState();
}

class _TarifaScreenState extends State<TarifaScreen> {
  static const int _paso = 500;
  static const int _minimo = 3000;
  static const int _maximo = 100000;

  final ControladorMapa _mapa = ControladorMapa();
  late int _tarifa = widget.pedido.tarifaSugerida;

  void _bajar() {
    if (_tarifa - _paso >= _minimo) setState(() => _tarifa -= _paso);
  }

  void _subir() {
    if (_tarifa + _paso <= _maximo) setState(() => _tarifa += _paso);
  }

  bool _enviando = false;

  /// Crea el pedido en Supabase (la BD genera los dos códigos) y busca domiciliarios.
  Future<void> _buscarRepartidor() async {
    setState(() => _enviando = true);
    final pedido = widget.pedido;
    pedido.tarifa = _tarifa;
    try {
      pedido.id = await PedidoService.crear(pedido);
      final (recogida, entrega) = await PedidoService.codigos(pedido.id!);
      pedido.codigo = recogida;
      pedido.codigoEntrega = entrega;
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BuscandoScreen(pedido: pedido)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  void dispose() {
    _mapa.liberar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    final origen = pedido.origen.posicion;
    final destino = pedido.destino.posicion;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MapaDeUna(
              controlador: _mapa,
              centroInicial: origen,
              zoomInicial: 14,
              relleno: const EdgeInsets.only(top: 70, bottom: 420),
              marcadores: [
                MarcadorMapa(
                  id: 'origen',
                  posicion: origen,
                  tipo: TipoMarcador.recogida,
                  titulo: 'Recogida',
                  detalle: pedido.origen.nombre,
                ),
                MarcadorMapa(
                  id: 'destino',
                  posicion: destino,
                  tipo: TipoMarcador.entrega,
                  titulo: 'Entrega',
                  detalle: pedido.destino.nombre,
                ),
              ],
              ruta: [origen, destino],
              onListo: () {
                Future.delayed(const Duration(milliseconds: 350), () {
                  if (mounted) _mapa.ajustar(origen, destino, margen: 80);
                });
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  BotonRedondo(
                    icono: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x331B2340),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Tarifa del envío',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Paleta.marino,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: PanelInferior(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: RutaResumen(
                          origen: pedido.origen.nombre,
                          destino: pedido.destino.nombre,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            kilometros(pedido.distanciaKm),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Paleta.azul,
                            ),
                          ),
                          Text(
                            '~${pedido.minutos} min',
                            style: const TextStyle(fontSize: 13, color: Paleta.gris),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Paleta.azulClaro,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFBFD3FF)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Tarifa sugerida por DeUna: ${pesos(pedido.tarifaSugerida)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Paleta.azul,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _BotonPaso(icono: Icons.remove_rounded, onPressed: _bajar),
                            Expanded(
                              child: Center(
                                child: Text(
                                  pesos(_tarifa),
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    color: Paleta.marino,
                                  ),
                                ),
                              ),
                            ),
                            _BotonPaso(icono: Icons.add_rounded, onPressed: _subir),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Los repartidores cercanos verán tu oferta. Puedes recibir contraofertas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: Paleta.gris),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  BotonPrincipal(
                    texto: _enviando ? 'Creando pedido…' : 'Buscar repartidor',
                    icono: Icons.search_rounded,
                    onPressed: _enviando ? null : _buscarRepartidor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonPaso extends StatelessWidget {
  final IconData icono;
  final VoidCallback onPressed;

  const _BotonPaso({required this.icono, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icono, color: Paleta.marino),
        ),
      ),
    );
  }
}
