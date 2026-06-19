-- =============================================================================
-- 0002  User, User-Role (multi-role), Partner Profile, and RLS role predicates
-- =============================================================================

-- USER -----------------------------------------------------------------------
create table public.app_user (
  id             uuid primary key default gen_random_uuid(),
  name           text,
  email_or_phone text,
  nin_ref        text,        -- minimised KYC reference only (Decision N); never a raw NIN/ID image
  created_at     timestamptz not null default now()
);
comment on table public.app_user is 'Anyone who touches the system. id equals the Supabase auth user id in deployment.';
comment on column public.app_user.nin_ref is 'Minimised KYC reference/token only (Decision N). Raw identity documents are not stored here.';
alter table public.app_user enable row level security;

-- USER_ROLE (many-to-many) ---------------------------------------------------
-- Decision H: six distinct roles; one human may hold Ops+Reviewer at launch and be split
-- later "with no rebuild". A join table delivers that directly: grant/revoke a row, no schema change.
create table public.user_role (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.app_user(id) on delete cascade,
  role       public.app_role not null,
  granted_by uuid references public.app_user(id),
  granted_at timestamptz not null default now(),
  unique (user_id, role)
);
comment on table public.user_role is 'A user may hold multiple roles; separable later with no schema change (Decision H). Grants/revocations are audited.';
alter table public.user_role enable row level security;

-- PARTNER_PROFILE (1:1 extension of a partner User) --------------------------
create table public.partner_profile (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null unique references public.app_user(id) on delete cascade,
  desks_covered        text[] not null default '{}',   -- LR|SG|CT|PE|FD
  states_covered       text[] not null default '{}',   -- Lagos|Ogun|FCT
  credential_type      text,
  credential_number    text,
  credential_status    text not null default 'active' check (credential_status in ('active','lapsed','suspended')),
  credential_expiry    date,
  verified_by          uuid references public.app_user(id),
  verified_at          date,
  trust_record         jsonb not null default '{}'::jsonb,  -- jobs|fixes|exceptions|disputes (Section 15)
  registered_device_id text unique,                          -- one registered device per partner (Decision Q)
  created_at           timestamptz not null default now()
);
alter table public.partner_profile enable row level security;

-- RLS ROLE PREDICATES --------------------------------------------------------
-- SECURITY DEFINER so they can read user_role without triggering that table's own RLS
-- (a normal policy querying user_role would otherwise recurse infinitely). search_path is
-- pinned to '' and every reference is schema-qualified to close the definer-injection vector.
create or replace function app.has_role(p_role public.app_role)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_role ur
                 where ur.user_id = app.current_user_id() and ur.role = p_role);
$$;

create or replace function app.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_role ur
                 where ur.user_id = app.current_user_id() and ur.role = 'admin');
$$;

create or replace function app.is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_role ur
                 where ur.user_id = app.current_user_id() and ur.role in ('ops','reviewer','admin'));
$$;

create or replace function app.is_ops()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_role ur
                 where ur.user_id = app.current_user_id() and ur.role in ('ops','admin'));
$$;

create or replace function app.is_reviewer()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_role ur
                 where ur.user_id = app.current_user_id() and ur.role in ('reviewer','admin'));
$$;
