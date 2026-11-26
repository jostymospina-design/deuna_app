import 'package:flutter/material.dart';

/// Colores de DeUna, tomados del prototipo interactivo:
/// verde para acciones, azul para precios y marino para títulos.
class Paleta {
  static const Color verde = Color(0xFF2E9E57);
  static const Color verdeClaro = Color(0xFFE4F4EA);
  static const Color marino = Color(0xFF1B2340);
  static const Color azul = Color(0xFF2F6BFF);
  static const Color azulClaro = Color(0xFFEAF1FF);
  static const Color fondo = Color(0xFFF5F6FA);
  static const Color gris = Color(0xFF7A8197);
  static const Color borde = Color(0xFFE3E6EF);
  static const Color alerta = Color(0xFFE5484D);
  static const Color estrella = Color(0xFFFFB400);
}

ThemeData construirTema() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Paleta.verde,
    primary: Paleta.verde,
    surface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Paleta.fondo,
    appBarTheme: const AppBarTheme(
      backgroundColor: Paleta.fondo,
      foregroundColor: Paleta.marino,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Paleta.marino,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Paleta.marino,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
