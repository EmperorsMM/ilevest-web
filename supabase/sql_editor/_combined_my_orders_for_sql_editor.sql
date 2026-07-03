-- ============================================================================
-- COMBINED for Supabase SQL Editor — Client dashboard read-model: my_orders()
-- Idempotent (create or replace). Safe to run on the live project.
-- ============================================================================
begin;

create or replace function public.my_orders()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  uid uuid := app.current_user_id();
  v   jsonb;
begin
  if uid is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(s.row order by s.created_at desc), '[]'::jsonb)
  into v
  from (
    select
      jsonb_build_object(
        'order_id',         o.id,
        'bundle',           o.bundle,
        'created_at',       o.created_at,
        'paid',             exists (
                              select 1 from public.payment p
                              where p.order_id = o.id and p.webhook_verified
                            ),
        'total_checks',     count(ci.id),
        'ready_checks',     count(ci.id) filter (where ci.state in ('finalized','rejected')),
        'ready',            (count(ci.id) > 0
                              and count(ci.id) filter (where ci.state not in ('finalized','rejected')) = 0),
        'headline_verdict', app.order_headline_verdict(o.id)
      ) as row,
      o.created_at
    from public.order_matter o
    left join public.check_item ci on ci.order_id = o.id
    where o.client_id = uid
    group by o.id, o.bundle, o.created_at
  ) s;

  return v;
end;
$$;

revoke all on function public.my_orders() from public;
grant execute on function public.my_orders() to authenticated;

comment on function public.my_orders() is
  'Owner-scoped summary list of the caller''s orders for the client dashboard. Empty for unauthenticated callers.';

commit;
