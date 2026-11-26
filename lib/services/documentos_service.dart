import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

/// Un tipo de documento del domiciliario.
class TipoDocumento {
  final String id;
  final String nombre;
  final String ayuda;
  final bool obligatorio;
  final bool vence;

  const TipoDocumento(this.id, this.nombre, this.ayuda,
      {this.obligatorio = true, this.vence = false});
}

const List<TipoDocumento> tiposDocumento = [
  TipoDocumento('selfie', 'Foto tuya', 'De frente, con buena luz. La verán tus clientes.'),
  TipoDocumento('cedula_frente', 'Cédula (frente)', 'Que se lean el nombre y el número.'),
  TipoDocumento('cedula_respaldo', 'Cédula (respaldo)', 'Completa, sin reflejos.'),
  TipoDocumento('licencia', 'Licencia de conducción', 'La categoría debe cubrir tu vehículo.',
      vence: true),
  TipoDocumento('soat', 'SOAT', 'Vigente y de la misma placa registrada.', vence: true),
  TipoDocumento('tarjeta_propiedad', 'Tarjeta de propiedad', 'De la placa que registraste.'),
  TipoDocumento('tecnomecanica', 'Revisión técnico-mecánica',
      'Solo si tu vehículo ya debe tenerla.', obligatorio: false, vence: true),
];

/// Subida y revisión de documentos. Las fotos se reducen en el celular antes de subirlas.
class DocumentosService {
  static const String _bucketDocs = 'documentos';
  static const String _bucketFotos = 'fotos_perfil';
  static final ImagePicker _picker = ImagePicker();

  /// Abre la cámara o la galería. La foto sale reducida (unos 200–300 KB; la selfie ~50 KB).
  static Future<XFile?> elegirFoto({required bool camara, required bool selfie}) {
    return _picker.pickImage(
      source: camara ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
      maxWidth: selfie ? 512 : 1280,
      maxHeight: selfie ? 512 : 1280,
      imageQuality: 70,
    );
  }

  static String _tipoMime(String ruta) {
    final r = ruta.toLowerCase();
    if (r.endsWith('.png')) return 'image/png';
    if (r.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Sube (o reemplaza) un documento y lo deja pendiente de revisión.
  static Future<void> subir(TipoDocumento tipo, XFile foto, {DateTime? venceEn}) async {
    final bytes = await foto.readAsBytes();
    final opciones = FileOptions(upsert: true, contentType: _tipoMime(foto.path));
    String ruta;
    if (tipo.id == 'selfie') {
      ruta = '$miId.jpg';
      await supabase.storage.from(_bucketFotos).uploadBinary(ruta, bytes, fileOptions: opciones);
      // ?v= cambia la dirección para que los celulares no muestren la foto vieja guardada.
      final url = '${supabase.storage.from(_bucketFotos).getPublicUrl(ruta)}'
          '?v=${DateTime.now().millisecondsSinceEpoch}';
      await supabase.from('perfiles').update({'foto_url': url}).eq('id', miId);
    } else {
      ruta = '$miId/${tipo.id}.jpg'; // siempre la misma ruta: al renovar se reemplaza
      await supabase.storage.from(_bucketDocs).uploadBinary(ruta, bytes, fileOptions: opciones);
    }
    await supabase.rpc('guardar_documento', params: {
      'p_tipo': tipo.id,
      'p_ruta': ruta,
      'p_vence': venceEn?.toIso8601String().substring(0, 10),
    });
  }

  /// Documentos de un domiciliario, por tipo (los propios, o los de la mensajería si eres admin).
  static Future<Map<String, Map<String, dynamic>>> de(String domId) async {
    final filas = await supabase
        .from('documentos_domiciliario')
        .select('tipo, ruta, vence_en, estado, motivo, subido_en')
        .eq('domiciliario_id', domId);
    return {for (final f in filas) f['tipo'] as String: f};
  }

  /// Dirección temporal (10 min) para ver la foto de un documento privado.
  static Future<String> urlParaVer(Map<String, dynamic> doc) async {
    final ruta = doc['ruta'] as String;
    if (doc['tipo'] == 'selfie') {
      return supabase.storage.from(_bucketFotos).getPublicUrl(ruta);
    }
    return supabase.storage.from(_bucketDocs).createSignedUrl(ruta, 600);
  }

  static Future<bool> autorizacionAceptada() async {
    final f = await supabase
        .from('domiciliarios')
        .select('autorizacion_datos_en')
        .eq('id', miId)
        .maybeSingle();
    return f?['autorizacion_datos_en'] != null;
  }

  static Future<void> aceptarAutorizacion() => supabase.rpc('aceptar_autorizacion_datos');

  // ---------------- Admin ----------------

  static Future<void> revisar(String domId, String tipo, {required bool aprobar, String? motivo}) =>
      supabase.rpc('revisar_documento', params: {
        'p_dom': domId,
        'p_tipo': tipo,
        'p_aprobar': aprobar,
        'p_motivo': motivo,
      });

  // ---------------- Cliente ----------------

  /// true si el domiciliario tiene todos sus documentos aprobados y vigentes.
  static Future<bool> verificado(String domId) async {
    final r = await supabase.rpc('domiciliario_verificado', params: {'p_dom': domId});
    return r == true;
  }
}

/// Estado legible de un documento, considerando el vencimiento.
String estadoDocumento(Map<String, dynamic>? doc) {
  if (doc == null) return 'falta';
  final vence = doc['vence_en'] as String?;
  if (vence != null && DateTime.parse(vence).isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
    return 'vencido';
  }
  return doc['estado'] as String; // pendiente | aprobado | rechazado
}
