import '../core/supabase_config.dart';

/// Recargas, comisiones y gestión de domiciliarios (panel de la mensajería).
class SaldoService {
  /// Últimos 30 movimientos (recargas y comisiones) de un domiciliario.
  static Future<List<Map<String, dynamic>>> movimientos(String domId) => supabase
      .from('movimientos_saldo')
      .select('tipo, monto, saldo_despues, creado_en')
      .eq('domiciliario_id', domId)
      .order('creado_en', ascending: false)
      .limit(30);

  /// Las solicitudes pendientes vencen a las 3 horas si nadie las confirma.
  static const Duration vigencia = Duration(hours: 3);

  /// true si una solicitud 'pendiente' ya pasó las 3 horas (aunque la BD no la haya marcado).
  static bool vencida(Map<String, dynamic> s) =>
      s['estado'] == 'pendiente' &&
      DateTime.now().difference(DateTime.parse(s['creado_en'] as String)) > vigencia;

  /// Minutos que le quedan a una solicitud pendiente.
  static int minutosRestantes(Map<String, dynamic> s) {
    final vence = DateTime.parse(s['creado_en'] as String).add(vigencia);
    return vence.difference(DateTime.now()).inMinutes.clamp(0, 180).toInt();
  }

  /// Solo se permite una pendiente a la vez (lo controla la BD).
  static Future<void> solicitarRecarga(int monto) =>
      supabase.rpc('solicitar_recarga', params: {'p_monto': monto});

  /// Admin: "no recibí el pago". Domiciliario: cancelar su propia solicitud.
  static Future<void> rechazar(String solicitudId) =>
      supabase.rpc('rechazar_solicitud', params: {'p_solicitud': solicitudId});

  static Future<List<Map<String, dynamic>>> misSolicitudes() => supabase
      .from('solicitudes_recarga')
      .select('id, monto, estado, creado_en')
      .eq('domiciliario_id', miId)
      .order('creado_en', ascending: false)
      .limit(10);

  // ---------------- Admin ----------------

  static Future<List<Map<String, dynamic>>> misDomiciliarios(String mensajeriaId) => supabase
      .from('domiciliarios')
      .select('id, vehiculo, placa, estado, saldo, disponible, perfiles(nombre, telefono, foto_url)')
      .eq('mensajeria_id', mensajeriaId)
      .order('estado');

  /// Solicitudes pendientes de los domiciliarios de mi mensajería (lo filtra la RLS).
  static Future<List<Map<String, dynamic>>> solicitudesPendientes() => supabase
      .from('solicitudes_recarga')
      .select('id, monto, creado_en, domiciliario_id, domiciliarios(perfiles(nombre))')
      .eq('estado', 'pendiente')
      .gte('creado_en', DateTime.now().toUtc().subtract(vigencia).toIso8601String())
      .order('creado_en');

  /// Comisiones cobradas a los domiciliarios de mi mensajería (últimas 50).
  static Future<List<Map<String, dynamic>>> comisiones() => supabase
      .from('movimientos_saldo')
      .select('monto, creado_en, domiciliarios(perfiles(nombre))')
      .eq('tipo', 'comision')
      .order('creado_en', ascending: false)
      .limit(50);

  static Future<void> cambiarEstado(String domId, String estado) => supabase
      .rpc('cambiar_estado_domiciliario', params: {'p_dom': domId, 'p_estado': estado});

  static Future<void> recargar(String domId, int monto, {String? solicitudId}) =>
      supabase.rpc('registrar_recarga', params: {
        'p_dom': domId,
        'p_monto': monto,
        'p_solicitud': solicitudId,
      });
}
