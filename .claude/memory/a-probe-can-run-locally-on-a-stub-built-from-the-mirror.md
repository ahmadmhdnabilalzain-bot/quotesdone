---
name: a-probe-can-run-locally-on-a-stub-built-from-the-mirror
description: "3 Nov 2026 — with no SUPABASE_ACCESS_TOKEN, a new SQL file and its _probe.sql were executed on the cloud container's Postgres 16 against a stub of the tables and routines they touch, copied from the schema mirror; it caught a defect the rehearsal would have hit first."
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-03T13:30:00.000Z
---

The session that built `accountant.reveal_reconcile`
(scripts/sql/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql) had no management token, so the
PR rehearsal on production could not be run before pushing. Postgres 16 is installed in the container (see
[[the-otp-race-step-runs-on-a-throwaway-postgres-in-the-cloud-container]]), so the file was run for real:

1. `pg_ctlcluster 16 main start`, then work as the postgres user (`su postgres -c "psql -d <db>" < file`; psql cannot
   open a file under the root-owned scratchpad, so feed it on stdin).
2. A scratch script (kept in the scratchpad, never committed) pulled the needed `CREATE TABLE` blocks and
   `CREATE OR REPLACE FUNCTION` bodies out of `supabase/schema/full_schema/*.sql` — the REAL `fn_seat_duty_run`,
   `fn_accountant_duty_settle`, `fn_it_engineer_finding_upsert/close`, `fn_is_demo_email` — and stubbed only what
   cannot exist locally: roles anon/authenticated/service_role, `net.http_post` writing to a local
   `net.http_request_queue`, `net._http_response`, generated columns other than `customers.is_demo`, and missing
   sequences. ~570 lines; loads in a second.
3. `begin; <file>; <probe>; rollback;` — exactly what `scripts/ci/rehearse_sql.mjs` sends. Then break each rule once
   with `sed` into a scratch copy and confirm the probe names it.

**What it caught:** "the latest report" was `order by reported_at desc limit 1`. Inside ONE transaction `now()` is
constant, so every report tied and the probe's last assertion read an arbitrary row. The fix (`, id desc`) is also
right in production. The production rehearsal would have failed on it at the PR, after the push.

**Boundary:** a stub proves the file parses, the routines run and the probe's logic holds against the real bodies it
copied. It does not prove production's data, grants or extensions; the PR rehearsal on production still decides.
