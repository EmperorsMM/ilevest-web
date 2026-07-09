-- defer_nin_bvn_smoke.sql — C1-PE-02 is off and cannot be ordered via Diaspora
\set ON_ERROR_STOP on
\echo '################ C1-PE-02 is inactive ################'
do $$
begin
  if (select active from public.service_catalogue where code = 'C1-PE-02') is not false then
    raise exception 'FAIL: C1-PE-02 must be active=false pending legal clearance';
  end if;
  raise notice 'PASS: C1-PE-02 (NIN/BVN) is switched off';
end $$;

\echo '################ C1-PE-02 is not in the Diaspora bundle ################'
do $$
begin
  if exists (select 1 from public.bundle_service where bundle='diaspora' and service_code='C1-PE-02') then
    raise exception 'FAIL: C1-PE-02 must not be in the Diaspora bundle';
  end if;
  raise notice 'PASS: ordering Diaspora cannot create a NIN/BVN line';
end $$;

\echo '################ Diaspora still delivers its other checks ################'
do $$
declare n int;
begin
  select count(*) into n from public.bundle_service where bundle='diaspora';
  if n < 8 then raise exception 'FAIL: Diaspora should retain its full check set (got %)', n; end if;
  raise notice 'PASS: Diaspora retains % checks (site inspection + full set)', n;
end $$;

\echo '################ inactive service does not surface in the active catalogue ################'
do $$
begin
  if exists (select 1 from public.service_catalogue where code='C1-PE-02' and active = true) then
    raise exception 'FAIL: C1-PE-02 must not appear as an active, selectable check';
  end if;
  raise notice 'PASS: C1-PE-02 will not surface to buyers as a selectable check';
end $$;

\echo ''
\echo 'ALL NIN/BVN DEFERRAL ASSERTIONS PASSED'
