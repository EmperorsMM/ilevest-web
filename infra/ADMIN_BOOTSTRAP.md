# Bootstrapping the first Admin

Admins are normally provisioned by another Admin. The very first one is a chicken-and-egg case,
so it is created once, by hand, by a trusted operator with database access — and then that Admin
provisions everyone else through the app.

## Procedure (run once)

1. The intended admin **signs up normally** in the app (email or Google). This creates their auth
   user, their `app_user` (keyed to the auth uid), and a default `client` role.
2. A trusted operator opens the Supabase **SQL Editor** (which runs as a superuser) and grants the
   `admin` role to that account, by email:

   ```sql
   insert into public.user_role (user_id, role)
   select id, 'admin' from public.app_user
   where email_or_phone = 'THE_ADMIN_EMAIL_HERE'
   on conflict do nothing;
   ```

3. Confirm exactly one admin exists:

   ```sql
   select u.email_or_phone from public.user_role r
   join public.app_user u on u.id = r.user_id where r.role = 'admin';
   ```

From here, that Admin uses the app to create Ops, Reviewer, Field Agent, and Partner accounts.

## Securing the bootstrap admin

- **Strong auth on the account:** enable MFA in Supabase Auth for admin accounts; prefer a real
  corporate identity over a personal social login (social login is access, not identity).
- **Restrict who can run the bootstrap:** only people with Supabase project (database) access can
  perform step 2; keep that list short and audited.
- **Least privilege still holds:** even this Admin cannot seal a verdict or move money — those stay
  with Reviewer and Ops. A compromised admin can disrupt *access*, not forge a *verification*.
- **Revocation:** an admin role is removed the same way it was granted (delete the `user_role` row),
  or via `admin_revoke_role` for the four staff roles.
