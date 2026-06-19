-- =============================================================================
-- 0011  Privilege grants (command-level), paired with the RLS row-level policies
-- =============================================================================
-- RLS decides WHICH ROWS; these grants decide WHICH COMMANDS. Append-only tables are
-- granted no UPDATE/DELETE at all (defence in depth behind the immutability triggers).
-- No table grants DELETE except user_role (role separation), which is admin-gated by policy.

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema app    to anon, authenticated, service_role;

-- App helper functions are evaluated inside RLS policies (so the querying role needs EXECUTE)
-- and called by app/edge code. Lock EXECUTE to our roles rather than the default PUBLIC.
revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to authenticated, service_role;
grant execute on function app.current_user_id() to anon;

-- ---- authenticated: precise, least-privilege command grants ----
-- mutable tables: select/insert/update (RLS still scopes rows; triggers still guard transitions)
grant select, insert, update on public.app_user        to authenticated;
grant select, insert, update on public.partner_profile to authenticated;
grant select, insert, update on public.property        to authenticated;
grant select, insert, update on public.party_seller    to authenticated;
grant select, insert, update on public.order_matter    to authenticated;
grant select, insert, update on public.check_item      to authenticated;
grant select, insert, update on public.payment         to authenticated;

-- user_role: the one place authenticated may DELETE (admin-gated by policy) so Ops+Reviewer
-- can be split later "with no rebuild"; grant/revoke is audited.
grant select, insert, update, delete on public.user_role to authenticated;

-- append-only / insert-only tables: select + insert only (no update/delete grant at all)
grant select, insert on public.government_fee            to authenticated;  -- core is immutable
grant select, insert on public.government_fee_transition to authenticated;
grant select, insert on public.evidence_item             to authenticated;
grant select, insert on public.verdict                   to authenticated;
grant select, insert on public.commitment                to authenticated;

-- read-only for ordinary users
grant select on public.audit_event  to authenticated;
grant select on public.anchor_batch to authenticated;

-- ---- service_role: trusted server/edge code (bypasses RLS); full DML ----
grant all privileges on all tables    in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;

-- ---- anon: nothing in Phase 1 beyond schema usage; the public verification
--      function (Decision K) will be added later and granted to anon explicitly.
