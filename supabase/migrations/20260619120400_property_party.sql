-- =============================================================================
-- 0004  Property and Party/Seller (first-class; Decisions E and F)
-- =============================================================================

-- PROPERTY: first-class and independent of any order, so repeat parcels are recognisable
-- over time (Decision E; the seed of supersession and the Phase 4 data asset).
create table public.property (
  id                  uuid primary key default gen_random_uuid(),
  lga                 text,
  state               text,
  locality            text,
  identifying_details text,
  first_seen_at       timestamptz not null default now(),  -- enables repeat-parcel recognition
  created_at          timestamptz not null default now()
);
comment on table public.property is 'First-class parcel, independent of any order (Decision E).';
create index property_locality_idx on public.property (state, lga);
alter table public.property enable row level security;

-- PARTY / SELLER: first-class but deliberately minimal at launch (Decision F).
create table public.party_seller (
  id          uuid primary key default gen_random_uuid(),
  name        text,
  identifiers text,                       -- minimal at launch; reserved for serial-fraudster detection later
  created_at  timestamptz not null default now()
);
comment on table public.party_seller is 'First-class but minimal at launch (Decision F).';
alter table public.party_seller enable row level security;
