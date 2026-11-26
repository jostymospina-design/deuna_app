// Edge Function "notificar" de DeUna.
// La llaman los triggers de la base de datos (función enviar_push) con:
//   { tokens: string[], titulo: string, cuerpo: string, datos: { ... } }
// y envía una notificación push a cada celular con Firebase Cloud Messaging (API HTTP v1).
//
// Secretos que necesita (Supabase > Edge Functions > Secrets):
//   FIREBASE_SERVICE_ACCOUNT  = el JSON completo de la cuenta de servicio de Firebase
//   PUSH_SECRETO              = el mismo valor que está en cambio_notificaciones.sql
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY ya existen solos en todas las Edge Functions.
// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';
import { JWT } from 'npm:google-auth-library@9';

const cuenta = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}');
const secreto = Deno.env.get('PUSH_SECRETO') ?? '';
const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// El token de acceso de Google dura 1 hora: se reutiliza entre llamadas.
let accesoGuardado: { valor: string; vence: number } | null = null;

async function tokenDeAcceso(): Promise<string> {
  if (accesoGuardado && Date.now() < accesoGuardado.vence) return accesoGuardado.valor;
  const jwt = new JWT({
    email: cuenta.client_email,
    key: cuenta.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const credenciales = await jwt.authorize();
  accesoGuardado = { valor: credenciales.access_token!, vence: Date.now() + 50 * 60 * 1000 };
  return accesoGuardado.valor;
}

Deno.serve(async (req) => {
  if (!secreto || req.headers.get('x-push-secreto') !== secreto) {
    return new Response('No autorizado', { status: 401 });
  }

  const { tokens, titulo, cuerpo, datos } = await req.json();
  if (!Array.isArray(tokens) || tokens.length === 0) {
    return Response.json({ enviados: 0 });
  }

  // FCM solo acepta textos en "data"
  const datosTexto: Record<string, string> = {};
  for (const [clave, valor] of Object.entries(datos ?? {})) datosTexto[clave] = String(valor);

  const acceso = await tokenDeAcceso();
  const invalidos: string[] = [];
  let enviados = 0;

  await Promise.all(
    tokens.map(async (token: string) => {
      const respuesta = await fetch(
        `https://fcm.googleapis.com/v1/projects/${cuenta.project_id}/messages:send`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${acceso}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: titulo, body: cuerpo },
              data: datosTexto,
              android: { priority: 'high', notification: { sound: 'default' } },
            },
          }),
        },
      );
      if (respuesta.ok) {
        enviados++;
        return;
      }
      const error = await respuesta.text();
      console.error('FCM', respuesta.status, error);
      // El celular desinstaló la app o el token cambió: se borra para no volver a intentarlo.
      if (respuesta.status === 404 || error.includes('UNREGISTERED')) invalidos.push(token);
    }),
  );

  if (invalidos.length > 0) {
    await supabase.from('dispositivos').delete().in('token', invalidos);
  }
  return Response.json({ enviados, invalidos: invalidos.length });
});
