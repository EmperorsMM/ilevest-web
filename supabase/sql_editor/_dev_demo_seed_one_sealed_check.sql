-- =============================================================================
-- Ilevest — DEV demo seed: one sealed check, to exercise the end-to-end anchor
-- (for the Supabase SQL Editor on ilevest-dev). Creates a single finalized, sealed
-- check so the next anchor run has a real fingerprint to fold into a Merkle root.
-- Idempotent: re-running will not double-seal. NOTE: finalized records are immutable
-- by design — this demo data persists on dev (that is fine for a dev environment).
-- =============================================================================
do $$
declare v_check uuid; v_state text;
begin
  -- demo users + roles (decoupled from auth; ids are arbitrary)
  insert into public.app_user(id,name,email_or_phone) values
    ('22222222-2222-2222-2222-222222222222','Demo Ops','demo-ops@ilevest.test'),
    ('33333333-3333-3333-3333-333333333333','Demo Reviewer','demo-rev@ilevest.test'),
    ('44444444-4444-4444-4444-444444444444','Demo Partner','demo-partner@ilevest.test'),
    ('66666666-6666-6666-6666-666666666666','Demo Client','demo-client@ilevest.test')
  on conflict do nothing;
  insert into public.user_role(user_id,role) values
    ('22222222-2222-2222-2222-222222222222','ops'),
    ('33333333-3333-3333-3333-333333333333','reviewer'),
    ('44444444-4444-4444-4444-444444444444','partner'),
    ('66666666-6666-6666-6666-666666666666','client')
  on conflict do nothing;

  -- a property + an a-la-carte order for one service, paid -> fans out one check
  insert into public.property(id,lga,state,locality)
    values ('aa000000-0000-0000-0000-0000000000d1','Eti-Osa','Lagos','Ikoyi') on conflict do nothing;
  insert into public.order_matter(id,client_id,property_id,bundle)
    values ('cc000000-0000-0000-0000-0000000000d1',
            '66666666-6666-6666-6666-666666666666',
            'aa000000-0000-0000-0000-0000000000d1','ala_carte') on conflict do nothing;
  insert into public.order_line(order_id,service_code)
    values ('cc000000-0000-0000-0000-0000000000d1','C1-LR-01') on conflict do nothing;
  insert into public.payment(order_id,service_fee,government_fee_total)
    values ('cc000000-0000-0000-0000-0000000000d1', 50000, 0) on conflict do nothing;
  perform public.confirm_payment('cc000000-0000-0000-0000-0000000000d1','demo_anchor_ref');

  select id, state into v_check, v_state from public.check_item
    where order_id='cc000000-0000-0000-0000-0000000000d1' and service_code='C1-LR-01';

  if v_state = 'finalized' then
    raise notice 'Demo check already sealed: %', v_check;
  else
    -- Ops assigns -> assigned worker progresses -> Reviewer seals
    perform set_config('app.user_id','22222222-2222-2222-2222-222222222222', true);
    perform public.assign_check(v_check, '44444444-4444-4444-4444-444444444444');
    perform set_config('app.user_id','44444444-4444-4444-4444-444444444444', true);
    update public.check_item set state='in_progress' where id=v_check;
    update public.check_item set state='in_review'  where id=v_check;
    perform set_config('app.user_id','33333333-3333-3333-3333-333333333333', true);
    perform public.seal_check(v_check, 'green', 'Demo: title clear — end-to-end anchor test');
    raise notice 'Sealed demo check: %', v_check;
  end if;
end $$;

-- the sealed check id — use it in the verify-certificate URL after anchoring
select id as sealed_check_id, state, service_code, sealed_at
from public.check_item
where order_id='cc000000-0000-0000-0000-0000000000d1' and service_code='C1-LR-01';
