# Synced from production — 27 July 2026

**Production was the source of truth for this sync, not this repo.** Local files were
overwritten from the live Supabase edge functions of project `htdblwldjkcgjvmqkbeh`.
Do not assume a file here is current just because its mtime looks recent — check the
deployed version before editing.

Source: live `get_edge_function` pull per slug. Every written file was verified
byte-identical (sha256) to the production pull after writing.

## Synced (local copy was BEHIND production — overwritten)

| slug | prod version | local before | after |
|---|---|---|---|
| os_api | v30 | 12,258 B | 18,164 B |
| inquiry_intake | v11 | 26,536 B | 28,575 B |
| quote_compare | v21 | 27,227 B | 28,657 B |
| agent_brain | v18 | 11,889 B | 17,742 B |
| meta_sync | v4 | 7,537 B | 8,103 B |
| knowledge_exam | v5 | 13,746 B | 14,228 B |
| drawing_redact | v7 | 6,636 B | 8,590 B |
| supplier_api | v27 | 41,975 B | 45,773 B |
| deploy_next_preview | v4 | 5,847 B | 6,749 B |
| retention_purge | v3 | 5,291 B | 5,759 B |

Recovered in this sync (would have been reverted if anyone had edited from the stale copy):

- **Fail-closed `__secret` auth guard** (`secretOk()`, "FAIL-CLOSED 27 Jul 2026") in
  `meta_sync`, `knowledge_exam`, `drawing_redact`, `retention_purge`. The stale local
  copies used a strict-equality check that could be satisfied by a missing/empty secret
  on functions that do not require a JWT.
- **Anonymity fixes 27 Jul 2026** in `supplier_api` (`scrubDeep()`, reveal-gating of
  `summary`/`spec`/`boq` before payment) and `drawing_redact` (opaque UUID storage
  prefix in place of a timestamp-based one).
- `deploy_next_preview` Vercel `target` fix; `quote_compare` v21 expert-reference
  feature; `os_api` v22→v30 action set; `agent_brain` pre-v14 → v17 employee runtime.

## Skipped — already identical to production (no write)

| slug | prod version | reason |
|---|---|---|
| customer_api | v36 | byte-identical to production |
| agent_act | v20 | byte-identical to production |
| cos_execute | v5 | byte-identical to production |
| dept_plan | v4 | byte-identical to production |
| canon_eval | v3 | byte-identical to production |

## Skipped — local work ahead of production

None. No local file contained work that production did not have, so nothing was
withheld and nothing unpushed was destroyed.

## Shared files

`agent_brain`, `agent_act`, `cos_execute`, `dept_plan`, `canon_eval` and
`knowledge_exam` are multi-file functions that also ship `_shared/llm.ts`
(reported by the pull as `functions/_shared/llm.ts`). The local
`supabase/functions/_shared/llm.ts` was already byte-identical to production
(sha256 `4c5fa242ad6986d43a09938cd5eaa262ba1469d01df036d7d454fbf48557ea74`,
8,229 B) — it already contained the 27 Jul 2026 AI cost-governor changes — so it
was verified and left untouched rather than rewritten.

## Scope

Only `index.ts` files under `supabase/functions/<slug>/` were written. Nothing was
deleted, nothing outside `supabase/functions/` was touched, and no git command was run —
these changes are unstaged working-tree edits for you to review and commit yourself.

---

# PRODUCTION IS AHEAD OF THIS MIRROR — 29 July 2026

Deployed to `htdblwldjkcgjvmqkbeh` and **not yet pulled back into this repo**. Read the
deployed version before editing any of these; the local copy is stale by definition.

| slug | prod version | what changed |
|---|---|---|
| `ai_gateway` | v5 | Carries vision, audio, the OpenRouter web/file-parser plugins, tool-calling and `response_format`. Capability is inferred from the payload and passed to routing. Caching disabled for binary and tool turns (see the comment on why the semantic path was dangerous there). 55s budget on modality calls. |
| `_shared/llm.ts` | shipped with `kb_research_test` v4 | New `llmCall` / `llmVision` / `llmWeb`. `makeLlm` is unchanged in behaviour and is now a wrapper over `llmCall`. |
| `kb_research_test` | v4 | Web research now goes through the gateway instead of its own OpenRouter fetch. |

Database (already committed via migrations, no drift):

- `model_registry` gained `supports_vision` / `supports_audio` / `supports_tools`.
- `fn_ai_route` gained `p_require_caps text[]` and substitutes a capable model, preferring
  the intended tier and then the nearest tier **above** it, so a capability substitution
  never silently becomes a quality downgrade.
- New policy classes `document_extraction` (4000 tokens) and `speech_transcription`.
  `extract_text`, `doc_extract`, `quote_extract`, `license_extract`, `drawing_boq` and
  `drawing_redact` moved off `ocr_cleanup`, whose 1200-token ceiling was truncating
  extractions. `secretary_act` moved off `customer_communication` (800 tokens) onto
  `chief_of_staff_decision`. `customer_api` was unmapped and is now mapped.

**To re-mirror:** `powershell -ExecutionPolicy Bypass -File scripts\qd-pull-functions.ps1`
(needs an `sbp_` access token). Do not hand-edit these three files here — pull them.

## CORRECTION — these were already migrated in production, only the repo was behind

An earlier draft of this note listed the functions below as "still calling OpenRouter
directly". That was read off the stale repo copy and was **wrong**. Production source was
pulled and checked: they were migrated onto `ai_gateway` and deployed on 28 Jul between
22:49 and 23:28 UTC — i.e. *after* the 22:40 UTC commit `11c497b`, which is why none of it
is in git. **31 edge functions are deployed and absent from this repo.** Their local copies
here are pre-migration and must not be edited or redeployed; pull them first.

Boot-verified 29 Jul: all 27 that had never been exercised were probed with a deliberately
invalid secret. 18 returned 403 and 9 returned 401 (the JWT-gated ones) — every one loads,
parses and enforces its auth guard. No 5xx, no import errors. Their runtime gateway path is
still unexercised; see the note at the end.

The 31, all deployed and absent from git:

`agent_autogen`, `capability_agent`, `customer_api`, `doc_extract`, `drawing_boq`,
`drawing_redact`, `extract_text`, `finance_doc`, `inquiry_ai`, `inquiry_intake`,
`inquiry_parse`, `kb_fill_gap`, `legal_review`, `license_extract`,
`os_pages`, `profile_ai`, `prompt_improve`, `quote_compare`, `quote_extract`,
`quote_review`, `resend_inbound`, `route_inquiry`, `secretary_act`, `seo_gen`,
`supplier_review`, `transcribe`, `translate_html`, `translate_page`, `kb_deepen`,
`kb_research_test`, `ai_gateway`.

(`site_assistant`, `wa_inbound` and `learn_gaps` were deployed BEFORE the last commit and
are correctly mirrored — they are not part of the drift.)

`ai_health` and `cost_snapshot` stay direct on purpose: they probe OpenRouter itself and
read its credit balance, so routing them through the gateway would test the wrong thing.

## Migrations applied but not committed

| version | name |
|---|---|
| `20260728230844` | `channel_decisions_task_cap_and_quality_loop` |
| `20260728234811` | `model_capabilities_and_capability_aware_routing` |
| `20260728234853` | `fn_ai_route_capability_aware` |
| `20260728235000` | `fn_ai_route_capability_substitute_respects_tier` |

The SQL for all four is recoverable from `supabase_migrations.schema_migrations.statements`.

## Verification status — 29 July 2026

The repo mirror is now complete: all 31 functions and the 4 migrations are in the working
tree. Deployed is still not the same as working, so each was exercised.

**Proven end to end** — a real model call, correctly routed, cost-logged in `ai_cost_log`:

| function | task class | model actually used |
|---|---|---|
| `legal_review` | contract_analysis | claude-sonnet-5 |
| `inquiry_parse` | json_extraction | gemini-3.1-flash-lite |
| `translate_html` | content_drafting | claude-haiku (correct Arabic returned) |
| `quote_review` | quote_comparison | claude-haiku |
| `supplier_review` | supplier_matching | gemini-3.1-flash-lite |
| `kb_deepen` | knowledge_research | claude-haiku |
| `kb_research_test` | knowledge_research | web plugin, 5 real sources |
| `extract_text` | document_extraction | gemini-3.5-flash (vision) |
| `secretary_act` | chief_of_staff_decision | claude-sonnet-5 (real tool_calls) |

`seo_gen` and `drawing_redact` ran cleanly with no work queued (no model call needed).
All 27 previously-unexercised functions boot and enforce their auth guard: 18 return 403 on
a bad secret, 9 return 401 without a JWT, zero 5xx.

Worth noting what the table shows: the cheap tier is now carrying real traffic. Before the
gateway, 100% of measured calls went to Sonnet or Opus. Extraction and classification now
land on flash-lite and haiku, and only contract analysis and agent reasoning reach Sonnet.

A second pass with real inputs verified seven more, each with a cost-logged model call:
`license_extract` (read a synthetic UAE trade licence correctly — name, licence number,
authority, emirate, dates, TRN), `profile_ai`, `capability_agent`, `quote_extract`,
`drawing_boq`, `kb_fill_gap` (filled a genuine 0-row category gap, 6 chunks inserted) and
`prompt_improve`. Seventeen of the 31 are now proven end to end.

One image-specific note: `drawing_boq` rejected a 1-bit PNG floor plan with
`invalid_request_error - Could not process image` from the provider, then handled a normal
image fine. That is an upstream image-format limit, not a routing fault, but real customer
drawings should be sent as standard RGB rather than 1-bit.

**Fixed 29 Jul: `translate_page` was returning HTTP 500 on every single call** — see the
commit. Pre-existing bug, unrelated to the gateway; the migration is just what caused it to
be called for the first time in weeks. Now verified returning Arabic.

**Still unproven, and why:**

| function | reason |
|---|---|
| `quote_compare` | needs 2+ non-draft quotes on one inquiry; there are zero quotes platform-wide |
| `inquiry_ai` | no `__secret` path — needs a signed-in user, or an `app_secrets.test_token` row that does not exist |
| `finance_doc` | calling it uploads a file and posts a real expense |
| `os_pages` | its AI actions rewrite `qd_deploy_src`; `publish` ships quotesdone.com |
| `agent_autogen` | creates a category agent and queues an email to the owner |
| `doc_extract`, `transcribe`, `customer_api`, `inquiry_intake`, `resend_inbound`, `route_inquiry` | need a real document, audio file, or signed-in session |

These are not known-broken — they are untested, which is a different thing. Each one boots
and enforces auth. Exercise them with real data when the opportunity arises naturally.

## Guard against this happening again

A scheduled task **"QuotesDone: daily deploy-vs-repo drift check"** runs every day at 09:00
Dubai. It compares each function's deployed timestamp against the last commit, compares
applied migrations against `supabase/migrations/`, pulls and commits anything that drifted,
checks `ai_cost_log` for failures and a spend spike, and reports in plain English. It is not
permitted to deploy, change schema, send, publish or delete — mirroring production into git
is its only write.

One false alarm, recorded so nobody re-chases it: `prompt_improve` returns `{"error":"no_key"}`
on an empty body. That is a missing `body.key` (which prompt to improve), not a missing
credential.
