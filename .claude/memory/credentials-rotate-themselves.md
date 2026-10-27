---
name: credentials-rotate-themselves
description: Since 6 Sep 2026 the 62 fn.<edge> internal credentials carry a 1-year expiry and cron credential_rotate_daily (334) rotates them 30 days ahead via fn_internal_credential_rotate_due; the 18 non-fn contexts (cron.*, ops.*) deliberately have no expiry because nothing can renew them.
metadata:
  type: project
---

fn_internal_auth refuses an expired credential, so an expiry without a rotator is a scheduled
outage. Rotation is atomic for callers because _shared/llm.ts reads app_secrets.cred_fn_<edge> per
call: issue successor -> store secret -> retire predecessor in one transaction. The red-view alerter
lists any credential within 7 days of expiry (source 'credential'). Proof was an aborted-transaction
probe (62 due / 62 rotated / successor accepted / predecessor refused).

**How to apply:** a new llm.ts importer needs its credential issued (widen-or-issue block, e.g.
scripts/sql/the_inbound_classifier_uses_the_one_door.sql) AND its name in the archived audit-95
migration list (llm_gateway_credential.test.mjs reads that file). Non-fn contexts: if one is ever
given an expiry, give it a rotator first. See [[a-comment-that-kept-a-bypass-alive]].
