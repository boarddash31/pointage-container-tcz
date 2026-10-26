-- Normalize messages from the Windows-encoded migration without changing rules.
do $$
declare fn regprocedure;
begin
  foreach fn in array array[
    'public.guard_transport_order_item_edit()'::regprocedure,
    'public.update_transport_order(uuid,integer,jsonb)'::regprocedure,
    'public.increase_transport_order_quantity(uuid,integer)'::regprocedure,
    'public.create_transport_order(text,text,text,text,jsonb,uuid,text)'::regprocedure,
    'public.bind_visit_order()'::regprocedure,
    'public.transport_order_items_status()'::regprocedure
  ] loop
    execute convert_from(convert_to(pg_get_functiondef(fn),'WIN1252'),'UTF8');
  end loop;
end $$;
