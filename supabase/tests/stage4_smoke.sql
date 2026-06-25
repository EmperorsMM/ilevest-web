-- =============================================================================
-- Ilevest — Build Stage 4 smoke test (Client Portal: buyer read-model + documents)
-- =============================================================================
-- Run as SUPERUSER against a DB with ALL migrations applied. No stored prices (Ops invoices
-- per request). Proves: the anon document checklist; the buyer status projection (states +
-- verdicts + readiness, owner/staff only); allow-ZERO documents; and the buyer-document RLS
-- boundary — exercised under `set role authenticated` so the policies actually apply.
\set ON_ERROR_STOP on
set client_min_messages = notice;
set search_path = public, extensions, pg_temp;

\set ops      '''22222222-2222-2222-2222-222222222222'''
\set reviewer '''33333333-3333-3333-3333-333333333333'''
\set partner1 '''44444444-4444-4444-4444-444444444444'''
\set client1  '''66666666-6666-6666-6666-666666666666'''
\set client2  '''77777777-7777-7777-7777-777777777777'''

\echo ''
\echo '################ PART A — document checklist (seeded, de-duplicated union) + prices gone ################'
set role anon;
-- per-service: C1-LR-01 has 4 listed documents, Helpful ranked first
select set_config('t.dc1', public.document_checklist(array['C1-LR-01'])::text, false);
do $$ declare d jsonb := current_setting('t.dc1')::jsonb; begin
  if jsonb_array_length(d) <> 4 then raise exception 'FAIL: C1-LR-01 should have 4 checklist items, got %', jsonb_array_length(d); end if;
  if (d->0->>'tier') <> 'helpful' then raise exception 'FAIL: Helpful items must rank first'; end if;
  raise notice 'PASS: per-service checklist returns the seeded items with Helpful first';
end $$;
-- a selection spanning two services composes ONE consolidated list and de-duplicates the shared doc
select set_config('t.dc2', public.document_checklist(array['C1-LR-01','C1-FD-01'])::text, false);
do $$ declare n int := jsonb_array_length(current_setting('t.dc2')::jsonb); begin
  -- LR-01 (4) + FD-01 (4) share "Survey plan, if available" exactly -> 7 unique
  if n <> 7 then raise exception 'FAIL: LR-01+FD-01 should de-duplicate to 7, got %', n; end if;
  raise notice 'PASS: a multi-service selection yields one consolidated, de-duplicated checklist (7 from 8)';
end $$;
reset role;
do $$ begin
  if to_regprocedure('public.quote_selection(text[])') is not null then raise exception 'FAIL: quote_selection must be gone (no stored prices)'; end if;
  raise notice 'PASS: no stored-price quote exists (selection routes to Ops invoicing)';
end $$;

\echo ''
\echo '################ PART B — order_tracking (buyer status, ownership-scoped, allow-zero docs) ################'
insert into public.app_user(id,name,email_or_phone) values
  ('22222222-2222-2222-2222-222222222222','Ops','o@x'),
  ('33333333-3333-3333-3333-333333333333','Reviewer','r@x'),
  ('44444444-4444-4444-4444-444444444444','Partner One','p1@x'),
  ('66666666-6666-6666-6666-666666666666','Client One','c1@x'),
  ('77777777-7777-7777-7777-777777777777','Client Two','c2@x');
insert into public.user_role(user_id,role) values
  ('22222222-2222-2222-2222-222222222222','ops'),('33333333-3333-3333-3333-333333333333','reviewer'),
  ('44444444-4444-4444-4444-444444444444','partner'),('66666666-6666-6666-6666-666666666666','client'),
  ('77777777-7777-7777-7777-777777777777','client');
set app.user_id = :ops;
insert into public.property(id,lga,state,locality) values ('aa000000-0000-0000-0000-0000000000e1','Eti-Osa','Lagos','Ikoyi');
insert into public.order_matter(id,client_id,property_id,bundle) values ('cc000000-0000-0000-0000-0000000000e1',:client1,'aa000000-0000-0000-0000-0000000000e1','ala_carte');
insert into public.order_line(order_id,service_code) values
  ('cc000000-0000-0000-0000-0000000000e1','C1-LR-01'),
  ('cc000000-0000-0000-0000-0000000000e1','C1-LR-02'),
  ('cc000000-0000-0000-0000-0000000000e1','C1-LR-03');
insert into public.payment(order_id,service_fee,government_fee_total) values ('cc000000-0000-0000-0000-0000000000e1', 60000, 15000);
reset role;
select public.confirm_payment('cc000000-0000-0000-0000-0000000000e1','ref_portal');
select set_config('t.c1',(select id::text from public.check_item where order_id='cc000000-0000-0000-0000-0000000000e1' and service_code='C1-LR-01'),false);
select set_config('t.c2',(select id::text from public.check_item where order_id='cc000000-0000-0000-0000-0000000000e1' and service_code='C1-LR-02'),false);
-- LR-01 -> sealed (Ready, green); LR-02 -> in_progress (In Progress); LR-03 -> initiated (Assigned)
set app.user_id = :ops;      select public.assign_check(current_setting('t.c1')::uuid, :partner1);
set app.user_id = :partner1; update public.check_item set state='in_progress' where id=current_setting('t.c1')::uuid;
                             update public.check_item set state='in_review'  where id=current_setting('t.c1')::uuid;
set app.user_id = :reviewer; select public.seal_check(current_setting('t.c1')::uuid,'green','clear');
set app.user_id = :ops;      select public.assign_check(current_setting('t.c2')::uuid, :partner1);
set app.user_id = :partner1; update public.check_item set state='in_progress' where id=current_setting('t.c2')::uuid;
reset role;

set app.user_id = :client1;
select set_config('t.ot', public.order_tracking('cc000000-0000-0000-0000-0000000000e1')::text, false);
do $$ declare r jsonb := current_setting('t.ot')::jsonb; m jsonb; begin
  if not (r->>'visible')::boolean then raise exception 'FAIL: the owner should see the order'; end if;
  if (r->>'ready')::boolean then raise exception 'FAIL: not all finalized -> ready=false'; end if;
  if jsonb_array_length(r->'checks') <> 3 then raise exception 'FAIL: should list 3 checks'; end if;
  if jsonb_array_length(r->'documents') <> 0 then raise exception 'FAIL: order with no uploads must still track (allow-zero), documents=[]'; end if;
  select jsonb_object_agg(c->>'service_code', c->>'status') into m from jsonb_array_elements(r->'checks') c;
  if m->>'C1-LR-01' <> 'Ready' or m->>'C1-LR-02' <> 'In Progress' or m->>'C1-LR-03' <> 'Assigned'
    then raise exception 'FAIL: buyer states wrong: %', m; end if;
  raise notice 'PASS: owner sees Ready / In Progress / Assigned, ready=false, and allow-zero documents=[]';
end $$;
do $$ declare r jsonb := current_setting('t.ot')::jsonb; c jsonb; begin
  select cc into c from jsonb_array_elements(r->'checks') cc where cc->>'service_code'='C1-LR-01';
  if c->>'verdict' <> 'green' then raise exception 'FAIL: sealed LR-01 should surface green'; end if;
  raise notice 'PASS: the sealed check surfaces its colour verdict to the buyer (green)';
end $$;
reset role;
set app.user_id = :client2;
do $$ begin
  if (public.order_tracking('cc000000-0000-0000-0000-0000000000e1')->>'visible')::boolean
    then raise exception 'FAIL: a non-owner must NOT see the order'; end if;
  raise notice 'PASS: a different client cannot see someone else''s order';
end $$;
reset role;

\echo ''
\echo '################ PART C — buyer_document RLS (exercised as authenticated) ################'
-- OWNER uploads one document to their own order
set role authenticated; set app.user_id = :client1;
insert into public.buyer_document(order_id, uploaded_by, doc_type, label, storage_ref, content_type)
  values ('cc000000-0000-0000-0000-0000000000e1', :client1, 'receipt', 'My purchase receipt', 'order/e1/receipt.pdf', 'application/pdf');
do $$ declare n int; begin
  select count(*) into n from public.buyer_document where order_id='cc000000-0000-0000-0000-0000000000e1';
  if n <> 1 then raise exception 'FAIL: owner should see their 1 uploaded document, saw %', n; end if;
  raise notice 'PASS: the owner can upload and see their own document (RLS insert + select)';
end $$;
reset role;
-- it now shows in the buyer status (label/type only, never the storage path)
set app.user_id = :client1;
do $$ declare r jsonb := public.order_tracking('cc000000-0000-0000-0000-0000000000e1'); begin
  if jsonb_array_length(r->'documents') <> 1 then raise exception 'FAIL: the uploaded doc should appear in tracking'; end if;
  if (r->'documents'->0) ? 'storage_ref' then raise exception 'FAIL: the storage path must never be exposed to the buyer'; end if;
  raise notice 'PASS: the document appears in tracking by label, with no storage path exposed';
end $$;
reset role;
-- a DIFFERENT client sees none of it, and cannot upload to the order
set role authenticated; set app.user_id = :client2;
do $$ declare n int; begin
  select count(*) into n from public.buyer_document where order_id='cc000000-0000-0000-0000-0000000000e1';
  if n <> 0 then raise exception 'FAIL: a non-owner must see 0 documents, saw %', n; end if;
  raise notice 'PASS: a non-owner sees none of the order''s documents (RLS select)';
end $$;
do $$ begin
  begin
    insert into public.buyer_document(order_id, uploaded_by, label, storage_ref)
      values ('cc000000-0000-0000-0000-0000000000e1', '77777777-7777-7777-7777-777777777777', 'sneaky', 'x/y.pdf');
    raise exception 'FAIL: a non-owner must not upload to another''s order';
  exception when insufficient_privilege then
    raise notice 'PASS: a non-owner upload is refused by RLS (insufficient_privilege)';
  end;
end $$;
reset role;
-- the WORKER assigned to the order may see the buyer's documents (to do the verification)
set role authenticated; set app.user_id = :partner1;
do $$ declare n int; begin
  select count(*) into n from public.buyer_document where order_id='cc000000-0000-0000-0000-0000000000e1';
  if n <> 1 then raise exception 'FAIL: the assigned worker should see the order''s 1 document, saw %', n; end if;
  raise notice 'PASS: the assigned worker can see the buyer''s document (RLS via partner_on_order)';
end $$;
reset role;

\echo ''
\echo '################ PART D — signup linkage logic (auth trigger verified on dev) ################'
-- a fresh signup (e.g. Google) creates the portable app_user + client role, UNVERIFIED
reset role;
select app.link_auth_user('88888888-8888-8888-8888-888888888888', 'Tunde A', 'tunde@example.ng', 'google');
do $$ begin
  if not exists (select 1 from public.app_user where id='88888888-8888-8888-8888-888888888888' and auth_provider='google')
    then raise exception 'FAIL: signup should create the app_user keyed by the auth uid'; end if;
  if not exists (select 1 from public.user_role where user_id='88888888-8888-8888-8888-888888888888' and role='client')
    then raise exception 'FAIL: signup should grant the client role'; end if;
  if (select identity_verified from public.app_user where id='88888888-8888-8888-8888-888888888888')
    then raise exception 'FAIL: a social/email signup must NOT be identity-verified'; end if;
  raise notice 'PASS: signup creates app_user(id=auth uid)+client role with identity_verified=false (access is not identity)';
end $$;
-- signing in again refreshes the profile, never duplicates the role
select app.link_auth_user('88888888-8888-8888-8888-888888888888', 'Tunde Adewale', 'tunde@example.ng', 'google');
do $$ begin
  if (select name from public.app_user where id='88888888-8888-8888-8888-888888888888') <> 'Tunde Adewale'
    then raise exception 'FAIL: re-link should refresh the name'; end if;
  if (select count(*) from public.user_role where user_id='88888888-8888-8888-8888-888888888888' and role='client') <> 1
    then raise exception 'FAIL: client role must not duplicate'; end if;
  raise notice 'PASS: re-link is idempotent (profile refreshed, single client role)';
end $$;
-- give this user a real C1-PE-02 check via the normal pipeline
insert into public.property(id,lga,state,locality) values ('aa000000-0000-0000-0000-0000000000e2','Eti-Osa','Lagos','Ikoyi');
insert into public.order_matter(id,client_id,property_id,bundle) values ('cc000000-0000-0000-0000-0000000000e2','88888888-8888-8888-8888-888888888888','aa000000-0000-0000-0000-0000000000e2','ala_carte');
insert into public.order_line(order_id,service_code) values ('cc000000-0000-0000-0000-0000000000e2','C1-PE-02');
insert into public.payment(order_id,service_fee,government_fee_total) values ('cc000000-0000-0000-0000-0000000000e2',0,0);
select public.confirm_payment('cc000000-0000-0000-0000-0000000000e2','ref_pe02');
select set_config('t.pe',(select id::text from public.check_item where order_id='cc000000-0000-0000-0000-0000000000e2' and service_code='C1-PE-02'),false);
-- a NON-PE-02 check cannot verify identity
do $$ begin
  begin
    perform app.mark_identity_verified('88888888-8888-8888-8888-888888888888', current_setting('t.c1')::uuid);
    raise exception 'FAIL: identity must not be verifiable via a non-PE-02 check';
  exception when check_violation then
    raise notice 'PASS: identity cannot be marked verified through a non-PE-02 check (boundary is structural)';
  end;
end $$;
-- the C1-PE-02 check is the one path that verifies identity
select app.mark_identity_verified('88888888-8888-8888-8888-888888888888', current_setting('t.pe')::uuid);
do $$ begin
  if not (select identity_verified from public.app_user where id='88888888-8888-8888-8888-888888888888')
    then raise exception 'FAIL: a C1-PE-02 check should mark identity verified'; end if;
  if (select identity_verified_by from public.app_user where id='88888888-8888-8888-8888-888888888888') <> current_setting('t.pe')::uuid
    then raise exception 'FAIL: should record which check verified the identity'; end if;
  raise notice 'PASS: identity_verified becomes TRUE only through the C1-PE-02 verification path';
end $$;
-- a later sign-in can neither undo nor fake that verification
select app.link_auth_user('88888888-8888-8888-8888-888888888888', 'Tunde Adewale', 'tunde@example.ng', 'google');
do $$ begin
  if not (select identity_verified from public.app_user where id='88888888-8888-8888-8888-888888888888')
    then raise exception 'FAIL: re-link must not disturb a real verification'; end if;
  raise notice 'PASS: the signup path never alters identity verification (boundary holds both ways)';
end $$;

\echo ''
\echo '################ ALL STAGE 4 ASSERTIONS PASSED ################'
