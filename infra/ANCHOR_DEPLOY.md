# Deploying the daily anchor (Stage 3, external step)

The proof-layer DB core is already live. This is the deploy-verified glue: a scheduled Edge job
that calls `anchor_pending`, submits the day's Merkle root to OpenTimestamps + the public mirror
(both swappable), and writes the proof back with `record_anchor_proof`. Its external submission can
only be exercised on the deployed environment (the build sandbox cannot reach the public calendars).

## 1) Secrets (PowerShell, in the repo folder)

```powershell
# a long random string the scheduler will present; keep it private
supabase secrets set ANCHOR_TRIGGER_SECRET=<random-string>

# OPTIONAL — the public mirror (second witness). Point it at a public append-only log endpoint.
supabase secrets set MIRROR_PROVIDER=http
supabase secrets set MIRROR_URL=https://<your-public-log-endpoint>
# ANCHOR_PROVIDER defaults to "opentimestamps"; set ANCHOR_PROVIDER=none to disable external
# timestamping temporarily (e.g. while choosing a mirror).
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to functions automatically.

## 2) Deploy the function

```powershell
supabase functions deploy anchor-pending --no-verify-jwt
```

`--no-verify-jwt` because the scheduler authenticates with the `x-anchor-secret` header, not a
user login. The function refuses any call without the correct secret.

## 3) Prove it once, by hand

```powershell
Invoke-RestMethod -Method Post `
  -Uri "https://uemycsmowvryxmwsjyby.supabase.co/functions/v1/anchor-pending" `
  -Headers @{ "x-anchor-secret" = "<random-string>" }
```

If there are sealed-but-unanchored fingerprints, you get back a summary with `anchored: true`, a
`merkle_root`, a `checks_anchored` count, and `proof_recorded: true`. If nothing is pending you get
`anchored: false`. Then verify any sealed certificate now shows the anchor:

```
https://uemycsmowvryxmwsjyby.supabase.co/functions/v1/verify-certificate/<a-sealed-check-id>
```
— `anchored` becomes `true` with a `merkle_root`, `anchored_at`, and the `anchor_ref` (OTS + mirror).

## 4) Schedule it daily (Supabase SQL Editor)

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'ilevest-daily-anchor',
  '15 0 * * *',                              -- 00:15 UTC daily
  $$
  select net.http_post(
    url     := 'https://uemycsmowvryxmwsjyby.supabase.co/functions/v1/anchor-pending',
    headers := jsonb_build_object('content-type','application/json','x-anchor-secret','<random-string>'),
    body    := '{}'::jsonb
  );
  $$
);
```

The secret here lives server-side in the `cron.job` table (never exposed to browsers); for stricter
handling, store it in Supabase Vault and read it in the cron body. To change or remove the schedule:
`select cron.unschedule('ilevest-daily-anchor');`

## Swapping providers later (no rebuild)

The timestamp service and the mirror sit behind `ANCHOR_PROVIDER` / `MIRROR_PROVIDER`. If the
OpenTimestamps library ever needs replacing in the Edge runtime, implement the alternative branch in
`anchor-pending/index.ts` (`stampRoot` / `mirrorRoot`) and redeploy — the database core, the
orchestration, the write-once proof attach, and the schedule are untouched.

## What to report back

The deployed-environment confirmation: the by-hand run returning an anchored summary, the certificate
then showing the anchor, and the daily schedule registered.
