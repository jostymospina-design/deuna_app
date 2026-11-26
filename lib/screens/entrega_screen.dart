import 'package:flutter/material.dart';
import '../core/formato.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../widgets/componentes.dart';
import '../services/pedido_service.dart';

/// Pantalla 7: Entrega completada, con calificación y propina.
class EntregaScreen extends StatefulWidget {
  final Pedido pedido;

  const EntregaScreen({super.key, required this.pedido});

  @override
  State<EntregaScreen> createState() => _EntregaScreenState();
}

class _EntregaScreenState extends State<EntregaScreen> {
  static const List<int> _propinas = [500, 1000, 2000];

  int _estrellas = 0;
  int _propina = 0;

  bool _enviando = false;

  Future<void> _finalizar() async {
    widget.pedido.calificacion = _estrellas;
    widget.pedido.propina = _propina;
    final navegador = Navigator.of(context);
    if (_estrellas > 0 && widget.pedido.id != null) {
      setState(() => _enviando = true);
      try {
        await PedidoService.calificar(widget.pedido.id!, _estrellas, _propina);
      } catch (_) {
        // Si falla la calificación, igual se cierra la pantalla: el pedido ya está entregado.
      }
    }
    navegador.popUntil((ruta) => ruta.isFirst);
  }

  Widget _fila(String etiqueta, String valor, {bool destacada = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            etiqueta,
            style: TextStyle(
              color: destacada ? Paleta.marino : Paleta.gris,
              fontWeight: destacada ? FontWeight.w800 : FontWeight.w500,
              fontSize: destacada ? 16 : 14,
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              color: Paleta.marino,
              fontWeight: FontWeight.w800,
              fontSize: destacada ? 20 : 15,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    final oferta = pedido.oferta!;
    final total = oferta.precio + _propina;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                  child: Column(
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: const BoxDecoration(
                          color: Paleta.verdeClaro,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded, size: 54, color: Paleta.verde),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '¡Entrega completada!',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Paleta.marino,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tu envío se completó con éxito',
                        style: TextStyle(color: Paleta.gris),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Paleta.borde),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ruta realizada',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Paleta.gris,
                              ),
                            ),
                            const SizedBox(height: 10),
                            RutaResumen(
                              origen: pedido.origen.nombre,
                              destino: pedido.destino.nombre,
                            ),
                            const Divider(height: 28, color: Paleta.borde),
                            _fila('Distancia', kilometros(pedido.distanciaKm)),
                            _fila('Paquete', '${pedido.tipoPaquete} · ${pedido.peso}'),
                            _fila('Tarifa acordada', pesos(oferta.precio)),
                            if (_propina > 0) _fila('Propina', pesos(_propina)),
                            const Divider(height: 24, color: Paleta.borde),
                            _fila('Precio final pagado', pesos(total), destacada: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Califica a ${oferta.nombre}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Paleta.marino,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Estrellas(
                        valor: _estrellas,
                        tamano: 42,
                        onChanged: (v) => setState(() => _estrellas = v),
                      ),
                      const SizedBox(height: 28),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Dejar una propina para el repartidor',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Paleta.marino,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (int i = 0; i < _propinas.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: _ChipPropina(
                                texto: pesos(_propinas[i]),
                                seleccionado: _propina == _propinas[i],
                                onTap: () => setState(() {
                                  _propina = _propina == _propinas[i] ? 0 : _propinas[i];
                                }),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: BotonPrincipal(
                  texto: _enviando ? 'Guardando…' : 'Finalizar',
                  onPressed: _enviando ? null : _finalizar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipPropina extends StatelessWidget {
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _ChipPropina({
    required this.texto,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: seleccionado ? Paleta.azul : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: seleccionado ? Paleta.azul : Paleta.borde,
              width: 1.5,
            ),
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: seleccionado ? Colors.white : Paleta.azul,
            ),
          ),
        ),
      ),
    );
  }
}
