-- =========================================================
-- DeUna - CAMBIO: documentos del domiciliario
-- Ejecutar UNA vez en Supabase > SQL Editor (después de cambio_notificaciones.sql).
-- =========================================================

-- 1. Autorización de tratamiento de datos (Ley 1581 de 2012)
alter table public.domiciliarios add column if not exists autorizacion_datos_en timestamptz;

-- 2. Documentos (uno por tipo; al renovarlo se reemplaza la misma fila y la misma foto)
create table if not exists public.documentos_domiciliario (
  domiciliario_id uuid not null references public.domiciliarios(id) on delete cascade,
  tipo            text not null check (tipo in ('selfie', 'cedula_frente', 'cedula_respaldo',
                                                'licencia', 'soat', 'tarjeta_propiedad', 'tecnomecanica')),
  ruta            text not null,          -- ruta del archivo en Storage
  vence_en        date,                   -- solo licencia, SOAT y técnico-mecánica
  estado          text not null default 'pendiente'
                  check (estado in ('pendiente', 'aprobado', 'rechazado')),
  motivo          text,                   -- por qué se rechazó
  revisado_por    uuid references public.perfiles(id),
  subido_en       timestamptz not null default now(),
  revisado_en     timestamptz,
  primary key (domiciliario_id, tipo)
);
alter table public.documentos_domiciliario enable row level security;

drop policy if exists "ver documentos" on public.documentos_domiciliario;
create policy "ver documentos" on public.documentos_domiciliario
  for select to authenticated using (
    domiciliario_id = auth.uid()
    or exists (select 1 from public.domiciliarios d
               where d.id = domiciliario_id
                 and d.mensajeria_id = public.mensajeria_que_administro()));
revoke insert, update, delete on public.documentos_domiciliario from authenticated;

-- 3. Storage: fotos de perfil (públicas, las ve el cliente) y documentos (privados)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos_perfil', 'fotos_perfil', true, 524288, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 524288,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documentos', 'documentos', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];
-- Límites: 512 KB por foto de perfil y 2 MB por documento (la app las comprime antes).

-- Foto de perfil: cada usuario solo escribe el archivo <su id>.jpg
drop policy if exists "foto perfil: subir la mia" on storage.objects;
create policy "foto perfil: subir la mia" on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos_perfil' and name = auth.uid()::text || '.jpg');
drop policy if exists "foto perfil: cambiar la mia" on storage.objects;
create policy "foto perfil: cambiar la mia" on storage.objects for update to authenticated
  using (bucket_id = 'fotos_perfil' and name = auth.uid()::text || '.jpg');
drop policy if exists "foto perfil: ver la mia" on storage.objects;
create policy "foto perfil: ver la mia" on storage.objects for select to authenticated
  using (bucket_id = 'fotos_perfil' and name = auth.uid()::text || '.jpg');

-- Documentos: carpeta <id del domiciliario>/; la ve él y el admin de su mensajería
drop policy if exists "documentos: subir los mios" on storage.objects;
create policy "documentos: subir los mios" on storage.objects for insert to authenticated
  with check (bucket_id = 'documentos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "documentos: cambiar los mios" on storage.objects;
create policy "documentos: cambiar los mios" on storage.objects for update to authenticated
  using (bucket_id = 'documentos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "documentos: borrar los mios" on storage.objects;
create policy "documentos: borrar los mios" on storage.objects for delete to authenticated
  using (bucket_id = 'documentos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "documentos: ver" on storage.objects;
create policy "documentos: ver" on storage.objects for select to authenticated
  using (bucket_id = 'documentos' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.domiciliarios d
               where d.id::text = (storage.foldername(name))[1]
                 and d.mensajeria_id = public.mensajeria_que_administro())));

-- 4. Avisos push (solo si ya se ejecutó cambio_notificaciones.sql)
create or replace function public.push_si_existe(p_usuarios uuid[], p_titulo text, p_cuerpo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if to_regprocedure('public.enviar_push(uuid[], text, text, jsonb)') is not null then
    execute 'select public.enviar_push($1, $2, $3, $4)'
      using p_usuarios, p_titulo, p_cuerpo, jsonb_build_object('tipo', 'documentos');
  end if;
end $$;
revoke execute on function public.push_si_existe(uuid[], text, text) from public, anon, authenticated;

-- 5. Funciones que usa la app
create or replace function public.aceptar_autorizacion_datos() returns void
language plpgsql security definer set search_path = public as $$
begin
  update domiciliarios set autorizacion_datos_en = now() where id = auth.uid();
  if not found then raise exception 'Primero regístrate como domiciliario'; end if;
end $$;

-- El domiciliario registra (o renueva) un documento que ya subió a Storage.
create or replace function public.guardar_documento(p_tipo text, p_ruta text, p_vence date default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_admin uuid; v_nombre text;
begin
  if not exists (select 1 from domiciliarios where id = auth.uid() and autorizacion_datos_en is not null) then
    raise exception 'Primero acepta la autorización de tratamiento de datos';
  end if;
  if p_tipo in ('licencia', 'soat', 'tecnomecanica') then
    if p_vence is null then raise exception 'Escribe la fecha de vencimiento'; end if;
    if p_vence < current_date then raise exception 'Ese documento ya está vencido'; end if;
  end if;
  insert into documentos_domiciliario (domiciliario_id, tipo, ruta, vence_en)
  values (auth.uid(), p_tipo, p_ruta, case when p_tipo in ('licencia', 'soat', 'tecnomecanica') then p_vence end)
  on conflict (domiciliario_id, tipo) do update
    set ruta = excluded.ruta, vence_en = excluded.vence_en, estado = 'pendiente',
        motivo = null, revisado_por = null, revisado_en = null, subido_en = now();

  select m.admin_id into v_admin from domiciliarios d join mensajerias m on m.id = d.mensajeria_id
   where d.id = auth.uid();
  select nombre into v_nombre from perfiles where id = auth.uid();
  perform push_si_existe(array[v_admin], 'Documento por revisar',
    coalesce(nullif(v_nombre, ''), 'Un domiciliario') || ' subió un documento.');
end $$;

-- El admin aprueba o rechaza un documento.
create or replace function public.revisar_documento(p_dom uuid, p_tipo text, p_aprobar boolean,
                                                    p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from domiciliarios
                 where id = p_dom and mensajeria_id = public.mensajeria_que_administro()) then
    raise exception 'Ese domiciliario no es de tu mensajería';
  end if;
  if not p_aprobar and coalesce(trim(p_motivo), '') = '' then
    raise exception 'Escribe el motivo del rechazo';
  end if;
  update documentos_domiciliario
     set estado = case when p_aprobar then 'aprobado' else 'rechazado' end,
         motivo = case when p_aprobar then null else trim(p_motivo) end,
         revisado_por = auth.uid(), revisado_en = now()
   where domiciliario_id = p_dom and tipo = p_tipo;
  if not found then raise exception 'Ese documento no existe'; end if;
  if not p_aprobar then
    perform push_si_existe(array[p_dom], 'Documento rechazado', trim(p_motivo));
  end if;
end $$;

-- true si tiene los 6 documentos obligatorios aprobados y ninguno vencido.
-- (La técnico-mecánica es opcional, pero si la subió y está vencida, también cuenta.)
create or replace function public.documentos_al_dia(p_dom uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select (select count(*) from documentos_domiciliario
           where domiciliario_id = p_dom and estado = 'aprobado'
             and tipo in ('selfie', 'cedula_frente', 'cedula_respaldo', 'licencia', 'soat', 'tarjeta_propiedad')
             and (vence_en is null or vence_en >= current_date)) = 6
     and not exists (select 1 from documentos_domiciliario
                      where domiciliario_id = p_dom and vence_en < current_date);
$$;

-- 6. Aprobar domiciliario: ahora exige los documentos al día
create or replace function public.cambiar_estado_domiciliario(p_dom uuid, p_estado text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from domiciliarios
                 where id = p_dom and mensajeria_id = public.mensajeria_que_administro()) then
    raise exception 'Ese domiciliario no es de tu mensajería';
  end if;
  if p_estado = 'aprobado' and not public.documentos_al_dia(p_dom) then
    raise exception 'Faltan documentos por aprobar o hay alguno vencido';
  end if;
  update domiciliarios set estado = p_estado where id = p_dom;
  if p_estado = 'aprobado' then
    perform push_si_existe(array[p_dom], '¡Ya puedes trabajar!',
      'Tu mensajería aprobó tu cuenta. Cambia a modo domiciliario.');
  end if;
end $$;

-- 7. Ofertar: además de lo anterior, exige documentos al día
create or replace function public.ofertar(p_pedido uuid, p_precio integer, p_minutos integer)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_dom domiciliarios; v_pedido pedidos; v_id uuid;
begin
  select * into v_dom from domiciliarios where id = auth.uid();
  if v_dom.id is null or v_dom.estado <> 'aprobado' then
    raise exception 'No eres un domiciliario aprobado';
  end if;
  if not public.documentos_al_dia(v_dom.id) then
    raise exception 'Tienes documentos vencidos o sin aprobar. Revisa "Mis documentos"';
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

-- 8. Avisos de vencimiento: 15 días antes, 1 día antes y el día que vence (cada mañana)
create or replace function public.avisar_vencimientos() returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  for r in
    select domiciliario_id, tipo, vence_en from documentos_domiciliario
     where estado = 'aprobado' and vence_en in (current_date + 15, current_date + 1, current_date)
  loop
    perform push_si_existe(array[r.domiciliario_id],
      case when r.vence_en = current_date then 'Documento vencido hoy' else 'Documento por vencer' end,
      'Tu ' || case r.tipo when 'soat' then 'SOAT' when 'licencia' then 'licencia'
                           else 'técnico-mecánica' end
        || ' vence el ' || to_char(r.vence_en, 'DD/MM/YYYY') || '. Sube el nuevo en "Mis documentos".');
    n := n + 1;
  end loop;
  return n;
end $$;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('avisar-vencimientos', '0 13 * * *', 'select public.avisar_vencimientos()');
  -- 13:00 UTC = 8:00 a. m. en Colombia
exception when others then
  raise notice 'pg_cron no disponible (%): no habrá avisos automáticos de vencimiento.', sqlerrm;
end $$;

-- 9. Para el cliente: ¿este domiciliario tiene los documentos verificados?
create or replace function public.domiciliario_verificado(p_dom uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.documentos_al_dia(p_dom);
$$;
