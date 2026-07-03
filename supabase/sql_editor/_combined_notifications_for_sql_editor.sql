-- ============================================================================
-- COMBINED for Supabase SQL Editor — Notifications spine
-- (outbox table + enqueue + order_received/verdict_ready hooks + quote_ready helper)
-- Idempotent. Safe to run on the live project.
-- ============================================================================
begin;

-- ============================================================================
-- Notifications — the spine (outbox + enqueue + event hooks)
-- ----------------------------------------------------------------------------
-- An outbox the workflow writes to. Events enqueue a row (what to notify, to
-- whom, about which order); a separate dispatch worker renders and delivers it
-- through a swappable channel adapter (email first, WhatsApp later) and marks
-- it sent. No message text or contact detail is stored here — only references;
-- the recipient and the words are resolved at send time. Idempotent: at most
-- one notification per (event, order), so retries never double-send.
--
-- Events wired now: order_received (on order creation) and verdict_ready (when
-- sealing completes the last check of an order). quote_ready has its enqueue
-- helper ready for the Ops invoice engine to call when that is built.
-- ============================================================================

create table if not exists public.notification (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.app_user(id) on delete cascade,
  event       text not null check (event in ('order_received','quote_ready','verdict_ready')),
  order_id    uuid references public.order_matter(id) on delete cascade,
  channel     text not null default 'email' check (channel in ('email','whatsapp')),
  status      text not null default 'pending' check (status in ('pending','sent','failed')),
  attempts    int  not null default 0,
  last_error  text,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz,
  unique (event, order_id)
);

create index if not exists notification_pending_idx on public.notification (created_at) where status = 'pending';

alter table public.notification enable row level security;

-- The buyer may read their own notifications (for an in-app inbox later); staff
-- may read all. No client writes — enqueue is the only writer (SECURITY DEFINER);
-- the dispatch worker updates status via the service role (bypasses RLS).
drop policy if exists notification_select on public.notification;
create policy notification_select on public.notification
  for select to authenticated
  using (user_id = app.current_user_id() or app.is_staff());

grant select on public.notification to authenticated;

-- ---- enqueue (the single write path) ---------------------------------------
create or replace function app.enqueue_notification(
  p_user     uuid,
  p_event    text,
  p_order    uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if p_user is null then
    return;  -- no recipient (e.g. anonymized account) -> nothing to enqueue
  end if;
  if p_event not in ('order_received','quote_ready','verdict_ready') then
    raise exception 'unknown notification event: %', p_event;
  end if;

  insert into public.notification(user_id, event, order_id, channel, metadata)
  values (p_user, p_event, p_order, 'email', coalesce(p_metadata, '{}'::jsonb))
  on conflict (event, order_id) do nothing;

  if found then
    perform app.write_audit(
      p_entity_type => 'notification',
      p_entity_id   => p_order,
      p_action      => 'enqueued',
      p_metadata    => jsonb_build_object('event', p_event)
    );
  end if;
end;
$$;

-- Convenience hook for the future Ops invoice engine.
create or replace function app.enqueue_quote_ready(p_order uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  perform app.enqueue_notification(
    (select client_id from public.order_matter where id = p_order),
    'quote_ready', p_order, '{}'::jsonb);
end;
$$;

-- ============================================================================
-- Wire the events into existing write paths (bodies reproduced + one line added)
-- ============================================================================

-- order_received: enqueue when an order is created
create or replace function public.create_order(
  p_bundle     text,
  p_services   text[] default null,
  p_state      text   default null,
  p_lga        text   default null,
  p_locality   text   default null,
  p_details    text   default null,
  p_state_code text   default null,
  p_seller     text   default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  uid      uuid := app.current_user_id();
  v_bundle order_bundle;
  v_codes  text[];
  v_prop   uuid;
  v_party  uuid;
  v_order  uuid;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  v_bundle := p_bundle::order_bundle;

  if v_bundle = 'ala_carte' then
    select array_agg(distinct c) into v_codes
    from unnest(coalesce(p_services, '{}'::text[])) as c;
  else
    select array_agg(service_code) into v_codes
    from public.bundle_service where bundle = v_bundle;
  end if;

  if v_codes is null or cardinality(v_codes) = 0 then
    raise exception 'no services selected';
  end if;

  if exists (
    select 1 from unnest(v_codes) as c
    where not exists (select 1 from public.service_catalogue s where s.code = c)
  ) then
    raise exception 'unknown service code in selection';
  end if;

  if coalesce(p_state, p_state_code, p_lga, p_locality, p_details) is not null then
    insert into public.property(state, state_code, lga, locality, identifying_details)
    values (
      nullif(btrim(p_state), ''), nullif(btrim(p_state_code), ''),
      nullif(btrim(p_lga), ''), nullif(btrim(p_locality), ''), nullif(btrim(p_details), '')
    )
    returning id into v_prop;
  end if;

  if nullif(btrim(p_seller), '') is not null then
    insert into public.party_seller(name) values (btrim(p_seller)) returning id into v_party;
  end if;

  insert into public.order_matter(client_id, property_id, party_id, bundle)
  values (uid, v_prop, v_party, v_bundle)
  returning id into v_order;

  insert into public.order_line(order_id, service_code)
  select v_order, c from unnest(v_codes) as c;

  perform app.write_audit(
    p_entity_type => 'order', p_entity_id => v_order, p_action => 'created',
    p_metadata => jsonb_build_object('bundle', v_bundle, 'service_count', cardinality(v_codes), 'has_seller', v_party is not null)
  );

  -- NEW: tell the buyer we've received their request
  perform app.enqueue_notification(uid, 'order_received', v_order, jsonb_build_object('bundle', v_bundle));

  return v_order;
end;
$$;

-- verdict_ready: enqueue when sealing completes the last check of an order
create or replace function public.seal_check(p_check uuid, p_colour verdict_colour, p_explanation text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v_canon text; v_hash text; v_prev text; v_commit uuid; v_order uuid; v_service text;
begin
  if not app.is_reviewer() then
    raise exception 'Only a Reviewer/Ops/Admin may seal a check.' using errcode = 'check_violation';
  end if;
  select order_id, service_code into v_order, v_service from public.check_item where id = p_check;
  if not found then raise exception 'Check % not found.', p_check using errcode = 'no_data_found'; end if;

  insert into public.verdict(check_id, colour, explanation) values (p_check, p_colour, p_explanation);
  update public.check_item set state = 'finalized' where id = p_check;  -- FSM trigger validates reviewer/ops

  select p_check::text || '|' || coalesce(v_service,'') || '|' || p_colour::text || '|' || coalesce(p_explanation,'')
         || '|' || coalesce(string_agg(e.content_hash, ',' order by e.id), '')
         || '|' || coalesce(v_order::text,'')
    into v_canon
  from public.evidence_item e where e.check_id = p_check;

  v_hash := encode(digest(v_canon, 'sha256'), 'hex');

  insert into public.commitment(check_id, content_hash) values (p_check, v_hash)
    returning prev_hash into v_prev;
  select id into v_commit from public.commitment where check_id = p_check;

  -- NEW: if this seal completes the order, tell the buyer their verdict is ready
  if not exists (select 1 from public.check_item where order_id = v_order and state <> 'finalized') then
    perform app.enqueue_notification(
      (select client_id from public.order_matter where id = v_order),
      'verdict_ready', v_order, '{}'::jsonb);
  end if;

  return jsonb_build_object('check_id', p_check, 'verdict', p_colour,
                            'content_hash', v_hash, 'prev_hash', v_prev, 'commitment_id', v_commit);
end; $function$;

commit;
