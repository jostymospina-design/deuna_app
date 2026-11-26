/// Convierte 8500 en "$8.500".
String pesos(int valor) {
  final texto = valor.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < texto.length; i++) {
    final restantes = texto.length - i;
    buffer.write(texto[i]);
    if (restantes > 1 && restantes % 3 == 1) buffer.write('.');
  }
  return '\$${buffer.toString()}';
}

/// Convierte 11.24 en "11,2 km".
String kilometros(double km) => '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

/// Igual que [pesos] pero acepta negativos: -700 -> "-$700".
String pesosConSigno(int valor) => valor < 0 ? '-${pesos(-valor)}' : pesos(valor);

/// "11/11/2026 14:05" en hora local.
String fechaHora(String iso) {
  final f = DateTime.parse(iso).toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
}

/// "2026-12-01" -> "01/12/2026".
String fechaCorta(String isoFecha) {
  final f = DateTime.parse(isoFecha);
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year}';
}
