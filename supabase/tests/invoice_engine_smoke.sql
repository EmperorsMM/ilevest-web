-- ============================================================================
-- Invoice engine smoke test (self-contained; rolled back)
--   - per-line VAT math incl. apply / exempt / out_of_scope government lines, totals
--   - government lines carry receipt-or-refund by default
--   - drafts are Ops-only; buyers see only their own ISSUED invoice; others none
--   - only Ops may create/edit/issue
--   - issuing flips state, creates the payment row (svc/gov/vat), fires "quote ready"
--   - paying (confirm_payment) fans the order out into live checks
-- Run against a DB built from migrations.
-- ============================================================================
\set ON_ERROR_STOP on
begin;

insert into public.app_user(id, name, email_or_phone) values
  ('a0000000-0000-0000-0000-0000000000f1','Client F','f1@test'),
  ('a0000000-0000-0000-0000-0000000000f2','Ops F','f2@test'),
  ('a0000000-0000-0000-0000-0000000000f3','Other F','f3@test');
insert into public.user_role(user_id, role) values
  ('a0000000-0000-0000-0000-0000000000f1','client'),
  ('a0000000-0000-0000-0000-0000000000f2','ops'),
  ('a0000000-0000-0000-0000-0000000000f3','client');

-- client creates an order (essential = 2 services)
do $$
declare oid uuid;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000f1', true);
  oid := public.create_order('essential', null, 'Lagos', 'Eti-Osa', 'Ikoyi', null, 'LA', null);
  -- stash for later steps
  create temp table _t(order_id uuid) on commit drop;
  insert into _t values (oid);
end $$;

-- Ops builds the invoice: 1 service fee (apply) + 3 government lines (apply / exempt / out_of_scope)
do $$
declare oid uuid; res jsonb; ln jsonb;
begin
  select order_id into oid from _t;
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000f2', true);

  res := public.ops_set_invoice_lines(oid, jsonb_build_array(
    jsonb_build_object('kind','service_fee','service_code','C1-LR-01','description','Title & Ownership Search','amount',50000),
    jsonb_build_object('kind','government_fee','description','Registry search fee','amount',20000,'vat_treatment','apply'),
    jsonb_build_object('kind','government_fee','description','Statutory stamp','amount',10000,'vat_treatment','exempt'),
    jsonb_build_object('kind','government_fee','description','Disbursement','amount',5000,'vat_treatment','out_of_scope')
  ));

  -- service VAT = 50000*7.5% = 3750 ; gov apply VAT = 20000*7.5% = 1500 ; others 0
  if (res->>'service_subtotal')::numeric <> 50000 then raise exception 'service_subtotal=%',(res->>'service_subtotal'); end if;
  if (res->>'government_subtotal')::numeric <> 35000 then raise exception 'government_subtotal=%',(res->>'government_subtotal'); end if;
  if (res->>'vat_total')::numeric <> 5250 then raise exception 'vat_total=% (expected 5250)',(res->>'vat_total'); end if;
  if (res->>'grand_total')::numeric <> 90250 then raise exception 'grand_total=% (expected 90250)',(res->>'grand_total'); end if;

  -- per-line: the exempt + out_of_scope government lines must have zero VAT
  if exists (select 1 from jsonb_array_elements(res->'lines') e
             where e->>'vat_treatment' in ('exempt','out_of_scope') and (e->>'vat_amount')::numeric <> 0) then
    raise exception 'exempt/out_of_scope line carried VAT';
  end if;
  -- government lines default to requiring a receipt (receipt-or-refund); service line does not
  if exists (select 1 from jsonb_array_elements(res->'lines') e where e->>'kind'='government_fee' and (e->>'requires_receipt')::bool is not true) then
    raise exception 'a government line did not require a receipt by default';
  end if;
  if exists (select 1 from jsonb_array_elements(res->'lines') e where e->>'kind'='service_fee' and (e->>'requires_receipt')::bool is true) then
    raise exception 'service line should not require a receipt';
  end if;

  raise notice 'PASS: per-line VAT (apply/exempt/out_of_scope) + totals + receipt-or-refund correct';
end $$;

-- drafts are Ops-only; the buyer cannot see a draft
do $$
declare oid uuid; as_buyer jsonb; as_ops jsonb;
begin
  select order_id into oid from _t;

  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000f1', true);
  as_buyer := public.get_invoice(oid);
  if (as_buyer->>'exists')::bool is true then raise exception 'buyer must not see a draft invoice'; end if;

  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000f2', true);
  as_ops := public.get_invoice(oid);
  if (as_ops->>'exists')::bool is not true then raise exception 'ops should see the draft'; end if;

  raise notice 'PASS: drafts are visible to Ops only, not the buyer';
end $$;

-- only Ops may edit / issue
do $$
declare oid uuid;
begin
  select order_id into oid from _t;
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000f1', true);  -- a client, not ops
  begin
    perform public.ops_set_invoice_lines(oid, '[]'::jsonb);
    raise exception 'FAIL: non-ops edited an invoice';
  exception when others then
    if sqlerrm not like '%Ops/Admin%' then raise exception 'wrong gate error: %', sqlerrm; end if;
  end;
  begin
    perform public.ops_issue_invoice(oid);
    raise exception 'FAIL: non-ops issued an invoice';
  exception when others then
    if sqlerrm not like '%Ops/Admin%' then raise exception 'wrong gate error: %', sqlerrm; end if;
  end;
  raise notice 'PASS: only Ops may edit/issue';
end $$;

-- issue: flips state, creates payment row, fires "quote ready"
do $$
declare oid uuid; res jsonb; psvc numeric; pgov numeric; pvat numeric;
begin
  select order_id into oid from _t;
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000f2', true);
  res := public.ops_issue_invoice(oid);
  if res->>'status' <> 'issued' then raise exception 'issue did not set status issued'; end if;

  select service_fee, government_fee_total, vat_total into psvc, pgov, pvat from public.payment where order_id = oid;
  if psvc <> 50000 or pgov <> 35000 or pvat <> 5250 then
    raise exception 'payment row wrong: svc=% gov=% vat=%', psvc, pgov, pvat;
  end if;

  if not exists (select 1 from public.notification where event='quote_ready' and order_id=oid
                 and user_id='a0000000-0000-0000-0000-0000000000f1') then
    raise exception 'issuing did not enqueue quote_ready for the buyer';
  end if;

  raise notice 'PASS: issuing flips state, creates the payment row, and fires quote_ready';
end $$;

-- after issue: buyer sees their issued invoice; a different client does not
do $$
declare oid uuid; mine jsonb; theirs jsonb;
begin
  select order_id into oid from _t;

  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000f1', true);
  mine := public.get_invoice(oid);
  if (mine->>'exists')::bool is not true or mine->>'status' <> 'issued' then raise exception 'buyer should now see the issued invoice'; end if;
  if (mine->>'grand_total')::numeric <> 90250 then raise exception 'buyer total wrong'; end if;
  if (mine->>'paid')::bool is not false then raise exception 'should be unpaid before payment'; end if;

  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000f3', true);
  theirs := public.get_invoice(oid);
  if (theirs->>'exists')::bool is true then raise exception 'a different client must not see the invoice'; end if;

  raise notice 'PASS: buyer sees own issued invoice; a different client sees nothing';
end $$;

-- paying fans the order out into live checks
do $$
declare oid uuid; r jsonb; nchecks int;
begin
  select order_id into oid from _t;
  -- the webhook calls confirm_payment as the service role; here we call it directly
  r := public.confirm_payment(oid, 'paystack_ref_test_123');
  if (r->>'checks_created')::int <> 2 then raise exception 'expected 2 checks created, got %', (r->>'checks_created'); end if;

  select count(*) into nchecks from public.check_item where order_id = oid;
  if nchecks <> 2 then raise exception 'order should have 2 checks after payment, has %', nchecks; end if;

  -- and the buyer's invoice now reads paid
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000f1', true);
  if (public.get_invoice(oid)->>'paid')::bool is not true then raise exception 'invoice should read paid after confirm_payment'; end if;

  raise notice 'PASS: paying (confirm_payment) fans out into live checks; invoice reads paid';
end $$;

rollback;
