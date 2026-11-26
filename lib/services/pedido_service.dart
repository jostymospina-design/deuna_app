import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/supabase_config.dart';
import '../models/modelos.dart';
import 'documentos_service.dart';

/// Toda la comunicación de los pedidos con Supabase.
class PedidoService {
  // ---------------- Cliente ----------------

  /// Crea el pedido y devuelve su id. Los dos códigos los genera la base de datos.
  static Future<String> crear(Pedido p) async {
    final fila = await supabase
        .from('pedidos')
        .insert({
          'cliente_id': miId,
          'origen_nombre': p.origen.nombre,
          'origen_lat': p.origen.posicion.latitude,
          'origen_lng': p.origen.posicion.longitude,
          'destino_nombre': p.destino.nombre,
          'destino_lat': p.destino.posicion.latitude,
          'destino_lng': p.destino.posicion.longitude,
          'tipo_paquete': p.tipoPaquete,
          'peso': p.peso,
          'indicaciones': p.indicaciones,
          'distancia_km': double.parse(p.distanciaKm.toStringAsFixed(2)),
          'tarifa_ofrecida': p.tarifa,
        })
        .select('id')
        .single();
    return fila['id'] as String;
  }

  /// Los dos códigos: (recogida, entrega). Solo el cliente puede leerlos.
  static Future<(String, String)> codigos(String pedidoId) async {
    final f = await supabase
        .from('codigos_pedido')
        .select('codigo, codigo_entrega')
        .eq('pedido_id', pedidoId)
        .single();
    return (f['codigo'] as String, f['codigo_entrega'] as String);
  }

  /// Ofertas en vivo, la más barata primero.
  static Stream<List<Map<String, dynamic>>> ofertas(String pedidoId) => supabase
      .from('ofertas')
      .stream(primaryKey: ['id'])
      .eq('pedido_id', pedidoId)
      .order('precio', ascending: true);

  /// Estado del pedido en vivo (buscando, asignado, recogido, entregado, cancelado).
  static Stream<Map<String, dynamic>> pedido(String pedidoId) => supabase
      .from('pedidos')
      .stream(primaryKey: ['id'])
      .eq('id', pedidoId)
      .where((lista) => lista.isNotEmpty)
      .map((lista) => lista.first);

  /// Nombre, calificación y vehículo de un domiciliario (se pide una vez y queda en caché).
  static final Map<String, Map<String, dynamic>> _domis = {};
  static Future<Map<String, dynamic>> domiciliario(String id) async {
    final guardado = _domis[id];
    if (guardado != null) return guardado;
    final Future<Map<String, dynamic>> fFila = supabase
        .from('domiciliarios')
        .select('vehiculo, placa, lat, lng, perfiles(nombre, calificacion, telefono, foto_url)')
        .eq('id', id)
        .single();
    final Future<bool> fVerificado = DocumentosService.verificado(id).catchError((_) => false);
    final (fila, verificado) = await (fFila, fVerificado).wait;
    return _domis[id] = {...fila, 'verificado': verificado};
  }

  /// Pedido en curso del cliente (buscando, asignado o recogido), o null.
  static Future<Map<String, dynamic>?> activoDelCliente() => supabase
      .from('pedidos')
      .select()
      .eq('cliente_id', miId)
      .inFilter('estado', ['buscando', 'asignado', 'recogido'])
      .order('creado_en', ascending: false)
      .limit(1)
      .maybeSingle();

  /// Los 3 pedidos más recientes del cliente, en vivo (para saber si hay uno en curso).
  static Stream<List<Map<String, dynamic>>> ultimosDelCliente() => supabase
      .from('pedidos')
      .stream(primaryKey: ['id'])
      .eq('cliente_id', miId)
      .order('creado_en', ascending: false)
      .limit(3);

  /// Arma una Oferta con la fila de la oferta y los datos del domiciliario.
  static Oferta ofertaDesde(Map<String, dynamic> o, Map<String, dynamic> d) {
    final perfil = (d['perfiles'] as Map<String, dynamic>?) ?? const {};
    return Oferta(
      id: o['id'] as String,
      domiciliarioId: o['domiciliario_id'] as String,
      nombre: (perfil['nombre'] as String?) ?? 'Domiciliario',
      calificacion: (perfil['calificacion'] as num?)?.toDouble() ?? 5,
      precio: o['precio'] as int,
      vehiculo: '${d['vehiculo']} · ${d['placa']}',
      minutosLlegada: o['minutos_llegada'] as int,
      fotoUrl: perfil['foto_url'] as String?,
      verificado: d['verificado'] == true,
    );
  }

  /// Reconstruye el Pedido de la app a partir de la fila de la BD
  /// (para volver a un pedido después de salir de la pantalla o cerrar la app).
  static Future<Pedido> reconstruir(Map<String, dynamic> f) async {
    final pedido = Pedido(
      origen: Lugar(
        nombre: f['origen_nombre'] as String,
        detalle: 'Recogida',
        posicion: LatLng((f['origen_lat'] as num).toDouble(), (f['origen_lng'] as num).toDouble()),
      ),
      destino: Lugar(
        nombre: f['destino_nombre'] as String,
        detalle: 'Entrega',
        posicion:
            LatLng((f['destino_lat'] as num).toDouble(), (f['destino_lng'] as num).toDouble()),
      ),
    );
    pedido.id = f['id'] as String;
    pedido.tarifa = f['tarifa_ofrecida'] as int;
    pedido.tipoPaquete = (f['tipo_paquete'] as String?) ?? pedido.tipoPaquete;
    pedido.peso = (f['peso'] as String?) ?? '';
    pedido.indicaciones = (f['indicaciones'] as String?) ?? '';
    pedido.distanciaKm = (f['distancia_km'] as num).toDouble();

    final (recogida, entrega) = await codigos(pedido.id!);
    pedido.codigo = recogida;
    pedido.codigoEntrega = entrega;

    final domId = f['domiciliario_id'] as String?;
    if (domId != null) {
      final Future<Map<String, dynamic>?> fOferta = supabase
          .from('ofertas')
          .select()
          .eq('pedido_id', pedido.id!)
          .eq('domiciliario_id', domId)
          .maybeSingle();
      final (o, d) = await (fOferta, domiciliario(domId)).wait;
      if (o != null) pedido.oferta = ofertaDesde(o, d);
    }
    return pedido;
  }

  static Future<void> aceptar(String ofertaId) =>
      supabase.rpc('aceptar_oferta', params: {'p_oferta': ofertaId});

  static Future<void> cancelar(String pedidoId) =>
      supabase.rpc('cancelar_pedido', params: {'p_pedido': pedidoId});

  static Future<void> calificar(String pedidoId, int estrellas, int propina) =>
      supabase.rpc('calificar_pedido', params: {
        'p_pedido': pedidoId,
        'p_estrellas': estrellas,
        'p_propina': propina,
      });

  // ---------------- Domiciliario ----------------

  /// Pedidos que buscan domiciliario a menos de [radioKm] de la posición dada.
  static Future<List<Map<String, dynamic>>> cercanos(double lat, double lng,
      {double radioKm = 5}) async {
    final r = await supabase.rpc('pedidos_cercanos',
        params: {'p_lat': lat, 'p_lng': lng, 'p_radio_km': radioKm});
    return List<Map<String, dynamic>>.from(r as List);
  }

  /// Estado actual de un pedido; null si ya no lo puede ver (lo tomó otro domiciliario).
  static Future<Map<String, dynamic>?> consultar(String pedidoId) => supabase
      .from('pedidos')
      .select()
      .eq('id', pedidoId)
      .maybeSingle();

  static Future<void> ofertar(String pedidoId, int precio, int minutos) =>
      supabase.rpc('ofertar', params: {
        'p_pedido': pedidoId,
        'p_precio': precio,
        'p_minutos': minutos,
      });

  /// true si el código de recogida es correcto.
  static Future<bool> verificarCodigo(String pedidoId, String codigo) async {
    final r = await supabase
        .rpc('verificar_codigo', params: {'p_pedido': pedidoId, 'p_codigo': codigo});
    return r == true;
  }

  /// Domiciliario: envía el código de entrega. Cliente: sin código. true = entregado.
  static Future<bool> finalizar(String pedidoId, {String? codigo}) async {
    final r = await supabase
        .rpc('finalizar_pedido', params: {'p_pedido': pedidoId, 'p_codigo': codigo});
    return r == true;
  }

  /// Nombre y celular del cliente (el domiciliario lo puede ver solo si tiene su pedido).
  static Future<Map<String, dynamic>?> cliente(String clienteId) => supabase
      .from('perfiles')
      .select('nombre, telefono')
      .eq('id', clienteId)
      .maybeSingle();
}
