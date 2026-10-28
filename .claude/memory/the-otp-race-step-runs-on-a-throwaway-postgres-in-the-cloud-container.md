---
name: the-otp-race-step-runs-on-a-throwaway-postgres-in-the-cloud-container
description: "28 Oct 2026: the cloud container has no Docker, but it does have the Postgres 16 binaries. A throwaway cluster run as the postgres user turns the gate's otp-race step from a 'known container failure' into a PASS (2/2)."
metadata:
  type: project
  modified: 2026-10-28
---

The gate's `otp-race` step (`supabase/functions/login_otp/verify_race.check.ts`) needs a throwaway Postgres. It reads
`QD_OTP_RACE_PG`, and without it falls back to Docker. The 27 Oct night checkpoint and #1658's gate tables both
reported it as FAIL, calling it environmental ("no Postgres in the container").

**Measured 28 Oct 2026 (customer_support, #1729).** The container has no Docker, but `/usr/lib/postgresql/16/bin/` is
installed and a `postgres` OS user exists. Two constraints shape the recipe:
- Postgres refuses to run as root.
- The session scratchpad is root-only (mode 700).

So the cluster lives in the postgres user's own home:

    runuser -u postgres -- bash -c 'set -e; D=/var/lib/postgresql/qd-otp-race; rm -rf "$D"; mkdir -p "$D"; echo race > "$D/pw";
      /usr/lib/postgresql/16/bin/initdb -D "$D/data" -U postgres --auth=md5 --pwfile="$D/pw" >/dev/null;
      /usr/lib/postgresql/16/bin/pg_ctl -D "$D/data" -o "-p 55432 -k $D -c listen_addresses=127.0.0.1" -l "$D/log" -w start'
    QD_OTP_RACE_PG=postgres://postgres:race@127.0.0.1:55432/postgres npm run gate

With that, `verify_race.check.ts` passed 2/2 in 0.4 s. It creates its own `anon`/`authenticated` roles and its own
table, and it never touches production. Stop the cluster afterwards with
`runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/qd-otp-race/data stop`.

**What it changes.** In a cloud session, an otp-race FAIL in the gate table is no longer the container's fault. It
means this cluster was not started.

**Not built yet.** `scripts/ci/local_gate.mjs` could start this cluster itself when Docker is absent (`withPostgres`).
That change belongs to it_engineer and gets its own PR.
