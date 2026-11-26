-- =========================================================
-- DeUna - CAMBIO: código de entrega (ejecutar UNA vez sobre la BD que ya existe)
-- =========================================================

-- 1. Nuevas columnas en la tabla de códigos
alter table public.codigos_pedido
  add column if not exists codigo_entrega   text,
  add column if not exists intentos_entrega smallint not null default 0;

-- 2. Pedidos que ya existían: se les crea un código de entrega distinto al de recogida
update public.codigos_pedido
   set codigo_entrega = lpad(((codigo::int + 1 + floor(random() * 9998)::int) % 10000)::text, 4, '0')
 where codigo_entrega is null;

alter table public.codigos_pedido alter column codigo_entrega set not null;

-- 3. El trigger ahora genera los dos códigos
-- Genera los dos códigos de 4 dígitos de cada pedido (siempre distintos).
create or replace function public.crear_codigo() returns trigger
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


-- 4. finalizar_pedido ahora recibe el código de entrega (se borra la versión vieja)
drop function if exists public.finalizar_pedido(uuid);

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

