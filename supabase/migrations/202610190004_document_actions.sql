-- Record user access to private PDF documents without claiming physical printing succeeded.
begin;
create table public.document_actions (
  id bigint generated always as identity primary key,
  document_id uuid not null references public.generated_documents(id),
  actor_id uuid not null references public.profiles(id),
  action text not null check(action in
    ('PREVIEW_REQUESTED','SHARE_REQUESTED','PRINT_DIALOG_REQUESTED','DIRECT_PRINT_REQUESTED',
     'BRIDGE_ARCHIVE_REQUESTED','BRIDGE_PRINT_REQUESTED')),
  occurred_at timestamptz not null default now()
);
create index document_actions_document_idx on public.document_actions(document_id,occurred_at);
grant select on public.document_actions to authenticated;
revoke insert,update,delete on public.document_actions from anon,authenticated;
alter table public.document_actions enable row level security;
create policy document_actions_admin_or_self on public.document_actions for select to authenticated
  using(public.can_do('admin') or (actor_id=auth.uid() and public.can_do('read')));

create or replace function public.record_document_action(p_document uuid,p_action text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid();
begin
  if not public.can_do('read') then raise exception 'permission denied' using errcode='42501'; end if;
  if p_action not in
      ('PREVIEW_REQUESTED','SHARE_REQUESTED','PRINT_DIALOG_REQUESTED','DIRECT_PRINT_REQUESTED',
     'BRIDGE_ARCHIVE_REQUESTED','BRIDGE_PRINT_REQUESTED') then
    raise exception 'invalid document action';
  end if;
  if not exists(select 1 from public.generated_documents where id=p_document) then
    raise exception 'document unavailable';
  end if;
  insert into public.document_actions(document_id,actor_id,action)
    values(p_document,v_actor,p_action);
end; $$;
revoke all on function public.record_document_action(uuid,text) from public,anon;
grant execute on function public.record_document_action(uuid,text) to authenticated;
commit;


