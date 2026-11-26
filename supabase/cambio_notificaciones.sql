-- =========================================================
-- DeUna - CAMBIO: notificaciones push (Firebase Cloud Messaging)
-- Ejecutar UNA vez en Supabase > SQL Editor, DESPUÉS de crear la Edge Function "notificar".
-- El secreto del paso 2 debe ser EXACTAMENTE el mismo del secreto PUSH_SECRETO de la Edge Function.
-- =========================================================

create extension if not exists pg_net;

-- 1. Celulares registrados (un usuario puede tener varios; un celular, una cuenta a la vez)
create table if not exists public.dispositivos (
  token          text primary key,
  usuario_id     uuid not null references public.perfiles(id) on delete cascade,
  actualizado_en timestamptz not null default now()
);
create index if not exists dispositivos_usuario on public.dispositivos (usuario_id);
alter table public.dispositivos enable row level security;
-- Sin políticas: la app solo los toca con las dos funciones de abajo.
revoke all on public.dispositivos from anon, authenticated;

create or replace function public.registrar_dispositivo(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  insert into dispositivos (token, usuario_id, actualizado_en)
  values (p_token, auth.uid(), now())
  on conflict (token) do update set usuario_id = auth.uid(), actualizado_en = now();
end $$;

create or replace function public.olvidar_dispositivo(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from dispositivos where token = p_token and usuario_id = auth.uid();
$$;

-- 2. Dirección de la Edge Function y secreto compartido (guardados en Vault, cifrados)
do $$
begin
  delete from vault.secrets where name in ('push_url', 'push_secreto');
  perform vault.create_secret('https://pdegghjzkuybtsylkpjd.supabase.co/functions/v1/notificar', 'push_url');
  perform vault.create_secret('3b42e09e0de20773ee8abcddc051235d5232b18d183ae4a4', 'push_secreto');
end $$;

-- Formato de pesos para los textos: 6000 -> 6.000
create or replace function public.pesos_txt(v integer) returns text
language sql immutable as $$ select replace(to_char(v, 'FM999,999,999'), ',', '.') $$;

-- 3. Envía una notificación a una lista de usuarios (no bloquea: pg_net la manda en segundo plano)
create or replace function public.enviar_push(p_usuarios uuid[], p_titulo text, p_cuerpo text,
                                              p_datos jsonb default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare v_tokens text[]; v_url text; v_secreto text;
begin
  select array_agg(token) into v_tokens from dispositivos where usuario_id = any(p_usuarios);
  if v_tokens is null then return; end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'push_url';
  select decrypted_secret into v_secreto from vault.decrypted_secrets where name = 'push_secreto';
  if v_url is null then return; end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('tokens', to_jsonb(v_tokens), 'titulo', p_titulo,
                               'cuerpo', p_cuerpo, 'datos', p_datos),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secreto', v_secreto)
  );
exception when others then
  raise warning 'No se pudo enviar la notificación: %', sqlerrm; -- nunca daña el pedido
end $$;
revoke execute on function public.enviar_push(uuid[], text, text, jsonb) from public, anon, authenticated;

-- 4. Pedidos: nuevo pedido, asignado, recogido, entregado, cancelado
create or replace function public.push_pedidos() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_destinos uuid[]; v_radio double precision := 5.0 / 111.0; -- ~5 km en grados
begin
  if tg_op = 'INSERT' then
    -- Domiciliarios aprobados y conectados a menos de ~5 km de la recogida
    select array_agg(d.id) into v_destinos
      from domiciliarios d
     where d.estado = 'aprobado' and d.disponible and d.id <> new.cliente_id
       and d.lat between new.origen_lat - v_radio and new.origen_lat + v_radio
       and d.lng between new.origen_lng - v_radio and new.origen_lng + v_radio;
    if v_destinos is not null then
      perform enviar_push(v_destinos, 'Nuevo pedido cerca · $' || pesos_txt(new.tarifa_ofrecida),
        new.origen_nombre || ' → ' || new.destino_nombre,
        jsonb_build_object('tipo', 'pedido_nuevo', 'pedido_id', new.id::text));
    end if;
    return new;
  end if;

  if new.estado is not distinct from old.estado then return new; end if;

  if new.estado = 'asignado' then
    perform enviar_push(array[new.domiciliario_id], '¡El cliente aceptó tu oferta!',
      'Ve a recoger en ' || new.origen_nombre,
      jsonb_build_object('tipo', 'asignado', 'pedido_id', new.id::text));
  elsif new.estado = 'recogido' then
    perform enviar_push(array[new.cliente_id], 'Tu paquete va en camino',
      'El domiciliario lo recogió. Comparte el código de entrega con quien recibe.',
      jsonb_build_object('tipo', 'recogido', 'pedido_id', new.id::text));
  elsif new.estado = 'entregado' then
    perform enviar_push(array[new.cliente_id], 'Paquete entregado',
      'Califica a tu domiciliario en DeUna.',
      jsonb_build_object('tipo', 'entregado', 'pedido_id', new.id::text));
  elsif new.estado = 'cancelado' and new.domiciliario_id is not null then
    perform enviar_push(array[new.domiciliario_id], 'Pedido cancelado',
      'El cliente canceló el pedido de ' || new.origen_nombre || '.',
      jsonb_build_object('tipo', 'cancelado', 'pedido_id', new.id::text));
  end if;
  return new;
end $$;

drop trigger if exists push_pedidos on public.pedidos;
create trigger push_pedidos after insert or update of estado on public.pedidos
for each row execute function public.push_pedidos();

-- 5. Ofertas: al cliente le llega cada oferta nueva
create or replace function public.push_ofertas() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_cliente uuid; v_nombre text;
begin
  select cliente_id into v_cliente from pedidos where id = new.pedido_id;
  select nombre into v_nombre from perfiles where id = new.domiciliario_id;
  perform enviar_push(array[v_cliente], 'Nueva oferta: $' || pesos_txt(new.precio),
    coalesce(nullif(v_nombre, ''), 'Un domiciliario') || ' llega en ' || new.minutos_llegada || ' min.',
    jsonb_build_object('tipo', 'oferta', 'pedido_id', new.pedido_id::text));
  return new;
end $$;

drop trigger if exists push_ofertas on public.ofertas;
create trigger push_ofertas after insert on public.ofertas
for each row execute function public.push_ofertas();

-- 6. Recargas: al admin cuando le piden una; al domiciliario cuando se la confirman o rechazan
create or replace function public.push_recargas() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_admin uuid; v_nombre text;
begin
  if tg_op = 'INSERT' then
    select m.admin_id into v_admin
      from domiciliarios d join mensajerias m on m.id = d.mensajeria_id
     where d.id = new.domiciliario_id;
    select nombre into v_nombre from perfiles where id = new.domiciliario_id;
    perform enviar_push(array[v_admin], 'Solicitud de recarga',
      coalesce(nullif(v_nombre, ''), 'Un domiciliario') || ' pide $' || pesos_txt(new.monto) || '.',
      jsonb_build_object('tipo', 'solicitud_recarga'));
  elsif new.estado is distinct from old.estado then
    if new.estado = 'aprobada' then
      perform enviar_push(array[new.domiciliario_id], 'Recarga confirmada',
        'Se sumaron $' || pesos_txt(new.monto) || ' a tu saldo.', jsonb_build_object('tipo', 'recarga'));
    elsif new.estado = 'rechazada' and auth.uid() is distinct from new.domiciliario_id then
      perform enviar_push(array[new.domiciliario_id], 'Recarga rechazada',
        'Tu mensajería no confirmó el pago de $' || pesos_txt(new.monto) || '.', jsonb_build_object('tipo', 'recarga'));
    end if;
  end if;
  return new;
end $$;

drop trigger if exists push_recargas on public.solicitudes_recarga;
create trigger push_recargas after insert or update of estado on public.solicitudes_recarga
for each row execute function public.push_recargas();
