-- =============================================================================
-- 0006  Evidence Item (append-only; hashed on the device at capture)
-- =============================================================================
-- Invariant #4 / Decision P: evidence is hashed on the partner's device at save,
-- before it travels. Preview is retake-or-keep only, never edit; once synced it is
-- a permanent record. The table is therefore append-only (no update, no delete).

create table public.evidence_item (
  id           uuid primary key default gen_random_uuid(),
  check_id     uuid not null references public.check_item(id) on delete restrict,
  captured_by  uuid references public.app_user(id) default app.current_user_id(),
  kind         public.evidence_kind not null,
  storage_ref  text,                                  -- signed-URL object key in Storage
  content_hash text not null,                          -- computed on device at save (the integrity anchor)
  gps_lat      double precision,
  gps_lng      double precision,
  gps_accuracy double precision,
  captured_at  timestamptz,                            -- device clock at capture
  synced_at    timestamptz not null default now(),     -- server receipt; capture->sync gap = synced_at - captured_at
  device_id    text,
  created_at   timestamptz not null default now()
);
comment on table public.evidence_item is 'Append-only captured proof; content_hash is computed on-device at save (Decision P / invariant #4).';
create index evidence_check_idx on public.evidence_item (check_id);
alter table public.evidence_item enable row level security;

create trigger evidence_item_block_modification
  before update or delete on public.evidence_item
  for each row execute function app.tg_block_modification();
