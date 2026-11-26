import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/tema.dart';

/// Botón verde grande, igual al de las pantallas del prototipo.
class BotonPrincipal extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final IconData? icono;

  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.onPressed,
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Paleta.verde,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Paleta.borde,
          disabledForegroundColor: Paleta.gris,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 20),
              const SizedBox(width: 8),
            ],
            Text(texto),
          ],
        ),
      ),
    );
  }
}

/// Botón con borde para acciones secundarias (cancelar, rechazar).
class BotonSecundario extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final Color color;

  const BotonSecundario({
    super.key,
    required this.texto,
    required this.onPressed,
    this.color = Paleta.marino,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: Paleta.borde, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: Text(texto),
      ),
    );
  }
}

/// Panel blanco que sube desde abajo sobre el mapa.
class PanelInferior extends StatelessWidget {
  final Widget child;

  const PanelInferior({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x261B2340),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Paleta.borde,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Botón circular blanco que flota sobre el mapa.
class BotonRedondo extends StatelessWidget {
  final IconData icono;
  final VoidCallback onPressed;

  const BotonRedondo({super.key, required this.icono, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: const Color(0x331B2340),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icono, color: Paleta.marino),
        ),
      ),
    );
  }
}

/// Círculo con las iniciales del nombre (reemplaza las fotos del prototipo).
class AvatarIniciales extends StatelessWidget {
  final String nombre;
  final double radio;

  const AvatarIniciales({super.key, required this.nombre, this.radio = 24});

  @override
  Widget build(BuildContext context) {
    final iniciales = nombre
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radio,
      backgroundColor: Paleta.verdeClaro,
      child: Text(
        iniciales,
        style: TextStyle(
          color: Paleta.verde,
          fontWeight: FontWeight.w800,
          fontSize: radio * 0.72,
        ),
      ),
    );
  }
}

/// Cinco estrellas. Si se pasa [onChanged], se pueden tocar para calificar.
class Estrellas extends StatelessWidget {
  final int valor;
  final double tamano;
  final ValueChanged<int>? onChanged;

  const Estrellas({
    super.key,
    required this.valor,
    this.tamano = 24,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(
              i < valor ? Icons.star_rounded : Icons.star_outline_rounded,
              color: Paleta.estrella,
              size: tamano,
            ),
          ),
        );
      }),
    );
  }
}

/// Recogida y entrega en dos líneas unidas por un conector.
class RutaResumen extends StatelessWidget {
  final String origen;
  final String destino;

  const RutaResumen({super.key, required this.origen, required this.destino});

  @override
  Widget build(BuildContext context) {
    const estiloTexto = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Paleta.marino,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 20,
              child: Center(
                child: CircleAvatar(radius: 5, backgroundColor: Paleta.verde),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(origen, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloTexto),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 9),
          child: Container(width: 2, height: 16, color: Paleta.borde),
        ),
        Row(
          children: [
            const SizedBox(
              width: 20,
              child: Icon(Icons.location_on_rounded, size: 20, color: Paleta.azul),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(destino, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloTexto),
            ),
          ],
        ),
      ],
    );
  }
}

/// Foto de perfil (se guarda en el celular después de verla una vez: no gasta datos de nuevo).
/// Si no hay foto, muestra las iniciales.
class FotoPerfil extends StatelessWidget {
  final String? url;
  final String nombre;
  final double radio;
  final bool verificado;

  const FotoPerfil({
    super.key,
    required this.url,
    required this.nombre,
    this.radio = 24,
    this.verificado = false,
  });

  @override
  Widget build(BuildContext context) {
    final foto = (url == null || url!.isEmpty)
        ? AvatarIniciales(nombre: nombre.isEmpty ? '?' : nombre, radio: radio)
        : ClipOval(
            child: CachedNetworkImage(
              imageUrl: url!,
              width: radio * 2,
              height: radio * 2,
              fit: BoxFit.cover,
              memCacheWidth: (radio * 4).round(),
              placeholder: (_, __) =>
                  AvatarIniciales(nombre: nombre.isEmpty ? '?' : nombre, radio: radio),
              errorWidget: (_, __, ___) =>
                  AvatarIniciales(nombre: nombre.isEmpty ? '?' : nombre, radio: radio),
            ),
          );
    if (!verificado) return foto;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        foto,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(Icons.verified_rounded, color: Paleta.azul, size: radio * 0.7),
          ),
        ),
      ],
    );
  }
}

/// Etiqueta "Documentos verificados".
class EtiquetaVerificado extends StatelessWidget {
  const EtiquetaVerificado({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Paleta.azulClaro,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 14, color: Paleta.azul),
          SizedBox(width: 4),
          Text(
            'Documentos verificados',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Paleta.azul),
          ),
        ],
      ),
    );
  }
}
