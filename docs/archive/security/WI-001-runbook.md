> **Archived 16 Nov 2026** (simplification wave B, it_engineer): an operator runbook whose SQL calls fn_internal_credential_issue/_rotate/_retire, which production no longer has (scripts/checks/llm_gateway_credential.test.mjs treats them as dropped). 3 of the 4 routines it names are gone from production (SELECT pg_proc, 16 Nov 2026). History, not the build today.

# WI-001 / audit 9.5 — operator runbook for scoped internal credentials

Step one landed 3 August 2026. **The shared secret still works everywhere.** Nothing about this
change can break a caller that has not been moved yet — that is the design, not luck.

## Where things stand

```sql
select * from public.v_internal_secret_migration_progress;
```

As of 3 Aug 2026:

| | |
|---|---|
| cron jobs total | 149 |
| still on the shared secret | **42** (33 active) |
| moved to a scoped credential | **1** (`uptime_check_15min`) |
| edge functions still reachable by the shared secret | 41 |
| scoped credentials issued | 1 (`cron.monitoring`) |
| safe to withdraw the shared secret | **false** |

## Corrected numbers

WI-001 and `PHASE1_HARDENING_REPORT.md:179` both say **"146 cron jobs (141 active)"**. Production
says **43 (34 active)** — the document counted *every* cron job rather than the ones passing the
secret, and sized its risk estimate off a number **3.4× too big**. The direction of the finding was
right; the headline was not.

This is not a footnote. Counting by grep produced a wrong answer again within minutes of the first
migration: right after moving `uptime_check_15min`, a naive `command ilike '%inbound_secret%'` still
returned 43, because the new command carries a *comment* saying what it was moved off.
`v_internal_secret_migration_progress` therefore counts the actual `key='inbound_secret'` reference,
not the presence of a word.

## Moving one context across

Order matters, and each step is independently reversible.

**1. Make the target functions accept the verifier.** Edit each one to use the shared module and
deploy. This changes nothing about who can call it — `fn_internal_auth` accepts both the new
credentials and the legacy shared secret.

```ts
import { requireInternal } from '../_shared/internal_auth.ts';

const auth = await requireInternal(admin, body.__secret, 'my_function_slug');
if (!auth.ok) return J({ error: auth.error, message: auth.message }, auth.status);
```

The slug must be the real function slug — scope is checked against it, so passing something else
silently widens the check.

**2. Issue the credential.** Scope it to exactly the functions that context calls.

```sql
select public.fn_internal_credential_issue(
  'cron.knowledge',
  array['kb_ingest','kb_embed','kb_deepen','kb_autofill_gaps','knowledge_exam']
);
```

The secret is returned **once**. Store it immediately:

```sql
insert into public.app_secrets (key, value) values ('cred_cron_knowledge', '<secret>')
on conflict (key) do update set value = excluded.value;
```

**3. Move the crons**, one at a time, changing only the key they read:

```sql
select cron.alter_job(<jobid>, command := $cmd$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_ingest',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='cred_cron_knowledge')),
    timeout_milliseconds:=120000)
$cmd$);
```

**4. Prove it before waiting for the schedule.** Run the command body by hand and read the response
— a wrong key name resolves to NULL and gives a 403, and you want to find that now, not in an hour:

```sql
select net.http_post(...) as request_id;                     -- then:
select status_code, left(content,200) from net._http_response where id = <request_id>;
```

**5. Watch.** `v_internal_credential_health` shows `use_count` and `last_used_at` per credential.
The legacy row's `use_count` is the number that decides when the shared secret can go.

## Rotating

```sql
select public.fn_internal_credential_rotate('cron.knowledge');
```

The **old credential stays live**. Update `app_secrets`, confirm the old one's `use_count` has
stopped rising, then:

```sql
select public.fn_internal_credential_retire(<previous_id>, 'rotated, callers moved and confirmed');
```

A rotation that invalidates the old secret immediately is the reason rotations never happen.

## Withdrawing the shared secret

Only when `safe_to_withdraw_shared_secret` is true — no active cron references it and it has had no
successful use for 7 days. Then retire the legacy credential and delete the `app_secrets` row. Do
not do it on a hunch; the whole point of the counters is that this is a fact, not a feeling.

## What this step does NOT do

- **41 of 42 functions are untouched.** They still compare the shared string themselves. They are no
  worse than yesterday, and now measurable.
- **Attribution is per credential, not per call.** Successes bump `use_count` / `last_used_at` /
  `last_function`; only refusals get a row. A row per success would be tens of thousands a day
  (`email_cron` runs every 2 minutes) and would bury the signal. Enough to scope an incident to a
  context; not a full call log.
- **Outbound hops are still legacy.** `uptime_check` is gated on the way *in* but still calls
  `alert_founder` with the shared secret, because moving that hop needs `alert_founder` to accept
  the verifier first. Changing both ends at once is the big-bang swap WI-001 warns against.
- **20 database functions** still embed the secret. Not started.

## Suggested context map for the remaining 42

Derived from the cron → function mapping. Roughly a dozen contexts, as WI-001 intended.

| context | functions |
|---|---|
| `cron.monitoring` ✅ | uptime_check, ai_health |
| `cron.knowledge` | kb_ingest, kb_embed, kb_deepen, kb_autofill_gaps, knowledge_exam, gen_category_knowledge, gen_category_personas, learn_gaps |
| `cron.agents` | agent_autogen, agent_learnings_report, exec_agents, reflect, dept_learn, dept_plan, cos_execute |
| `cron.notifications` | email_cron, send_sms, send_whatsapp, email_triage |
| `cron.finance` | finance_ingest, cost_snapshot, money_tests, collections_legal |
| `cron.marketplace` | embed_leads, enrich_capability, match_eval, boost_recommend, archive_rfq |
| `cron.content` | blog_weekly, seo_gen, content_revise, assets_ingest |
| `cron.backup` | backup, dropbox_backup, dropbox_sync, dr_drill, retention_purge, github_sync |
| `cron.documents` | doc_extract |
| `cron.marketing` | meta_sync |

Ten contexts for 42 jobs — versus one credential for everything today.
