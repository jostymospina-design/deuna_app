-- =========================================================
-- DeUna - esquema completo (pegar en Supabase > SQL Editor > Run)
-- =========================================================

-- ---------- 1. TABLAS ----------

create table public.perfiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  nombre       text not null default '',
  telefono     text,
  foto_url     text,
  calificacion numeric(3,2) not null default 5,
  creado_en    timestamptz not null default now()
);

create table public.mensajerias (
  id                  uuid primary key default gen_random_uuid(),
  nombre              text not null,
  telefono            text,
  admin_id            uuid not null unique references public.perfiles(id) on delete cascade,
  porcentaje_comision numeric(5,2) not null default 10
                      check (porcentaje_comision between 0 and 50),
  creado_en           timestamptz not null default now()
);

create table public.domiciliarios (
  id            uuid primary key references public.perfiles(id) on delete cascade,
  mensajeria_id uuid not null references public.mensajerias(id),
  vehiculo      text not null,
  placa         text not null,
  estado        text not null default 'pendiente'
                check (estado in ('pendiente','aprobado','bloqueado')),
  saldo         integer not null default 0,
  disponible    boolean not null default false,
  lat           double precision,
  lng           double precision,
  ubicacion_en  timestamptz,
  creado_en     timestamptz not null default now()
);
create index on public.domiciliarios (mensajeria_id);

create table public.pedidos (
  id              uuid primary key default gen_random_uuid(),
  cliente_id      uuid not null references public.perfiles(id),
  domiciliario_id uuid references public.domiciliarios(id),
  origen_nombre   text not null,
  origen_lat      double precision not null,
  origen_lng      double precision not null,
  destino_nombre  text not null,
  destino_lat     double precision not null,
  destino_lng     double precision not null,
  tipo_paquete    text not null default 'Caja pequeña',
  peso            text,
  indicaciones    text,
  distancia_km    numeric(6,2) not null,
  tarifa_ofrecida integer not null check (tarifa_ofrecida > 0),
  precio_final    integer,
  comision        integer,
  propina         integer not null default 0,
  calificacion    smallint check (calificacion between 1 and 5),
  estado          text not null default 'buscando'
                  check (estado in ('buscando','asignado','recogido','entregado','cancelado')),
  creado_en       timestamptz not null default now(),
  asignado_en     timestamptz,
  recogido_en     timestamptz,
  entregado_en    timestamptz
);
create index on public.pedidos (cliente_id, creado_en desc);
create index on public.pedidos (domiciliario_id, creado_en desc);
create index on public.pedidos (creado_en desc) where estado = 'buscando';

-- El código va en una tabla aparte: así el domiciliario NUNCA puede leerlo.
-- codigo         = se dicta al RECOGER (confirma que es el pedido correcto)
-- codigo_entrega = lo dice quien RECIBE en el destino (confirma que es la persona correcta)
create table public.codigos_pedido (
  pedido_id        uuid primary key references public.pedidos(id) on delete cascade,
  codigo           text not null,
  codigo_entrega   text not null,
  intentos         smallint not null default 0,
  intentos_entrega smallint not null default 0
);

create table public.ofertas (
  id              uuid primary key default gen_random_uuid(),
  pedido_id       uuid not null references public.pedidos(id) on delete cascade,
  domiciliario_id uuid not null references public.domiciliarios(id),
  precio          integer not null check (precio > 0),
  minutos_llegada integer not null default 10,
  estado          text not null default 'pendiente'
                  check (estado in ('pendiente','aceptada','rechazada')),
  creado_en       timestamptz not null default now(),
  unique (pedido_id, domiciliario_id)
);

create table public.movimientos_saldo (
  id              bigint generated always as identity primary key,
  domiciliario_id uuid not null references public.domiciliarios(id),
  tipo            text not null check (tipo in ('recarga','comision','ajuste')),
  monto           integer not null,          -- + recarga, - comisión
  saldo_despues   integer not null,
  pedido_id       uuid references public.pedidos(id),
  registrado_por  uuid references public.perfiles(id),
  creado_en       timestamptz not null default now()
);
create index on public.movimientos_saldo (domiciliario_id, creado_en desc);

create table public.solicitudes_recarga (
  id              uuid primary key default gen_random_uuid(),
  domiciliario_id uuid not null references public.domiciliarios(id),
  monto           integer not null check (monto >= 5000),
  estado          text not null default 'pendiente'
                  check (estado in ('pendiente','aprobada','rechazada')),
  creado_en       timestamptz not null default now(),
  resuelto_en     timestamptz
);

create table public.lugares_guardados (
  id         uuid primary key default gen_random_uuid(),
  usuario_id uuid not null default auth.uid() references public.perfiles(id) on delete cascade,
  nombre     text not null,          -- "Casa", "Trabajo"
  direccion  text not null,
  lat        double precision not null,
  lng        double precision not null
);

-- ---------- 2. TRIGGERS ----------

-- Crea el perfil automáticamente cuando alguien se registra.
create function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (id, nombre, telefono)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'nombre', ''),
          new.raw_user_meta_data->>'telefono');
  return new;
end $$;

create trigger al_registrarse after insert on auth.users
for each row execute function public.crear_perfil();

-- Genera los dos códigos de 4 dígitos de cada pedido (siempre distintos).
create function public.crear_codigo() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_rec text; v_ent text;
begin
  v_rec := lpad((floor(random() * 10000))::int::text, 4, '0');
  loop
    v_ent := lpad((floor(random() * 10000))::int::text, 4, '0');
    exit when v_ent <> v_rec;
  end loop;
  insert into public.codigos_pedido (pedido_id, codigo, codigo_entrega)
  values (new.id, v_rec, v_ent);
  return new;
end $$;

create trigger al_crear_pedido after insert on public.pedidos
for each row execute function public.crear_codigo();

-- ---------- 3. FUNCIONES DE AYUDA ----------

create function public.soy_domiciliario_aprobado() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from domiciliarios
                 where id = auth.uid() and estado = 'aprobado');
$$;

create function public.mensajeria_que_administro() returns uuid
language sql stable security definer set search_path = public as $$
  select id from mensajerias where admin_id = auth.uid();
$$;

create function public.puede_ver_perfil(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p = auth.uid()
    or exists (select 1 from pedidos pe
               where (pe.cliente_id = auth.uid() and pe.domiciliario_id = p)
                  or (pe.domiciliario_id = auth.uid() and pe.cliente_id = p))
    or exists (select 1 from ofertas o join pedidos pe on pe.id = o.pedido_id
               where pe.cliente_id = auth.uid() and o.domiciliario_id = p)
    or exists (select 1 from domiciliarios d
               where d.id = p and d.mensajeria_id = public.mensajeria_que_administro());
$$;

-- ---------- 4. SEGURIDAD (RLS) ----------

alter table public.perfiles            enable row level security;
alter table public.mensajerias         enable row level security;
alter table public.domiciliarios       enable row level security;
alter table public.pedidos             enable row level security;
alter table public.codigos_pedido      enable row level security;
alter table public.ofertas             enable row level security;
alter table public.movimientos_saldo   enable row level security;
alter table public.solicitudes_recarga enable row level security;
alter table public.lugares_guardados   enable row level security;

-- perfiles
create policy "ver perfiles permitidos" on public.perfiles
  for select to authenticated using (public.puede_ver_perfil(id));
create policy "editar mi perfil" on public.perfiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.perfiles from authenticated;
grant update (nombre, telefono, foto_url) on public.perfiles to authenticated;

-- mensajerias
create policy "ver mensajerias" on public.mensajerias
  for select to authenticated using (true);
create policy "crear mi mensajeria" on public.mensajerias
  for insert to authenticated with check (admin_id = auth.uid());
create policy "editar mi mensajeria" on public.mensajerias
  for update to authenticated using (admin_id = auth.uid());

-- domiciliarios
create policy "ver domiciliarios" on public.domiciliarios
  for select to authenticated using (public.puede_ver_perfil(id));
create policy "registrarme como domiciliario" on public.domiciliarios
  for insert to authenticated
  with check (id = auth.uid() and estado = 'pendiente' and saldo = 0);
create policy "actualizar mi estado" on public.domiciliarios
  for update to authenticated using (id = auth.uid());
revoke update on public.domiciliarios from authenticated;
grant update (disponible, lat, lng, ubicacion_en, vehiculo, placa)
  on public.domiciliarios to authenticated;

-- pedidos (los cambios de estado solo por funciones RPC)
create policy "ver mis pedidos o los disponibles" on public.pedidos
  for select to authenticated using (
    cliente_id = auth.uid()
    or domiciliario_id = auth.uid()
    or (estado = 'buscando' and public.soy_domiciliario_aprobado())
  );
create policy "crear pedido" on public.pedidos
  for insert to authenticated
  with check (cliente_id = auth.uid() and estado = 'buscando'
              and domiciliario_id is null and precio_final is null and comision is null);
revoke update, delete on public.pedidos from authenticated;

-- codigos: solo el cliente
create policy "solo el cliente ve su codigo" on public.codigos_pedido
  for select to authenticated using (
    exists (select 1 from public.pedidos pe
            where pe.id = pedido_id and pe.cliente_id = auth.uid()));
revoke insert, update, delete on public.codigos_pedido from authenticated;

-- ofertas (se crean con la función ofertar)
create policy "ver ofertas" on public.ofertas
  for select to authenticated using (
    domiciliario_id = auth.uid()
    or exists (select 1 from public.pedidos pe
               where pe.id = pedido_id and pe.cliente_id = auth.uid()));
revoke insert, update, delete on public.ofertas from authenticated;

-- movimientos de saldo
create policy "ver movimientos" on public.movimientos_saldo
  for select to authenticated using (
    domiciliario_id = auth.uid()
    or exists (select 1 from public.domiciliarios d
               where d.id = domiciliario_id
                 and d.mensajeria_id = public.mensajeria_que_administro()));
revoke insert, update, delete on public.movimientos_saldo from authenticated;

-- solicitudes de recarga
create policy "ver solicitudes" on public.solicitudes_recarga
  for select to authenticated using (
    domiciliario_id = auth.uid()
    or exists (select 1 from public.domiciliarios d
               where d.id = domiciliario_id
                 and d.mensajeria_id = public.mensajeria_que_administro()));
create policy "pedir recarga" on public.solicitudes_recarga
  for insert to authenticated
  with check (domiciliario_id = auth.uid() and estado = 'pendiente');
revoke update, delete on public.solicitudes_recarga from authenticated;

-- lugares guardados
create policy "mis lugares" on public.lugares_guardados
  for all to authenticated using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- ---------- 5. FUNCIONES RPC (lógica de negocio en el servidor) ----------

-- Comisión que se cobraría por un precio dado a un domiciliario.
create function public.calcular_comision(p_dom uuid, p_precio integer) returns integer
language sql stable security definer set search_path = public as $$
  select ceil(p_precio * m.porcentaje_comision / 100)::int
  from domiciliarios d join mensajerias m on m.id = d.mensajeria_id
  where d.id = p_dom;
$$;

-- Domiciliario hace (o cambia) su oferta.
create function public.ofertar(p_pedido uuid, p_precio integer, p_minutos integer)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_dom domiciliarios; v_pedido pedidos; v_id uuid;
begin
  select * into v_dom from domiciliarios where id = auth.uid();
  if v_dom.id is null or v_dom.estado <> 'aprobado' then
    raise exception 'No eres un domiciliario aprobado';
  end if;
  select * into v_pedido from pedidos where id = p_pedido;
  if v_pedido.estado is distinct from 'buscando' then
    raise exception 'El pedido ya no está disponible';
  end if;
  if v_pedido.cliente_id = auth.uid() then
    raise exception 'No puedes ofertar en tu propio pedido';
  end if;
  if exists (select 1 from pedidos where domiciliario_id = auth.uid()
             and estado in ('asignado','recogido')) then
    raise exception 'Termina tu pedido actual antes de ofertar';
  end if;
  if v_dom.saldo < public.calcular_comision(v_dom.id, p_precio) then
    raise exception 'Saldo insuficiente. Recarga para seguir trabajando';
  end if;

  insert into ofertas (pedido_id, domiciliario_id, precio, minutos_llegada)
  values (p_pedido, auth.uid(), p_precio, p_minutos)
  on conflict (pedido_id, domiciliario_id)
  do update set precio = excluded.precio, minutos_llegada = excluded.minutos_llegada,
                estado = 'pendiente', creado_en = now()
  returning id into v_id;
  return v_id;
end $$;

-- Cliente acepta una oferta.
create function public.aceptar_oferta(p_oferta uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_of ofertas; v_pedido pedidos;
begin
  select * into v_of from ofertas where id = p_oferta;
  select * into v_pedido from pedidos where id = v_of.pedido_id for update;
  if v_pedido.cliente_id is distinct from auth.uid() then
    raise exception 'Este pedido no es tuyo';
  end if;
  if v_pedido.estado <> 'buscando' then
    raise exception 'El pedido ya fue asignado o cancelado';
  end if;
  update pedidos set domiciliario_id = v_of.domiciliario_id, precio_final = v_of.precio,
         estado = 'asignado', asignado_en = now()
   where id = v_pedido.id;
  update ofertas set estado = case when id = p_oferta then 'aceptada' else 'rechazada' end
   where pedido_id = v_pedido.id;
end $$;

-- Domiciliario escribe el código que le dicta el cliente.
create function public.verificar_codigo(p_pedido uuid, p_codigo text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_pedido pedidos; v_cod codigos_pedido;
begin
  select * into v_pedido from pedidos where id = p_pedido for update;
  if v_pedido.domiciliario_id is distinct from auth.uid() or v_pedido.estado <> 'asignado' then
    raise exception 'No puedes verificar este pedido';
  end if;
  select * into v_cod from codigos_pedido where pedido_id = p_pedido for update;
  if v_cod.intentos >= 5 then
    raise exception 'Demasiados intentos. Pide al cliente que cancele y cree otro pedido';
  end if;
  if v_cod.codigo = trim(p_codigo) then
    update pedidos set estado = 'recogido', recogido_en = now() where id = p_pedido;
    return true;
  end if;
  update codigos_pedido set intentos = intentos + 1 where pedido_id = p_pedido;
  return false;
end $$;

-- Cierra el pedido y descuenta la comisión.
-- Domiciliario: DEBE enviar el código de entrega que le dice quien recibe (máx. 5 intentos).
-- Cliente: puede cerrarlo sin código ("Ya recibí mi paquete"), porque es el dueño del pedido.
-- Devuelve false si el código es incorrecto (no se cierra nada).
create function public.finalizar_pedido(p_pedido uuid, p_codigo text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_pedido pedidos; v_cod codigos_pedido; v_comision integer; v_saldo integer;
begin
  select * into v_pedido from pedidos where id = p_pedido for update;
  if auth.uid() is null or auth.uid() not in (v_pedido.cliente_id, v_pedido.domiciliario_id) then
    raise exception 'Este pedido no es tuyo';
  end if;
  if v_pedido.estado <> 'recogido' then
    raise exception 'El pedido debe estar recogido (código de recogida verificado)';
  end if;

  if auth.uid() = v_pedido.domiciliario_id then
    select * into v_cod from codigos_pedido where pedido_id = p_pedido for update;
    if v_cod.intentos_entrega >= 5 then
      raise exception 'Demasiados intentos. Comunícate con el cliente para que confirme la entrega';
    end if;
    if p_codigo is null or v_cod.codigo_entrega <> trim(p_codigo) then
      update codigos_pedido set intentos_entrega = intentos_entrega + 1 where pedido_id = p_pedido;
      return false;
    end if;
  end if;

  v_comision := public.calcular_comision(v_pedido.domiciliario_id, v_pedido.precio_final);
  update domiciliarios set saldo = saldo - v_comision
   where id = v_pedido.domiciliario_id returning saldo into v_saldo;
  insert into movimientos_saldo (domiciliario_id, tipo, monto, saldo_despues, pedido_id)
  values (v_pedido.domiciliario_id, 'comision', -v_comision, v_saldo, p_pedido);
  update pedidos set estado = 'entregado', entregado_en = now(), comision = v_comision
   where id = p_pedido;
  return true;
end $$;

create function public.cancelar_pedido(p_pedido uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update pedidos set estado = 'cancelado'
   where id = p_pedido and cliente_id = auth.uid() and estado in ('buscando','asignado');
  if not found then raise exception 'No se puede cancelar este pedido'; end if;
end $$;

create function public.calificar_pedido(p_pedido uuid, p_estrellas int, p_propina int)
returns void language plpgsql security definer set search_path = public as $$
declare v_dom uuid;
begin
  update pedidos set calificacion = p_estrellas, propina = greatest(p_propina, 0)
   where id = p_pedido and cliente_id = auth.uid() and estado = 'entregado'
   returning domiciliario_id into v_dom;
  if v_dom is null then raise exception 'No se puede calificar este pedido'; end if;
  update perfiles set calificacion =
    (select round(avg(calificacion), 2) from pedidos
      where domiciliario_id = v_dom and calificacion is not null)
   where id = v_dom;
end $$;

-- Admin aprueba o bloquea a un domiciliario de su mensajería.
create function public.cambiar_estado_domiciliario(p_dom uuid, p_estado text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update domiciliarios set estado = p_estado
   where id = p_dom and mensajeria_id = public.mensajeria_que_administro();
  if not found then raise exception 'Ese domiciliario no es de tu mensajería'; end if;
end $$;

-- Admin registra una recarga (el dinero lo recibió en efectivo o Nequi).
create function public.registrar_recarga(p_dom uuid, p_monto integer, p_solicitud uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v_saldo integer;
begin
  if p_monto < 5000 then raise exception 'La recarga mínima es 5.000'; end if;
  update domiciliarios set saldo = saldo + p_monto
   where id = p_dom and mensajeria_id = public.mensajeria_que_administro()
   returning saldo into v_saldo;
  if v_saldo is null then raise exception 'Ese domiciliario no es de tu mensajería'; end if;
  insert into movimientos_saldo (domiciliario_id, tipo, monto, saldo_despues, registrado_por)
  values (p_dom, 'recarga', p_monto, v_saldo, auth.uid());
  if p_solicitud is not null then
    update solicitudes_recarga set estado = 'aprobada', resuelto_en = now()
     where id = p_solicitud and domiciliario_id = p_dom;
  end if;
  return v_saldo;
end $$;

-- Pedidos que buscan domiciliario cerca de un punto (radio en km).
create function public.pedidos_cercanos(p_lat double precision, p_lng double precision,
                                        p_radio_km double precision default 5)
returns setof public.pedidos language sql stable set search_path = public as $$
  select * from pedidos
  where estado = 'buscando'
    and origen_lat between p_lat - p_radio_km / 111.0 and p_lat + p_radio_km / 111.0
    and origen_lng between p_lng - p_radio_km / 111.0 and p_lng + p_radio_km / 111.0
  order by (origen_lat - p_lat)^2 + (origen_lng - p_lng)^2
  limit 20;
$$;

-- ---------- 6. TIEMPO REAL ----------
alter publication supabase_realtime add table public.pedidos, public.ofertas;

-- ---------- 7. SOLICITUDES DE RECARGA: rechazar y vencer a las 3 horas ----------
-- 1. Nuevo estado "vencida" (además de pendiente, aprobada, rechazada)
alter table public.solicitudes_recarga drop constraint if exists solicitudes_recarga_estado_check;
alter table public.solicitudes_recarga add constraint solicitudes_recarga_estado_check
  check (estado in ('pendiente', 'aprobada', 'rechazada', 'vencida'));

-- 2. Vence las solicitudes pendientes con más de 3 horas
create or replace function public.vencer_solicitudes() returns integer
language sql security definer set search_path = public as $$
  with vencidas as (
    update solicitudes_recarga
       set estado = 'vencida', resuelto_en = now()
     where estado = 'pendiente' and creado_en < now() - interval '3 hours'
    returning 1
  )
  select count(*)::int from vencidas;
$$;

select public.vencer_solicitudes(); -- limpia las que ya existan

-- Si quedaron varias pendientes del mismo domiciliario, se deja solo la más reciente
update public.solicitudes_recarga s
   set estado = 'vencida', resuelto_en = now()
 where estado = 'pendiente'
   and exists (select 1 from public.solicitudes_recarga o
               where o.domiciliario_id = s.domiciliario_id
                 and o.estado = 'pendiente'
                 and o.creado_en > s.creado_en);

-- 3. Máximo una solicitud pendiente por domiciliario
create unique index if not exists una_solicitud_pendiente
  on public.solicitudes_recarga (domiciliario_id) where estado = 'pendiente';

-- 4. Las solicitudes ahora se crean con una función (mensaje claro si ya hay una pendiente)
drop policy if exists "pedir recarga" on public.solicitudes_recarga;
revoke insert on public.solicitudes_recarga from authenticated;

create or replace function public.solicitar_recarga(p_monto integer) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not exists (select 1 from domiciliarios where id = auth.uid()) then
    raise exception 'Solo los domiciliarios pueden pedir recargas';
  end if;
  if p_monto < 5000 then
    raise exception 'La recarga mínima es 5.000';
  end if;
  perform public.vencer_solicitudes();
  if exists (select 1 from solicitudes_recarga
             where domiciliario_id = auth.uid() and estado = 'pendiente') then
    raise exception 'Ya tienes una solicitud pendiente. Cancélala o espera a que tu mensajería la confirme';
  end if;
  insert into solicitudes_recarga (domiciliario_id, monto)
  values (auth.uid(), p_monto) returning id into v_id;
  return v_id;
end $$;

-- 5. Rechazar (admin: "no recibí el pago") o cancelar (el mismo domiciliario)
create or replace function public.rechazar_solicitud(p_solicitud uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update solicitudes_recarga s
     set estado = 'rechazada', resuelto_en = now()
   where s.id = p_solicitud
     and s.estado = 'pendiente'
     and (s.domiciliario_id = auth.uid()
          or exists (select 1 from domiciliarios d
                     where d.id = s.domiciliario_id
                       and d.mensajeria_id = public.mensajeria_que_administro()));
  if not found then
    raise exception 'La solicitud ya no está pendiente o no es de tu mensajería';
  end if;
end $$;

-- 6. registrar_recarga: ya no deja aprobar una solicitud vencida o ya resuelta
create or replace function public.registrar_recarga(p_dom uuid, p_monto integer, p_solicitud uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v_saldo integer;
begin
  if p_monto < 5000 then raise exception 'La recarga mínima es 5.000'; end if;
  if p_solicitud is not null then
    perform public.vencer_solicitudes();
    update solicitudes_recarga set estado = 'aprobada', resuelto_en = now()
     where id = p_solicitud and domiciliario_id = p_dom and estado = 'pendiente';
    if not found then
      raise exception 'La solicitud venció (más de 3 horas) o ya fue resuelta';
    end if;
  end if;
  update domiciliarios set saldo = saldo + p_monto
   where id = p_dom and mensajeria_id = public.mensajeria_que_administro()
   returning saldo into v_saldo;
  if v_saldo is null then raise exception 'Ese domiciliario no es de tu mensajería'; end if;
  insert into movimientos_saldo (domiciliario_id, tipo, monto, saldo_despues, registrado_por)
  values (p_dom, 'recarga', p_monto, v_saldo, auth.uid());
  return v_saldo;
end $$;

-- 7. Vencimiento automático cada 15 minutos con pg_cron (incluido en Supabase).
--    Si pg_cron no se puede activar, no pasa nada: la app y las funciones de arriba
--    ya tratan como vencidas las solicitudes de más de 3 horas.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('vencer-solicitudes-recarga', '*/15 * * * *',
                        'select public.vencer_solicitudes()');
exception when others then
  raise notice 'pg_cron no disponible (%). Actívalo en Integrations > Cron si quieres el vencimiento automático.', sqlerrm;
end $$;
