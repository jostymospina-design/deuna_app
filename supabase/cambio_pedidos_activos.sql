-- =========================================================
-- DeUna - CAMBIO: un solo pedido en curso por cliente
-- Ejecutar UNA vez en Supabase > SQL Editor.
-- =========================================================

-- 1. Limpia lo que ya está repetido: si un cliente tiene varios pedidos en curso,
--    se cancelan los que siguen "buscando" y se deja el asignado/recogido (o el más reciente).
update public.pedidos p
   set estado = 'cancelado'
 where p.estado = 'buscando'
   and exists (select 1 from public.pedidos o
                where o.cliente_id = p.cliente_id and o.id <> p.id
                  and o.estado in ('buscando', 'asignado', 'recogido')
                  and (o.estado <> 'buscando' or o.creado_en > p.creado_en));

-- 2. Búsquedas abandonadas: un pedido "buscando" por más de 30 minutos se cancela solo.
create or replace function public.cancelar_busquedas_viejas() returns integer
language sql security definer set search_path = public as $$
  with c as (
    update pedidos set estado = 'cancelado'
     where estado = 'buscando' and creado_en < now() - interval '30 minutes'
    returning 1
  )
  select count(*)::int from c;
$$;
select public.cancelar_busquedas_viejas();

-- 3. Antes de crear un pedido: no se permite si el cliente ya tiene uno en curso.
create or replace function public.un_pedido_en_curso() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update pedidos set estado = 'cancelado'
   where cliente_id = new.cliente_id and estado = 'buscando'
     and creado_en < now() - interval '30 minutes';
  if exists (select 1 from pedidos
             where cliente_id = new.cliente_id
               and estado in ('buscando', 'asignado', 'recogido')) then
    raise exception 'Ya tienes un pedido en curso. Ábrelo con "Ver mi pedido" en la pantalla principal';
  end if;
  return new;
end $$;

drop trigger if exists un_pedido_en_curso on public.pedidos;
create trigger un_pedido_en_curso before insert on public.pedidos
for each row execute function public.un_pedido_en_curso();

-- 4. Revisión automática cada 10 minutos (si pg_cron está disponible)
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('cancelar-busquedas-viejas', '*/10 * * * *',
                        'select public.cancelar_busquedas_viejas()');
exception when others then
  raise notice 'pg_cron no disponible (%): las búsquedas viejas se cancelan al crear el siguiente pedido.', sqlerrm;
end $$;
