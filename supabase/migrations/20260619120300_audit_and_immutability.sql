-- =============================================================================
-- 0003  The audit spine + reusable immutability triggers
-- =============================================================================
-- Audit Event is "the spine of the database" (Section 13): every actor, action,
-- from-state -> to-state, timestamp and reason, append-only and never edited.

create table public.audit_event (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references public.app_user(id),     -- who acted (null = system/automated)
  entity_type text not null,                            -- 'check','order','user_role','government_fee',...
  entity_id   uuid,                                     -- the affected row
  check_id    uuid,                                     -- convenience FK for the common case (added after check_item exists)
  action      text not null,                            -- 'created','state_change','role_granted',...
  from_state  text,
  to_state    text,
  reason      text,
  metadata    jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
comment on table public.audit_event is 'Append-only audit spine (Decision G). Never updated or deleted. Written by SECURITY DEFINER triggers and by service-role processes.';
create index audit_event_entity_idx on public.audit_event (entity_type, entity_id);
create index audit_event_check_idx  on public.audit_event (check_id);
create index audit_event_actor_idx  on public.audit_event (actor_id);
alter table public.audit_event enable row level security;

-- Reusable guard: a table that may never be UPDATEd or DELETEd (hard append-only).
-- A trigger (not just REVOKE) is used because triggers fire regardless of role, so this
-- holds even against the table owner and the bypass-RLS service role.
create or replace function app.tg_block_modification()
returns trigger language plpgsql as $$
begin
  raise exception 'Table % is append-only; % is not permitted (immutable by policy).',
    tg_table_name, lower(tg_op)
    using errcode = 'check_violation';
end;
$$;

-- audit_event itself is append-only.
create trigger audit_event_block_modification
  before update or delete on public.audit_event
  for each row execute function app.tg_block_modification();

-- Generic helper to write an audit row from app/edge code (runs as definer; bypasses RLS).
create or replace function app.write_audit(
  p_entity_type text, p_entity_id uuid, p_action text,
  p_from text default null, p_to text default null,
  p_reason text default null, p_check_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  insert into public.audit_event(actor_id, entity_type, entity_id, check_id, action, from_state, to_state, reason, metadata)
  values (app.current_user_id(), p_entity_type, p_entity_id, p_check_id, p_action, p_from, p_to, p_reason, p_metadata)
  returning id into v_id;
  return v_id;
end;
$$;

-- Audit role grants/revocations on user_role.
create or replace function app.tg_audit_user_role()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform app.write_audit('user_role', new.user_id, 'role_granted', null, new.role::text, null, null,
                            jsonb_build_object('role', new.role));
    return new;
  elsif tg_op = 'DELETE' then
    perform app.write_audit('user_role', old.user_id, 'role_revoked', old.role::text, null, null, null,
                            jsonb_build_object('role', old.role));
    return old;
  end if;
  return null;
end;
$$;

create trigger user_role_audit
  after insert or delete on public.user_role
  for each row execute function app.tg_audit_user_role();
