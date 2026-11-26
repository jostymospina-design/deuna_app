import 'package:flutter/material.dart';
import '../core/formato.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../services/auth_service.dart';
import '../services/pedido_service.dart';
import '../widgets/componentes.dart';
import 'seguimiento_screen.dart';

/// Pantalla 5: Ofertas de repartidores (la subasta).
/// Las ofertas llegan en tiempo real desde Supabase.
class OfertasScreen extends StatefulWidget {
  final Pedido pedido;

  const OfertasScreen({super.key, required this.pedido});

  @override
  State<OfertasScreen> createState() => _OfertasScreenState();
}

class _OfertasScreenState extends State<OfertasScreen> {
  late final Stream<List<Map<String, dynamic>>> _ofertas =
      PedidoService.ofertas(widget.pedido.id!);
  final Set<String> _rechazadas = {}; // rechazar = ocultar en este celular
  bool _aceptando = false;

  Oferta _aOferta(Map<String, dynamic> o, Map<String, dynamic> d) =>
      PedidoService.ofertaDesde(o, d);

  Future<void> _aceptar(Oferta oferta) async {
    if (_aceptando) return;
    setState(() => _aceptando = true);
    try {
      await PedidoService.aceptar(oferta.id);
      widget.pedido.oferta = oferta;
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SeguimientoScreen(pedido: widget.pedido)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _aceptando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
    }
  }

  /// "Ajustar tarifa": cancela este pedido y vuelve a la pantalla de tarifa para crear otro.
  Future<void> _ajustarTarifa() async {
    final navegador = Navigator.of(context);
    try {
      await PedidoService.cancelar(widget.pedido.id!);
    } catch (_) {}
    if (navegador.canPop()) navegador.pop();
  }

  @override
  Widget build(BuildContext context) {
    // Atrás vuelve al inicio sin cancelar: el pedido sigue recibiendo ofertas.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) Navigator.of(context).popUntil((r) => r.isFirst);
      },
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ofertas,
        builder: (context, snap) {
          final filas = (snap.data ?? [])
              .where((o) => o['estado'] == 'pendiente' && !_rechazadas.contains(o['id']))
              .toList();
          final menorPrecio = filas.isEmpty
              ? 0
              : filas.map((o) => o['precio'] as int).reduce((a, b) => a < b ? a : b);
          final todasRechazadas = filas.isEmpty && _rechazadas.isNotEmpty;

          return Scaffold(
            appBar: AppBar(title: Text('Ofertas de repartidores (${filas.length})')),
            body: Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Paleta.azulClaro,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Paleta.azul),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Las ofertas llegan en tiempo real…',
                          style: TextStyle(
                            color: Paleta.azul,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filas.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inbox_outlined, size: 56, color: Paleta.gris),
                              const SizedBox(height: 12),
                              Text(
                                todasRechazadas
                                    ? 'Rechazaste todas las ofertas'
                                    : 'Esperando ofertas',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Paleta.marino,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Si no llegan, sube un poco la tarifa.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Paleta.gris),
                              ),
                              const SizedBox(height: 20),
                              BotonPrincipal(
                                texto: 'Cancelar y ajustar tarifa',
                                onPressed: _ajustarTarifa,
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          children: [
                            for (final fila in filas)
                              FutureBuilder<Map<String, dynamic>>(
                                key: ValueKey(fila['id']),
                                future: PedidoService.domiciliario(fila['domiciliario_id'] as String),
                                builder: (_, d) {
                                  if (!d.hasData) {
                                    return const SizedBox(
                                      height: 150,
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }
                                  final oferta = _aOferta(fila, d.data!);
                                  return _TarjetaOferta(
                                    oferta: oferta,
                                    tarifaOriginal: widget.pedido.tarifa,
                                    esMejor: oferta.precio == menorPrecio,
                                    onRechazar: () =>
                                        setState(() => _rechazadas.add(fila['id'] as String)),
                                    onAceptar: () => _aceptar(oferta),
                                  );
                                },
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaOferta extends StatelessWidget {
  final Oferta oferta;
  final int tarifaOriginal;
  final bool esMejor;
  final VoidCallback onRechazar;
  final VoidCallback onAceptar;

  const _TarjetaOferta({
    super.key,
    required this.oferta,
    required this.tarifaOriginal,
    required this.esMejor,
    required this.onRechazar,
    required this.onAceptar,
  });

  @override
  Widget build(BuildContext context) {
    final contraoferta = oferta.precio != tarifaOriginal;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
      builder: (contexto, valor, hijo) {
        return Opacity(
          opacity: valor,
          child: Transform.translate(offset: Offset(0, 18 * (1 - valor)), child: hijo),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: esMejor ? Paleta.azul : Paleta.borde,
            width: esMejor ? 2 : 1.2,
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FotoPerfil(
                  url: oferta.fotoUrl,
                  nombre: oferta.nombre,
                  radio: 26,
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
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Paleta.marino,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 17, color: Paleta.estrella),
                          const SizedBox(width: 3),
                          Text(
                            oferta.calificacion.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 13, color: Paleta.gris),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${oferta.vehiculo} · llega en ${oferta.minutosLlegada} min',
                        style: const TextStyle(fontSize: 12.5, color: Paleta.gris),
                      ),
                      if (oferta.verificado) ...[
                        const SizedBox(height: 6),
                        const EtiquetaVerificado(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pesos(oferta.precio),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: esMejor ? Paleta.azul : Paleta.marino,
                      ),
                    ),
                    if (contraoferta)
                      Text(
                        'Oferta: ${pesos(tarifaOriginal)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Paleta.gris,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    if (esMejor)
                      const Text(
                        'Mejor precio',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Paleta.azul,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: TextButton(
                      onPressed: onRechazar,
                      style: TextButton.styleFrom(
                        backgroundColor: Paleta.fondo,
                        foregroundColor: Paleta.gris,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Rechazar'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: onAceptar,
                      style: FilledButton.styleFrom(
                        backgroundColor: Paleta.verde,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Aceptar oferta'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
