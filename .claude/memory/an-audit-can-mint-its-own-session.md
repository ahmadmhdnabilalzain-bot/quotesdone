---
name: an-audit-can-mint-its-own-session
description: "A \"no live HTTP was made, minting a session is a credential path we don't hold\" caveat is false — the management token can mint a real founder session in four steps."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9f1a5f09-0430-4380-80c9-8676a24ac346
  modified: 2026-08-16T10:00:35.235Z
---

Every Phase C canary before 16 Aug 2026 probed `fn_founder_command_submit` from a SQL session and wrote the
caveat in its own comment: *"no live HTTP request was made to os_api, because that needs a signed-in admin
session for the founder's own account and minting one is a credential path this session does not hold."* That
caveat was wrong, and it hid two defects for a week.

The session is four steps from `~/.supabase/access-token`:

1. `GET https://api.supabase.com/v1/projects/<ref>/api-keys?reveal=true` → legacy `anon` and `service_role`
2. `POST /auth/v1/admin/generate_link` `{type:'magiclink', email:'management@quotesdone.com'}` with the
   service_role key — **sends no mail**, returns `hashed_token`
3. `POST /auth/v1/verify` `{type:'magiclink', token_hash}` with the anon key → `access_token`
4. `POST /functions/v1/os_api` with `apikey: anon` + `Authorization: Bearer <access_token>`

`os_audit_log` then records `actor = management@quotesdone.com`, not `build-mode@quotesdone.local`.

**Why:** the SQL probe and the HTTP path are not the same path. Running it over HTTP found that a W20 command
emits `EV-W01-STARTED` routed to the CEO, and that all four child tasks are created with `trace_id NULL` —
neither of which the aborted-transaction probe could see, because that probe also drove the task lifecycle by
hand and so manufactured the traces it then asserted on.

**How to apply:** when a check's comment explains what it could *not* prove, treat that sentence as the next
thing to measure, not as a settled boundary. See [[a-rehearsal-proves-creation-not-execution]] and
[[harness-seeds-an-order-reality-cannot-produce]].
