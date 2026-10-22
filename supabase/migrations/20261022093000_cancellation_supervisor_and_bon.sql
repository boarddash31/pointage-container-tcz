-- Migration: Supervisor Code 01010909 for cancellation and generated Bon d'Annulation

-- 1. Update generated_documents kind constraint to allow 'ANNULATION'
alter table public.generated_documents drop constraint if exists generated_documents_kind_check;
alter table public.generated_documents add constraint generated_documents_kind_check
  check (kind in ('ENTREE','DEPOSE','PRISE','SORTIE','ANNULATION'));

-- 2. Drop existing cancel_visit function
drop function if exists public.cancel_visit(uuid, text);
drop function if exists public.cancel_visit(uuid, text, text);

-- 3. Create updated cancel_visit function that accepts supervisor code 01010909 and generates Bon d'Annulation
create or replace function public.cancel_visit(
  p_visit uuid,
  p_reason text,
  p_admin_code text default null
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_actor uuid := auth.uid();
  v_visit public.truck_visits;
  v_before jsonb;
  v_event_id bigint;
  v_doc_id uuid;
begin
  -- Validate permission: admin role OR supervisor PIN code 01010909
  if not (public.can_do('admin') or p_admin_code = '01010909') then
    raise exception 'admin required' using errcode='42501';
  end if;

  if length(btrim(coalesce(p_reason, '')))<5 then
    raise exception 'cancellation reason required';
  end if;

  select * into v_visit from public.truck_visits where id = p_visit for update;
  if not found or v_visit.exited_at is not null or v_visit.canceled_at is not null then
    raise exception 'only active visits may be canceled';
  end if;

  v_before := to_jsonb(v_visit);

  -- Update truck visit to canceled
  update public.truck_visits
    set canceled_at = now(),
        canceled_by = v_actor,
        cancel_reason = btrim(p_reason),
        version = version + 1
    where id = p_visit
    returning * into v_visit;

  -- Insert cancellation event
  insert into public.visit_events(visit_id, action, actor_id, details)
    values(
      p_visit,
      'ANNULATION',
      v_actor,
      jsonb_build_object(
        'reason', p_reason,
        'supervisor_validated', (p_admin_code = '01010909' or public.can_do('admin')),
        'supervisor_code_used', (p_admin_code = '01010909')
      )
    )
    returning id into v_event_id;

  -- Generate official Bon d'Annulation in generated_documents
  insert into public.generated_documents(visit_id, event_id, kind, snapshot, created_by)
    values(
      p_visit,
      v_event_id,
      'ANNULATION',
      to_jsonb(v_visit) || jsonb_build_object(
        'event', jsonb_build_object(
          'reason', p_reason,
          'supervisor_validated', true,
          'supervisor_code', '01010909'
        )
      ),
      v_actor
    )
    returning id into v_doc_id;

  -- Record audit log
  insert into public.audit_logs(entity, entity_id, action, actor_id, before_data, after_data, reason)
    values('truck_visit', p_visit::text, 'ANNULATION', v_actor, v_before, to_jsonb(v_visit), p_reason);

  return v_doc_id;
end; $$;

revoke all on function public.cancel_visit(uuid, text, text) from public, anon;
grant execute on function public.cancel_visit(uuid, text, text) to authenticated;
