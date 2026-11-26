import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/formato.dart';
import '../../core/tema.dart';
import '../../providers/sesion_provider.dart';
import '../../services/auth_service.dart';
import '../../services/saldo_service.dart';
import '../../widgets/componentes.dart';
import '../../widgets/menu_deuna.dart';
import 'revisar_documentos_screen.dart';

/// Panel de la mensajería: aprobar domiciliarios, registrar recargas y ver comisiones.
class PanelAdminScreen extends StatefulWidget {
  const PanelAdminScreen({super.key});

  @override
  State<PanelAdminScreen> createState() => _PanelAdminScreenState();
}

class _PanelAdminScreenState extends State<PanelAdminScreen> {
  late final String _mensajeriaId;
  late Future<List<Map<String, dynamic>>> _domis;
  late Future<List<Map<String, dynamic>>> _solicitudes;
  late Future<List<Map<String, dynamic>>> _comisiones;

  @override
  void initState() {
    super.initState();
    _mensajeriaId = context.read<SesionProvider>().mensajeria!['id'] as String;
    _cargar();
  }

  void _cargar() {
    _domis = SaldoService.misDomiciliarios(_mensajeriaId);
    _solicitudes = SaldoService.solicitudesPendientes();
    _comisiones = SaldoService.comisiones();
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await Future.wait([_domis, _solicitudes, _comisiones]);
  }

  Future<void> _accion(Future<void> Function() f, String exito) async {
    try {
      await f();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exito)));
      _refrescar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AuthService.mensajeError(e))));
      }
    }
  }

  Future<void> _recargaManual(String domId, String nombre) async {
    final ctrl = TextEditingController(text: '20000');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Recarga para $nombre'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Valor recibido (efectivo o Nequi)',
            prefixText: '\$ ',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Registrar')),
        ],
      ),
    );
    final monto = int.tryParse(ctrl.text) ?? 0;
    if (ok != true) return;
    _accion(() => SaldoService.recargar(domId, monto), 'Recarga de ${pesos(monto)} registrada');
  }

  Future<void> _rechazar(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Rechazar la solicitud?'),
        content: Text(
          '${_nombreDe(s)} pidió ${pesos(s['monto'] as int)}. Recházala solo si no '
          'recibiste el pago. No se suma nada a su saldo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Paleta.alerta),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _accion(() => SaldoService.rechazar(s['id'] as String), 'Solicitud rechazada');
  }

  Widget _vacio(String texto) => ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: Paleta.gris)),
          ),
        ],
      );

  Widget _lista(Future<List<Map<String, dynamic>>> futuro, String vacio,
      Widget Function(Map<String, dynamic>) fila) {
    return RefreshIndicator(
      onRefresh: _refrescar,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: futuro,
        builder: (_, snap) {
          if (snap.hasError) return _vacio('No se pudo cargar. Desliza para reintentar.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.isEmpty) return _vacio(vacio);
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: snap.data!.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => fila(snap.data![i]),
          );
        },
      ),
    );
  }

  String _nombreDe(Map<String, dynamic> fila) {
    final dom = fila['domiciliarios'] as Map<String, dynamic>?;
    final perfil = dom?['perfiles'] as Map<String, dynamic>?;
    return (perfil?['nombre'] as String?) ?? 'Domiciliario';
  }

  Future<void> _revisarDocumentos(String domId, String nombre, String estado) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RevisarDocumentosScreen(domiciliarioId: domId, nombre: nombre, estado: estado),
      ),
    );
    if (mounted) _refrescar();
  }

  Future<void> _opcionesDomiciliario(String domId, String nombre, String estado) async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w800))),
            ListTile(
              leading: const Icon(Icons.badge_rounded),
              title: const Text('Ver documentos'),
              onTap: () => Navigator.pop(c, 'docs'),
            ),
            if (estado == 'aprobado')
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_rounded),
                title: const Text('Registrar recarga'),
                onTap: () => Navigator.pop(c, 'recarga'),
              ),
            if (estado == 'aprobado')
              ListTile(
                leading: const Icon(Icons.block_rounded, color: Paleta.alerta),
                title: const Text('Bloquear'),
                onTap: () => Navigator.pop(c, 'bloquear'),
              ),
            if (estado == 'bloqueado')
              ListTile(
                leading: const Icon(Icons.lock_open_rounded),
                title: const Text('Desbloquear'),
                onTap: () => Navigator.pop(c, 'desbloquear'),
              ),
          ],
        ),
      ),
    );
    switch (opcion) {
      case 'docs':
        _revisarDocumentos(domId, nombre, estado);
      case 'recarga':
        _recargaManual(domId, nombre);
      case 'bloquear':
        _accion(() => SaldoService.cambiarEstado(domId, 'bloqueado'), '$nombre fue bloqueado');
      case 'desbloquear':
        _accion(() => SaldoService.cambiarEstado(domId, 'aprobado'), '$nombre fue desbloqueado');
    }
  }

  Widget _filaDomiciliario(Map<String, dynamic> d) {
    final perfil = d['perfiles'] as Map<String, dynamic>?;
    final nombre = (perfil?['nombre'] as String?) ?? 'Sin nombre';
    final estado = d['estado'] as String;
    final saldo = d['saldo'] as int;
    final id = d['id'] as String;
    return ListTile(
      leading: FotoPerfil(url: perfil?['foto_url'] as String?, nombre: nombre, radio: 20),
      title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${d['vehiculo']} · ${d['placa']}\n'
        '${estado == 'aprobado' ? (d['disponible'] == true ? 'Disponible' : 'Desconectado') : estado}'
        '${perfil?['telefono'] != null ? ' · ${perfil!['telefono']}' : ''}',
      ),
      isThreeLine: true,
      trailing: estado == 'pendiente'
          ? FilledButton(
              onPressed: () => _revisarDocumentos(id, nombre, estado),
              child: const Text('Revisar'),
            )
          : estado == 'bloqueado'
              ? const Text('Bloqueado', style: TextStyle(color: Paleta.alerta))
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pesosConSigno(saldo),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: saldo < 2000 ? Paleta.alerta : Paleta.marino,
                      ),
                    ),
                    const Text('Toca para opciones',
                        style: TextStyle(fontSize: 11, color: Paleta.gris)),
                  ],
                ),
      onTap: estado == 'pendiente'
          ? () => _revisarDocumentos(id, nombre, estado)
          : () => _opcionesDomiciliario(id, nombre, estado),
    );
  }


  @override
  Widget build(BuildContext context) {
    final mensajeria = context.select<SesionProvider, Map<String, dynamic>?>((s) => s.mensajeria);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        drawer: const MenuDeUna(),
        appBar: AppBar(
          title: Text((mensajeria?['nombre'] as String?) ?? 'Mi mensajería'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Domiciliarios'),
              Tab(text: 'Recargas'),
              Tab(text: 'Comisiones'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _lista(_domis, 'Aún no tienes domiciliarios.\nDiles que se registren desde el menú.',
                _filaDomiciliario),
            _lista(
              _solicitudes,
              'Sin solicitudes de recarga pendientes.\nLas que nadie confirma vencen a las 3 horas.',
              (s) => ListTile(
                leading: const Icon(Icons.account_balance_wallet_rounded, color: Paleta.verde),
                title: Text('${_nombreDe(s)} pide ${pesos(s['monto'] as int)}'),
                subtitle: Text(
                  '${fechaHora(s['creado_en'] as String)} · '
                  'vence en ${SaldoService.minutosRestantes(s)} min',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'No recibí el pago',
                      icon: const Icon(Icons.close_rounded, color: Paleta.alerta),
                      onPressed: () => _rechazar(s),
                    ),
                    FilledButton(
                      onPressed: () => _accion(
                        () => SaldoService.recargar(
                          s['domiciliario_id'] as String,
                          s['monto'] as int,
                          solicitudId: s['id'] as String,
                        ),
                        'Recarga confirmada',
                      ),
                      child: const Text('Recibí el pago'),
                    ),
                  ],
                ),
              ),
            ),
            _lista(
              _comisiones,
              'Aún no hay comisiones cobradas',
              (c) => ListTile(
                leading: const Icon(Icons.trending_up_rounded, color: Paleta.verde),
                title: Text(_nombreDe(c)),
                subtitle: Text(fechaHora(c['creado_en'] as String)),
                trailing: Text(
                  pesos(-(c['monto'] as int)),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Paleta.verde),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
