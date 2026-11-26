import 'package:firebase_core/firebase_core.dart';

/// Datos del proyecto de Firebase (solo para las notificaciones push).
/// Se copian del archivo google-services.json que descargas de Firebase:
///   apiKey            -> client[0].api_key[0].current_key
///   appId             -> client[0].client_info.mobilesdk_app_id
///   messagingSenderId -> project_info.project_number
///   projectId         -> project_info.project_id
/// Mientras digan PEGAR_AQUI, la app funciona igual pero sin notificaciones push.
const FirebaseOptions opcionesFirebase = FirebaseOptions(
  apiKey: 'AIzaSyCRp1EW63h5EmU4bQu_N0sKReXaSf1Sbv8',
  appId: '1:316689604727:android:0f973630446efb1075a672',
  messagingSenderId: '316689604727',
  projectId: 'deuna-5d1c6',
);
