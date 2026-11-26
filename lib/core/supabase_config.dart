import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'https://pdegghjzkuybtsylkpjd.supabase.co';
const String supabaseClave = 'sb_publishable_AbBzUIJ0t_bnwOmvHoZk-A_0GH0DZC_'; // anon o sb_publishable_...

/// Atajo para usar el cliente en cualquier archivo.
SupabaseClient get supabase => Supabase.instance.client;
String get miId => supabase.auth.currentUser!.id;