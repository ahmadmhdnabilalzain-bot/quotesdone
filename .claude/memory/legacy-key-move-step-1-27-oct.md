---
name: legacy-key-move-step-1-27-oct
description: "27 Oct 2026: every consumer of the leaked legacy HS256 anon/service_role keys moved to the publishable/secret keys with a temporary fallback; the deploy order; the 24-48 h watch; and the trap that a new key sent as Bearer ONLY is read as anon by Storage"
metadata:
  node_type: memory
  type: project
  modified: 2026-10-27T16:30:00.000Z
---

Step 1 of closing the leaked legacy JWT secret (docs/reports/security/SECURITY_HARDENING_27_OCT.md item 3). Seat:
it_engineer. Every consumer now reads the NEW key first and the legacy one only as a temporary fallback:

- Site `src/lib/supaEnv.ts`: `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, then `NEXT_PUBLIC_SUPABASE_ANON_KEY`. The hardcoded
  legacy JWT is gone and NO literal replaced it (no key value is ever committed).
- `/api/resilience-ping`: `serviceKey()` = `SUPABASE_SECRET_KEY`, then `SUPABASE_SERVICE_ROLE_KEY`.
- `stripe_setup_page`: the runtime's `SUPABASE_ANON_KEY`, which Supabase injects as the publishable key (digest
  compared 27 Oct; `SUPABASE_SERVICE_ROLE_KEY` in the edge runtime is likewise the `sb_secret_` key).
- `fn_lead_sourcing_kick()`: through `fn_gateway_client_key()` = `app_secrets.publishable_key`, else `anon_key`.
  The value is written at release by `scripts/it/store_the_publishable_key_in_app_secrets.mjs`, never by SQL text.
- Scripts: `scripts/lib/supabase_keys.mjs` `pickApiKey(keys, 'secret'|'publishable')` replaces every
  `name === 'service_role' / 'anon'` pick.
- `scripts/checks/no_source_file_hardcodes_a_legacy_supabase_key.test.mjs` fails on any tracked legacy JWT (it found
  two more, in agent_knowledge.json and the agent_knowledge seed, now redacted). Production `agent_knowledge` still
  holds one copy of the old admin page with the anon JWT: data, not a sender; inert once HS256 is revoked.

**The trap (measured 27 Oct):** with the legacy JWT, `Authorization: Bearer <key>` alone worked on Storage, because
Storage verified the JWT. A `sb_secret_` key sent as Bearer ONLY is read as **anon** (Storage answered
"Bucket not found", 400; every expense document fetch failed). Always send `apikey` too. Functions accept Bearer-only
new keys; PostgREST needs `apikey` with either kind.

Vercel production already held `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` and `SUPABASE_SECRET_KEY` (integration, read
back by name), so nothing was added. The watch: `node scripts/it/hs256_traffic_since_the_key_move.mjs` (exit 0 only
on zero HS256 outside /admin/*). The gateway logs keep about a day, so run it daily through the window. Then disable
the legacy keys, then revoke HS256 key `746f6064-…`, then remove every fallback in one PR.

Related: [[apply-at-merge-never-before]]; the hardening pass state file (security-hardening-27-oct-state, PR #1651).
