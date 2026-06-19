-- =============================================================================
-- 0008  Verdict (append-only; one per check)
-- =============================================================================
-- Decision C / J-5. A check finalizes with exactly one honest verdict. Append-only:
-- a correction is a NEW verification that supersedes the old (see commitment), never an edit.

create table public.verdict (
  id          uuid primary key default gen_random_uuid(),
  check_id    uuid not null unique references public.check_item(id) on delete restrict,
  colour      public.verdict_colour not null,
  explanation text,                       -- plain-English; never the words "safe to buy"
  as_at       date not null default current_date,
  created_at  timestamptz not null default now()
);
comment on table public.verdict is 'The finding for a check (Decision C). Append-only; one per check; corrections supersede.';
alter table public.verdict enable row level security;

create trigger verdict_block_modification
  before update or delete on public.verdict
  for each row execute function app.tg_block_modification();

-- DERIVED headline verdict for an order. One RED dominates the headline (Decision J-5).
-- Defined here (not in 0005) because it reads the verdict table created just above.
create or replace function app.order_headline_verdict(p_order uuid)
returns public.verdict_colour language sql stable security definer set search_path = '' as $$
  select case
    when bool_or(v.colour = 'red')        then 'red'::public.verdict_colour
    when bool_or(v.colour = 'amber')      then 'amber'::public.verdict_colour
    when bool_or(v.colour = 'unresolved') then 'unresolved'::public.verdict_colour
    when count(*) > 0 and bool_and(v.colour = 'green') then 'green'::public.verdict_colour
    else null
  end
  from public.check_item c
  join public.verdict v on v.check_id = c.id
  where c.order_id = p_order;
$$;
