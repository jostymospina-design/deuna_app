import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/formato.dart';
import '../core/supabase_config.dart';
import '../core/tema.dart';
import '../models/perfil.dart';
import '../providers/sesion_provider.dart';
import '../services/pedido_service.dart';
import 'abrir_pedido.dart';

/// Historial: como cliente, los pedidos que hizo; como domiciliario, los que entregó.
/// Carga de a 20 y pide más al llegar al final de la lista.
class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  static const int _pagina = 20;
  final List<Map<String, dynamic>> _pedidos = [];
  final ScrollController _scroll = ScrollController();
  bool _cargando = false;
  bool _hayMas = true;
  String? _error;
  late final bool _comoDomi;

  @override
  void initState() {
    super.initState();
    _comoDomi = context.read<SesionProvider>().modo == Modo.domiciliario;
    _cargarMas();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _cargarMas();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargarMas() async {
    if (_cargando || !_hayMas) return;
    _cargando = true;
    final desde = _pedidos.length;
    try {
      final filas = await supabase
          .from('pedidos')
          .select('id, origen_nombre, destino_nombre, estado, precio_final, '
              'tarifa_ofrecida, comision, propina, calificacion, creado_en')
          .eq(_comoDomi ? 'domiciliario_id' : 'cliente_id', miId)
          .order('creado_en', ascending: false)
          .range(desde, desde + _pagina - 1);
      if (!mounted) return;
      setState(() {
        _pedidos.addAll(filas);
        _hayMas = filas.length == _pagina;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo cargar el historial.';
          _hayMas = false;
        });
      }
    }
    _cargando = false;
  }

  Future<void> _refrescar() async {
    setState(() {
      _pedidos.clear();
      _hayMas = true;
    });
    await _cargarMas();
  }

  Future<void> _abrir(String pedidoId) async {
    final fila = await PedidoService.consultar(pedidoId);
    if (fila == null || !mounted) return;
    await abrirPedidoEnCurso(context, fila);
    if (mounted) _refrescar();
  }

  Color _color(String estado) => switch (estado) {
        'entregado' => Paleta.verde,
        'cancelado' => Paleta.alerta,
        _ => Paleta.azul,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_comoDomi ? 'Mis entregas' : 'Mis pedidos')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: _pedidos.isEmpty && !_hayMas
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.receipt_long_rounded, size: 56, color: Paleta.gris.withValues(alpha: 0.6)),
                  const SizedBox(height: 12),
                  Center(child: Text(_error ?? 'Aún no tienes pedidos')),
                ],
              )
            : ListView.separated(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _pedidos.length + (_hayMas ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  if (i == _pedidos.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final p = _pedidos[i];
                  final valor = (p['precio_final'] ?? p['tarifa_ofrecida']) as int;
                  final comision = p['comision'] as int?;
                  final estado = p['estado'] as String;
                  final enCurso = const ['buscando', 'asignado', 'recogido'].contains(estado);
                  return ListTile(
                    // Un pedido en curso del cliente se puede abrir desde aquí.
                    onTap: !_comoDomi && enCurso ? () => _abrir(p['id'] as String) : null,
                    title: Text(
                      '${p['origen_nombre']} → ${p['destino_nombre']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      fechaHora(p['creado_en'] as String) +
                          (_comoDomi && comision != null ? ' · comisión ${pesos(comision)}' : '') +
                          (p['calificacion'] != null ? ' · ★ ${p['calificacion']}' : ''),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(pesos(valor), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(estado, style: TextStyle(color: _color(estado), fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
