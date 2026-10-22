-- ==============================================================================
-- Migration: Add cancel_reason and increase recent_visits limit in admin_dashboard_kpis
-- ==============================================================================

create or replace function public.admin_dashboard_kpis(p_day date default current_date)
returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_res jsonb;
  v_start timestamptz := (p_day::timestamp at time zone 'Africa/Casablanca');
  v_end timestamptz := ((p_day + 1)::timestamp at time zone 'Africa/Casablanca');
begin
  select jsonb_build_object(
    'day', p_day,
    'trucks_inside', (select count(*) from public.truck_visits where exited_at is null and canceled_at is null),
    'entries_today', (select count(*) from public.truck_visits where entered_at >= v_start and entered_at < v_end),
    'exits_today', (select count(*) from public.truck_visits where exited_at >= v_start and exited_at < v_end and canceled_at is null),
    'cancellations_today', (select count(*) from public.truck_visits where canceled_at >= v_start and canceled_at < v_end),
    'needs_engin_inside', (select count(*) from public.truck_visits where exited_at is null and canceled_at is null and engin_at is null and entry_kind = 'loaded'),
    'twin_today', (select count(*) from public.truck_visits where entered_at >= v_start and entered_at < v_end and is_twin = true),
    'total_containers_today', (select count(*) from public.truck_visits where entered_at >= v_start and entered_at < v_end and container_number is not null) +
                              (select count(*) from public.truck_visits where entered_at >= v_start and entered_at < v_end and is_twin = true and container_number_2 is not null),
    'armateurs_breakdown', (
      select coalesce(jsonb_agg(jsonb_build_object('name', armateur, 'count', cnt)), '[]'::jsonb)
      from (
        select coalesce(nullif(armateur_id, ''), 'AUTRE') as armateur, count(*) as cnt
        from public.truck_visits
        where entered_at >= v_start and entered_at < v_end
        group by 1 order by cnt desc limit 8
      ) arm_stats
    ),
    'hourly_entries', (
      select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'count', coalesce(cnt, 0)) order by h), '[]'::jsonb)
      from generate_series(0, 23) h
      left join (
        select extract(hour from entered_at at time zone 'Africa/Casablanca')::int as eh, count(*) as cnt
        from public.truck_visits
        where entered_at >= v_start and entered_at < v_end
        group by 1
      ) hr on hr.eh = h
    ),
    'hourly_exits', (
      select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'count', coalesce(cnt, 0)) order by h), '[]'::jsonb)
      from generate_series(0, 23) h
      left join (
        select extract(hour from exited_at at time zone 'Africa/Casablanca')::int as xh, count(*) as cnt
        from public.truck_visits
        where exited_at >= v_start and exited_at < v_end and canceled_at is null
        group by 1
      ) hr on hr.xh = h
    ),
    'recent_visits', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', v.id,
        'truck_plate', v.plate,
        'driver_cin', v.driver_cin,
        'entry_kind', v.entry_kind,
        'container_number', v.container_number,
        'container_number_2', v.container_number_2,
        'is_twin', v.is_twin,
        'iso_code', v.iso_code,
        'armateur', v.armateur_id,
        'entered_at', v.entered_at,
        'exited_at', v.exited_at,
        'canceled_at', v.canceled_at,
        'cancel_reason', v.cancel_reason,
        'status', case
          when v.canceled_at is not null then 'ANNULE'
          when v.exited_at is not null then 'SORTI'
          else 'AU_PARC'
        end
      ) order by v.entered_at desc), '[]'::jsonb)
      from (select * from public.truck_visits order by entered_at desc limit 100) v
    ),
    'agents_count', (select count(*) from public.profiles where active = true)
  ) into v_res;
  return v_res;
end; $$;

grant execute on function public.admin_dashboard_kpis(date) to authenticated, anon;
