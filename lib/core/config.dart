/// Interruptor del mapa.
///   false -> OpenStreetMap: no necesita clave ni facturación (úsalo mientras Google no funcione).
///   true  -> Google Maps: necesita la clave en AndroidManifest.xml y facturación activa.
/// Los marcadores, la ruta y las pantallas son los mismos con cualquiera de los dos.
const bool usarGoogleMaps = true;

/// Debe coincidir con el applicationId de android/app/build.gradle.kts.
/// OpenStreetMap lo pide para identificar la aplicación.
const String paqueteApp = 'com.example.deuna_app';
