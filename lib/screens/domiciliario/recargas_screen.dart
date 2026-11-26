import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/formato.dart';
import '../../core/supabase_config.dart';
import '../../core/tema.dart';
import '../../providers/sesion_provider.dart';
import '../../services/auth_service.dart';
import '../../services/saldo_service.dart';

/// Saldo del domiciliario, solicitud de recargas y movimientos (recargas y comisiones).
class RecargasScreen extends StatefulWidget {
  const RecargasScreen({super.key});

  @override
  State<RecargasScreen> createState() => _RecargasScreenState();
}

class _RecargasScreenState extends State<RecargasScreen> {
  late Future<List<Map<String, dynamic>>> _movimientos;
  late Future<List<Map<String, dynamic>>> _solicitudes;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _movimientos = SaldoService.movimientos(miId);
    _solicitudes = SaldoService.misSolicitudes();
  }

  Future<void> _refrescar() async {
    final sesion = context.read<SesionProvider>();
    setState(_cargar);
    await sesion.recargar();
  }

  Future<void> _solicitar(int monto) async {
    try {
      await SaldoService.solicitarRecarga(monto);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Solicitud de ${pesos(monto)} enviada. Paga en tu mensajería '
            'y ellos la confirman.'),
      ));
      setState(_cargar);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
    }
  }

  Future<void> _cancelar(Map<String, dynamic> sol) async {
    try {
      await SaldoService.rechazar(sol['id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Solicitud cancelada.')));
      setState(_cargar);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
    }
  }

  Widget _filaSolicitud(Map<String, dynamic> sol) {
    final vencida = SaldoService.vencida(sol);
    final estado = vencida ? 'vencida' : sol['estado'] as String;
    final (texto, color) = switch (estado) {
      'pendiente' => ('Pendiente · vence en ${SaldoService.minutosRestantes(sol)} min', Paleta.azul),
      'aprobada' => ('Aprobada', Paleta.verde),
      'rechazada' => ('Rechazada / cancelada', Paleta.alerta),
      _ => ('Vencida (nadie la confirmó en 3 horas)', Paleta.gris),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(pesos(sol['monto'] as int), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${fechaHora(sol['creado_en'] as String)}\n$texto',
          style: TextStyle(color: color)),
      isThreeLine: true,
      trailing: estado == 'pendiente'
          ? TextButton(onPressed: () => _cancelar(sol), child: const Text('Cancelar'))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final saldo = context.select<SesionProvider, int>((s) => s.domiciliario?.saldo ?? 0);
    return Scaffold(
      appBar: AppBar(title: const Text('Saldo y recargas')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: saldo < 2000 ? const Color(0xFFFDECEC) : Paleta.verdeClaro,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Text('Tu saldo', style: TextStyle(color: Paleta.gris)),
                  Text(
                    pesosConSigno(saldo),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: saldo < 2000 ? Paleta.alerta : Paleta.verde,
                    ),
                  ),
                  const Text(
                    'De cada pedido entregado se descuenta la comisión de tu mensajería.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Paleta.gris),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Solicitar recarga',
                style: TextStyle(fontWeight: FontWeight.w800, color: Paleta.marino)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final m in const [10000, 20000, 50000])
                  ActionChip(label: Text(pesos(m)), onPressed: () => _solicitar(m)),
              ],
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _solicitudes,
              builder: (_, snap) {
                final lista = snap.data ?? [];
                if (lista.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    const Text('Mis solicitudes',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Paleta.marino)),
                    for (final sol in lista.take(5)) _filaSolicitud(sol),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            const Text('Movimientos',
                style: TextStyle(fontWeight: FontWeight.w800, color: Paleta.marino)),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _movimientos,
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.data!.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aún no tienes movimientos.'),
                  );
                }
                return Column(
                  children: [
                    for (final m in snap.data!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          (m['monto'] as int) >= 0
                              ? Icons.add_circle_rounded
                              : Icons.remove_circle_rounded,
                          color: (m['monto'] as int) >= 0 ? Paleta.verde : Paleta.alerta,
                        ),
                        title: Text(switch (m['tipo']) {
                          'recarga' => 'Recarga',
                          'comision' => 'Comisión de pedido',
                          _ => 'Ajuste',
                        }),
                        subtitle: Text(fechaHora(m['creado_en'] as String)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(pesosConSigno(m['monto'] as int),
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('Saldo ${pesosConSigno(m['saldo_despues'] as int)}',
                                style: const TextStyle(fontSize: 11.5, color: Paleta.gris)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
