import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/formato.dart';
import '../core/tema.dart';
import '../models/modelos.dart';
import '../widgets/componentes.dart';
import 'tarifa_screen.dart';

class _TipoPaquete {
  final String nombre;
  final String ejemplo;
  final IconData icono;

  const _TipoPaquete(this.nombre, this.ejemplo, this.icono);
}

/// Pantalla 2: Detalles del paquete.
class DetallesPaqueteScreen extends StatefulWidget {
  final Pedido pedido;

  const DetallesPaqueteScreen({super.key, required this.pedido});

  @override
  State<DetallesPaqueteScreen> createState() => _DetallesPaqueteScreenState();
}

class _DetallesPaqueteScreenState extends State<DetallesPaqueteScreen> {
  static const List<_TipoPaquete> _tipos = [
    _TipoPaquete('Sobre', 'Documentos, cartas', Icons.mail_outline_rounded),
    _TipoPaquete('Caja pequeña', 'Zapatos, libros', Icons.inventory_2_outlined),
    _TipoPaquete('Caja mediana', 'Ropa, electrodomésticos pequeños', Icons.all_inbox_outlined),
    _TipoPaquete('Bolsa', 'Mercado, comida', Icons.shopping_bag_outlined),
  ];

  String _tipo = 'Caja pequeña';
  final TextEditingController _peso = TextEditingController();
  final TextEditingController _notas = TextEditingController();
  String? _errorPeso;

  @override
  void dispose() {
    _peso.dispose();
    _notas.dispose();
    super.dispose();
  }

  void _siguiente() {
    final kg = double.tryParse(_peso.text.trim().replaceAll(',', '.'));
    if (kg == null || kg <= 0) {
      setState(() => _errorPeso = 'Escribe el peso en kilos, por ejemplo 2.');
      return;
    }
    if (kg > 30) {
      setState(() => _errorPeso = 'El peso máximo para una moto es 30 kg.');
      return;
    }

    widget.pedido.tipoPaquete = _tipo;
    widget.pedido.peso = '${kg.toStringAsFixed(kg % 1 == 0 ? 0 : 1)} kg';
    widget.pedido.indicaciones = _notas.text.trim();

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TarifaScreen(pedido: widget.pedido)),
    );
  }

  InputDecoration _decoracion({String? ayuda, IconData? icono, String? sufijo, String? error}) {
    OutlineInputBorder borde(Color color, [double ancho = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: ancho),
        );
    return InputDecoration(
      hintText: ayuda,
      hintStyle: const TextStyle(color: Paleta.gris),
      prefixIcon: icono == null ? null : Icon(icono, color: Paleta.gris),
      suffixText: sufijo,
      errorText: error,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: borde(Paleta.borde),
      enabledBorder: borde(Paleta.borde),
      focusedBorder: borde(Paleta.verde, 2),
      errorBorder: borde(Paleta.alerta),
      focusedErrorBorder: borde(Paleta.alerta, 2),
    );
  }

  Widget _titulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Paleta.marino,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    return Scaffold(
      appBar: AppBar(title: const Text('Detalles del paquete')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Paleta.borde),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: RutaResumen(
                            origen: pedido.origen.nombre,
                            destino: pedido.destino.nombre,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          kilometros(pedido.distanciaKm),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Paleta.azul,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _titulo('Tipo de paquete'),
                  for (final tipo in _tipos) ...[
                    _TarjetaTipo(
                      tipo: tipo,
                      seleccionado: tipo.nombre == _tipo,
                      onTap: () => setState(() => _tipo = tipo.nombre),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _titulo('Peso aproximado'),
                  TextField(
                    controller: _peso,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (_) {
                      if (_errorPeso != null) setState(() => _errorPeso = null);
                    },
                    decoration: _decoracion(
                      ayuda: 'Ej: 2',
                      icono: Icons.scale_outlined,
                      sufijo: 'kg',
                      error: _errorPeso,
                    ),
                  ),
                  _titulo('Indicaciones especiales'),
                  TextField(
                    controller: _notas,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _decoracion(
                      ayuda: 'Ej: Llamar al llegar, el timbre no funciona. Entregar en portería.',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: BotonPrincipal(texto: 'Siguiente', onPressed: _siguiente),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaTipo extends StatelessWidget {
  final _TipoPaquete tipo;
  final bool seleccionado;
  final VoidCallback onTap;

  const _TarjetaTipo({
    required this.tipo,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: seleccionado ? Paleta.verdeClaro : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: seleccionado ? Paleta.verde : Paleta.borde,
              width: seleccionado ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(tipo.icono, color: seleccionado ? Paleta.verde : Paleta.marino),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tipo.nombre,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Paleta.marino,
                      ),
                    ),
                    Text(
                      'Ej: ${tipo.ejemplo}',
                      style: const TextStyle(fontSize: 12.5, color: Paleta.gris),
                    ),
                  ],
                ),
              ),
              if (seleccionado)
                const Icon(Icons.check_circle_rounded, color: Paleta.verde),
            ],
          ),
        ),
      ),
    );
  }
}
