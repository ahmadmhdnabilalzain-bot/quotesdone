# Supabase support ticket: remove pg_net's grant to PUBLIC, anon and authenticated

**Seat:** it_engineer. **Written:** 27 Oct 2026. **For:** the founder. Paste the block below into
<https://supabase.com/dashboard/support/new>, choosing project `htdblwldjkcgjvmqkbeh`, category "Database",
severity "Low" (nothing is exploitable today; see "Why it is not urgent" below).

## Why this goes to support and is not done in SQL

The objects belong to `supabase_admin`, and the estate connects as `postgres`, which is not a member of
`supabase_admin`. Measured on 27 Oct 2026 at about 15:20 UTC with a rolled-back probe (one `DO` block ending in
`raise exception`, so nothing committed):

- `revoke execute on function net.http_post(...), net.http_get(...), net.http_delete(...), net.worker_restart() from public, anon, authenticated`
  returned no error.
- `revoke all on table net.http_request_queue, net._http_response from public, anon, authenticated` returned no error.
- `revoke usage on schema net from anon, authenticated` returned no error.
- Inside the same transaction, after those statements, `has_function_privilege('anon', 'net.http_post(...)', 'execute')`
  was still **true**, and so were `anon` INSERT on the queue, `anon` SELECT on `_http_response`, `anon` EXECUTE on
  `net.worker_restart()` and `anon` USAGE on `net`. `pg_has_role('postgres', 'supabase_admin', 'member')` = **false**.

A revoke by a role that did not grant the privilege is a silent no-op in Postgres. The same result was recorded
earlier the same day in `docs/reports/security/prelaunch_audit_27_oct.md` (finding M1). A read-back after the
rollback confirmed that nothing changed.

## Why it is not urgent

Two conditions keep it unreachable today. Both were measured, and both are asserted on every gate run by
`scripts/checks/anon_cannot_execute_security_definer.test.mjs`:

- PostgREST serves only `public,graphql_public`, so the `net` schema is not served.
- No SECURITY INVOKER routine that `anon` or `authenticated` can execute references `net.*`.

The grant is defence in depth: if either condition ever broke, any website visitor could make the database send
HTTP requests from inside Supabase (SSRF), read the responses of the estate's own internal calls, and restart the
pg_net worker.

## What must keep working after the change

These roles need access, measured 27 Oct 2026:

- **`postgres`** needs it. 10 SECURITY DEFINER routines owned by `postgres` call `net.http_*`:
  `fn_action_invoke_dispatch`, `fn_backup_kick`, `fn_kb_embed_dispatch`, `fn_lead_sourcing_kick`,
  `fn_marketing_competitor_scan`, `fn_sanctions_screen_tick`, `fn_unfinished_signup_purge`,
  `fn_wa_human_request_tick`, `qd_sign_customer` and `qd_sign_supplier`. `net.http_post` is
  SECURITY INVOKER, so `postgres` needs EXECUTE plus INSERT on the queue and USAGE on its sequence. Today it gets
  them only through PUBLIC, so it **must** get an explicit grant in the same transaction as the revoke.
- **pg_cron** needs nothing extra. All 54 active jobs are owned by `postgres`, and none calls `net.http_*` directly.
- **Database webhooks** are not in use: 0 triggers use `supabase_functions`. `supabase_functions_admin` already has
  its own USAGE grant and is kept below anyway.

---

## Ticket text (paste from here)

**Subject:** Please revoke pg_net's default grants to PUBLIC / anon / authenticated on project htdblwldjkcgjvmqkbeh

Hello Supabase team,

Project ref: **htdblwldjkcgjvmqkbeh** (region ap-southeast-1, pg_net extension version 0.20.3).

On our project the pg_net objects carry their default ACL, which lets the `anon` and `authenticated` API roles use
them:

- All 12 functions in schema `net` (including `net.http_post`, `net.http_get`, `net.http_delete`,
  `net.worker_restart()`, `net.wake()`, `net._await_response(bigint)`) have a NULL ACL, so EXECUTE is granted to
  PUBLIC.
- `net.http_request_queue` and `net._http_response` grant `arwdDxtm` to PUBLIC
  (`=arwdDxtm/supabase_admin`). `net.http_request_queue_id_seq` grants `rwU` to PUBLIC.
- Schema `net` grants USAGE to PUBLIC, `anon` and `authenticated`.

All of these objects are owned by `supabase_admin`. Our `postgres` role is not a member of `supabase_admin`, so a
REVOKE issued as `postgres` completes without error and changes nothing. We verified this in a rolled-back
transaction: `has_function_privilege('anon', 'net.http_post(text,jsonb,jsonb,jsonb,integer)', 'execute')` stays true.

The `net` schema is not exposed through PostgREST on our project, so this is not exploitable today. We still want
the internet-facing roles to hold no SSRF-capable privilege, in case an exposure is ever added by mistake.

Please run the following as `supabase_admin` on our project, in one transaction:

```sql
begin;
-- keep the roles that legitimately use pg_net (our SECURITY DEFINER routines are owned by postgres)
grant usage on schema net to postgres, service_role, supabase_functions_admin;
grant execute on all functions in schema net to postgres, service_role, supabase_functions_admin;
grant select, insert, update, delete on net.http_request_queue, net._http_response
  to postgres, service_role, supabase_functions_admin;
grant usage, select, update on sequence net.http_request_queue_id_seq
  to postgres, service_role, supabase_functions_admin;

-- remove everything from the internet-facing roles and from PUBLIC
revoke execute on all functions in schema net from public, anon, authenticated;
revoke all on net.http_request_queue, net._http_response from public, anon, authenticated;
revoke all on sequence net.http_request_queue_id_seq from public, anon, authenticated;
revoke usage on schema net from public, anon, authenticated;
commit;
```

Three questions, please:

1. Will these grants survive a future pg_net upgrade or a platform maintenance? Our project has the event trigger
   `issue_pg_net_access` (ddl_command_end, function `extensions.grant_pg_net_access()`). On any DDL that touches
   the pg_net extension, it runs `GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon,
   authenticated, service_role`. So an `ALTER EXTENSION pg_net UPDATE` would hand USAGE back to `anon` and
   `authenticated`. Can that trigger stop granting to `anon` and `authenticated` on our project? If not, please
   tell us, so we can re-check after each upgrade.
2. Is there a supported way for us to manage pg_net's ACL ourselves, for example a `grant ... with grant option` to
   `postgres`, so that future changes do not need a ticket?
3. If you would rather not run this, is it safe for us to `drop extension pg_net` and re-create it (we would
   re-create our 10 dependent routines)? Would the re-created objects be owned by `postgres`?

Afterwards we will verify with:

```sql
select has_function_privilege('anon', 'net.http_post(text,jsonb,jsonb,jsonb,integer)', 'execute'),  -- expect false
       has_function_privilege('authenticated', 'net.http_post(text,jsonb,jsonb,jsonb,integer)', 'execute'), -- expect false
       has_function_privilege('postgres', 'net.http_post(text,jsonb,jsonb,jsonb,integer)', 'execute'), -- expect true
       has_table_privilege('anon', 'net._http_response', 'select'),       -- expect false
       has_table_privilege('postgres', 'net.http_request_queue', 'insert'), -- expect true
       has_schema_privilege('anon', 'net', 'usage');                     -- expect false
```

Thank you.

## (end of ticket text)

---

## After support replies

The `it_engineer` seat runs the verification query above and then one live outbound call through an existing
`postgres`-owned routine. If any `postgres` value reads false, it asks support to apply the grant half again;
nothing in the estate can do it. It then removes the residual from `prelaunch_audit_27_oct.md` M1. The gate check
`anon_cannot_execute_security_definer.test.mjs` stays as it is: it guards the two conditions, which still matter.
