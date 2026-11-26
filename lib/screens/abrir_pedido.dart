import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/pedido_service.dart';
import 'buscando_screen.dart';
import 'seguimiento_screen.dart';

/// Abre la pantalla que corresponde a un pedido en curso del cliente:
/// buscando -> radar/ofertas; asignado o recogido -> seguimiento con los códigos.
Future<void> abrirPedidoEnCurso(BuildContext context, Map<String, dynamic> fila) async {
  final navegador = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final pedido = await PedidoService.reconstruir(fila);
    final estado = fila['estado'] as String;
    if (estado == 'buscando') {
      await navegador.push(MaterialPageRoute(builder: (_) => BuscandoScreen(pedido: pedido)));
    } else if (pedido.oferta != null) {
      await navegador.push(MaterialPageRoute(builder: (_) => SeguimientoScreen(pedido: pedido)));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
  }
}
