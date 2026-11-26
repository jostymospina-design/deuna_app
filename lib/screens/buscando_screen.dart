import 'dart:async';
import 'package:flutter/material.dart';
import '../core/formato.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../services/pedido_service.dart';
import '../widgets/componentes.dart';
import '../widgets/mapa_deuna.dart';
import 'ofertas_screen.dart';

/// Pantalla 4: Buscando repartidores.
/// Espera la primera oferta real de un domiciliario y pasa sola a las ofertas.
class BuscandoScreen extends StatefulWidget {
  final Pedido pedido;

  const BuscandoScreen({super.key, required this.pedido});

  @override
  State<BuscandoScreen> createState() => _BuscandoScreenState();
}

class _BuscandoScreenState extends State<BuscandoScreen>
    with SingleTickerProviderStateMixin {
  static const double _alturaPanel = 300;

  late final AnimationController _radar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  final ControladorMapa _mapa = ControladorMapa();
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = PedidoService.ofertas(widget.pedido.id!).listen((lista) {
      if (lista.isNotEmpty) {
        _sub?.cancel();
        _irAOfertas();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _radar.dispose();
    _mapa.liberar();
    super.dispose();
  }

  void _irAOfertas() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => OfertasScreen(pedido: widget.pedido)),
    );
  }

  /// Vuelve al inicio sin cancelar: el pedido sigue buscando y se retoma con "Ver mi pedido".
  void _salirAlInicio() {
    _sub?.cancel();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _cancelar() async {
    _sub?.cancel();
    final navegador = Navigator.of(context);
    try {
      await PedidoService.cancelar(widget.pedido.id!);
    } catch (_) {}
    navegador.pop();
  }

  Widget _anillo(double progreso) {
    final tamano = 40 + progreso * 240;
    final opacidad = (1 - progreso).clamp(0.0, 1.0).toDouble();
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Paleta.azul.withValues(alpha: 0.10 * opacidad),
        border: Border.all(
          color: Paleta.azul.withValues(alpha: 0.55 * opacidad),
          width: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (volvio, _) {
        if (!volvio) _salirAlInicio(); // atrás no cancela; "Cancelar búsqueda" sí
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: MapaDeUna(
                controlador: _mapa,
                centroInicial: pedido.origen.posicion,
                zoomInicial: 15,
                relleno: const EdgeInsets.only(bottom: _alturaPanel),
                interactivo: false,
                onListo: () => _mapa.moverA(pedido.origen.posicion, zoom: 15),
              ),
            ),
            Positioned.fill(
              bottom: _alturaPanel,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _radar,
                    builder: (contexto, _) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          for (int i = 0; i < 3; i++)
                            _anillo((_radar.value + i / 3) % 1),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Paleta.azul,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: const [
                                BoxShadow(color: Color(0x552F6BFF), blurRadius: 10),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: BotonRedondo(
                  icono: Icons.arrow_back_rounded,
                  onPressed: _salirAlInicio,
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
                    const Text(
                      'Buscando repartidores…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Paleta.marino,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ofreciendo tu tarifa de',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Paleta.gris),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pesos(pedido.tarifa),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        color: Paleta.azul,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        color: Paleta.azul,
                        backgroundColor: Paleta.azulClaro,
                      ),
                    ),
                    const SizedBox(height: 20),
                    BotonSecundario(
                      texto: 'Cancelar búsqueda',
                      color: Paleta.alerta,
                      onPressed: _cancelar,
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
