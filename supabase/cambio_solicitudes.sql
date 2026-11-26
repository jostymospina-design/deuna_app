-- =========================================================
-- DeUna - CAMBIO: solicitudes de recarga (rechazar + vencer a las 3 horas)
-- Ejecutar UNA vez en Supabase > SQL Editor, sobre la base de datos que ya existe.
-- =========================================================

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
