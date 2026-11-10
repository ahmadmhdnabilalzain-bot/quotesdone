---
name: direct-database-access-is-closed
description: "9 Nov 2026 (founder approved): production database SSL enforcement is ON and direct database access from the internet is CLOSED (network restrictions = documentation addresses only). Management API, PostgREST, edge functions and pg_cron are unaffected. To use psql / supabase db dump from a machine, add its IP in Supabase → Database → Network restrictions first."
metadata:
  type: reference
  modified: 2026-11-09
---

Changed 9 Nov 2026 23:20 UTC by it_engineer, on the founder's "of course, you can proceed with the database hardening".

- Before: `ssl_enforcement.database=false`; network restrictions `0.0.0.0/0` and `::/0` (the whole internet could try).
- Measured before the change: every live client connection was already TLS (pg_stat_ssl); no repository code
  connects to Postgres directly (git grep for postgres:// URLs, pooler hosts, DATABASE_URL, --db-url: none).
- Now: SSL enforcement ON; `dbAllowedCidrs ["192.0.2.1/32"]`, `dbAllowedCidrsV6 ["2001:db8::1/128"]` (documentation
  ranges that route nowhere, i.e. no outside address may connect directly).
- Verified after: management-API SQL (scripts/qsql.mjs) answered; a public edge function answered; 91 pg_cron
  runs succeeded in the next 3 minutes, 0 failed.
- Undo or widen: `POST /v1/projects/<ref>/network-restrictions/apply` with the CIDRs wanted (or the dashboard).
- A direct connection now fails with a network error. That is this rule, not an outage.

Related: [[security-hardening-27-oct-state]].
