enum Modo { cliente, domiciliario, admin }

class Perfil {
  final String id;
  final String nombre;
  final String? telefono;
  final String? fotoUrl;
  final double calificacion;

  const Perfil({
    required this.id,
    required this.nombre,
    this.telefono,
    this.fotoUrl,
    required this.calificacion,
  });

  factory Perfil.desdeMapa(Map<String, dynamic> m) => Perfil(
        id: m['id'] as String,
        nombre: (m['nombre'] as String?) ?? '',
        telefono: m['telefono'] as String?,
        fotoUrl: m['foto_url'] as String?,
        calificacion: (m['calificacion'] as num?)?.toDouble() ?? 5,
      );
}

class InfoDomiciliario {
  final String mensajeriaId;
  final String vehiculo;
  final String placa;
  final String estado; // pendiente | aprobado | bloqueado
  final int saldo;

  const InfoDomiciliario({
    required this.mensajeriaId,
    required this.vehiculo,
    required this.placa,
    required this.estado,
    required this.saldo,
  });

  bool get aprobado => estado == 'aprobado';

  factory InfoDomiciliario.desdeMapa(Map<String, dynamic> m) => InfoDomiciliario(
        mensajeriaId: m['mensajeria_id'] as String,
        vehiculo: m['vehiculo'] as String,
        placa: m['placa'] as String,
        estado: m['estado'] as String,
        saldo: (m['saldo'] as num).toInt(),
      );
}
