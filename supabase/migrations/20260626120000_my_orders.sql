-- ============================================================================
-- Client dashboard read-model: my_orders()
-- ----------------------------------------------------------------------------
-- Returns the CURRENT user's orders as a JSON array, each summarised for the
-- dashboard list: bundle, when placed, whether it has been paid, how many
-- checks exist and how many are complete, whether the whole order is ready,
-- and the RED-dominant headline verdict.
--
-- Boundary: scoped by `where client_id = app.current_user_id()`. The detail
-- view uses order_tracking(id); this is the at-a-glance list. SECURITY DEFINER
-- (like order_tracking) so it can read across the joined tables, but it only
-- ever returns rows owned by the caller — a different client sees their own
-- orders only, and an unauthenticated caller sees an empty list.
-- ============================================================================

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
    return '[]'::jsonb;          -- no identity -> nothing to show
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
