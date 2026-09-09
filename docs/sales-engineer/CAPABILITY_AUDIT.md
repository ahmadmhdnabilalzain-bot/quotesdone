# Sales Engineer — repository and integration capability audit

Required by the build prompt §18: *"First deliver a repository and integration capability audit,
then implement in working increments."*

Every figure was measured against production `htdblwldjkcgjvmqkbeh` on 9 September 2026 by eleven
parallel read-only investigations. Nothing here is inferred from documentation.

---

## 1. The two blockers only the founder can clear

**These are not engineering problems and no amount of building removes them.**

### 1.1 OpenRouter is held shut, by him, until the year 2126

`openai/gpt-6-astra` is real, and this account is permitted to use it — it appears in the
account-scoped model list (428 of 431 catalog models), context 1,050,000, with `tools`,
`structured_outputs` and `reasoning_effort` supported.

It still cannot be called. All **8 routes** in `llm_route_health` carry `open_until =
2126-08-15`, every row bearing his own words:

> HELD BY THE FOUNDER 15 Aug 2026: no OpenRouter calls until he releases it.
> Release with: `update llm_route_health set open_until = null;`

`fn_kernel_paid_provider_gate` denies **globally** when *any* route is held, so registering
gpt-6-astra with a clear hold changes nothing — all eight must be cleared together.

`consecutive_failures = 0` on every row: a deliberate stop, not a tripped breaker.

**Credit:** limit $200, used $195.93, **$4.07 remaining** against the estate's own configured floor
of `openrouter_min_usd = 20`.

**Measured consequence:** zero paid model calls in the visible window. `llm_attempt` 0 rows;
`ai_cost_log` 8 rows, every one `model_used='none'`, `cost_aed=0`, four naming the hold explicitly.
The website chat is answering visitors from templates with no model call at all.

### 1.2 The lead list cannot lawfully be emailed

22,264 rows in `leads`; 19,896 with an email. **Every one scraped** — `scraped_at` populated on
22,261, sources `uaecsd` 9,873 · `web_scrape` 4,635 · `uaecsd_xlsx` 4,282 · `yello_staging` 1,800 ·
`uaecompanies` 862 · `apify_2026-06` 607 (Apify Google-Maps) · `yellowpages` 186.

**There is no consent column in the table.** Not absent data — absent schema. Nowhere to record a
lawful basis even if one existed. `accepted_terms_at` 0, `wa_optin` 0, `signed` 0.

Resend prohibits unsolicited cold outreach. Sending this list as invitations violates that at any
volume, and engages UAE PDPL direct-marketing consent. **No cap, warm-up or wording fixes it.**

**Corrected 9 Sep after founder challenge:** nothing has ever been sent. `notifications` holds 2
rows, both `founder_alert`; **zero invitation notifications, ever**. The 171 `leads.invited_at`
values are test data written straight to the status column. See
`a-status-column-is-not-a-delivery-record`.

---

## 2. What the sweep of 7–9 September took, and left calling

Commit `182308b` (PR #530, 8 Sep) deleted **137 edge functions** from repo and production without
updating their callers. Ten live call sites now point at nothing. Every one fails **silently**.

| Missing function | Called from | What breaks | How it fails |
|---|---|---|---|
| `route_inquiry` | `customer_api:187` | capability matching | silent downgrade to keyword matching |
| `cad_convert` | `customer_api:581`, `supplier_catalog_ingest:150` | DWG/DXF | 200 + `cad_not_converted` |
| `drawing_redact` | `customer_api:615` | supplier-safe drawings | RFQ sent with **no** drawing (fails safe) |
| `drawing_boq` | `customer_api:618` | BOQ from drawings | 200 + `ok:false`, invisible to the buyer |
| `quote_extract` | `supplier_api:789` | quote OCR | 502, falls back to manual entry (handled best) |
| `doc_extract` | — | **the only OCR fallback in the estate** | `customer_documents` reads a column nothing writes |
| `capability_agent` | `supplier_api:307` | **the only writer of `supplier_capabilities.confirmed_at`** | 502 |
| `profile_ai`, `supplier_review` | `supplier_api:118,121` | supplier AI review | swallowed; email says "AI check:" with nothing after |
| `compliance_archive` | 3 sites incl. 2 DB triggers | archival | `net.http_post` result discarded |
| `sanctions_screen` | `fn_sanctions_screen_tick` | screening | 404, and never scheduled anyway |

**Sources survive at `182308b^`.** Precedent exists: PR #532 already restored eight functions from
the same sweep. **This is recovery, not construction.**

---

## 3. The marketplace has never run

| Table | Rows |
|---|---|
| `inquiries`, `quotes`, `transactions`, `inquiry_matches`, `projects` | **0** |
| `customers` | **1** (created 8 Sep 17:09 UTC — the only real business event) |
| `leads` | 22,264, of which **0 verified, 0 matchable** |
| `supplier_capabilities` | 15,305, of which **0 confirmed** |

`fn_is_matchable` requires `verified = true`. **Zero rows pass it.** So even with `route_inquiry`
restored, every inquiry terminates at the coverage-gap branch. **The blocker is data, not code.**

Three suppliers once uploaded a licence; all three lead rows have since been deleted. Nobody has
ever completed onboarding.

---

## 4. What is already built and should be reused, not rebuilt

This is the most important section. The estate is far richer than it looks — the pattern
throughout is **built + empty + switched-off**, not missing.

| Capability | State | Verdict |
|---|---|---|
| `fn_match_capability` | Implements most of the spec's mandatory-gate list as hard SQL *before* ranking: trade intersection, negative `excluded_trades`, contracted role via `taxonomy_role`, every `taxonomy_trade.authority_required` code, project-value band, emirate coverage. Then weighted scoring from `decision_policy`. | **Reuse.** Fix one thing: unknown coverage/value **passes** the gate (`cardinality(coverage_emirates)=0` reads as "covers everywhere"). Spec says unknown mandatory evidence is not a pass. |
| `inquiry_answer` + `_document` + `_corroboration` + `_conflict` + `_scope` | A real provenance-carrying fact ledger with conflict modelling. 0 rows. | **Extend.** This is the spec's typed fact ledger, already designed. |
| `inquiry_workstream` / `inquiry_gate` / `v_workstream_dispatch` | Full work-package + gate + dispatch-eligibility layer. **`inquiry_gate_required` has 0 rows, so `gates_passed` is a NOT EXISTS over an empty set — vacuously true forever.** No deployed code reads any of it. | **Wire and seed.** Seeding `inquiry_gate_required` is the single highest-leverage act available. |
| `supplier_capability_confirmation` | Versioned proposed/confirmed/supplier_added/exclusions with `agent_version`. 0 rows, no writer. | **Wire.** This is the spec's versioned capability model, already built. |
| `inquiry_supplier_brief` + `inquiries_supplier_safe` | Versioned, hash-sealed (`brief_sha256`) supplier-facing brief with a view that prefers the frozen version. 0 rows. | **Wire.** |
| `quote_compare` + `deterministic.ts` | Comparison service with a model-free fallback that ranks on stated facts only and labels itself `degraded`. | **Reuse, do not rebuild** (spec says so explicitly). |
| `fn_company_hard_rules` | Reads the live Supplier Agreement + `pricing_config` at call time. | **Single source for commercial values.** |
| `support_ceo_report` + `fn_support_report_to_ceo` | `idempotency_key UNIQUE`, unfiltered-lookup-returns-original, refuses to invent a recipient, `delivery_attempts` + `last_delivery_error` + `status` = generation/submission/delivery as distinct states. | **The envelope pattern to copy.** Note: it has a writer and **no reader** — `ceo_agent`'s inbox ignores it. |
| `fn_licence_expiry_sweep` / `fn_reconcile_doc_blocks` / `fn_licence_ask_close_for_lead` | Complete renewal→invalidate→revalidate→stop-reminders loop. Closes an ask only when a **document arrives**, never when a message is sent — exactly the spec's requirement. Never scheduled. | **Wire to a scheduler.** |
| `_shared/attachment.ts` | Magic-byte sniffing, polyglot refusal, `danger/*` classes refused by shape, EXIF/XMP/ICC + PNG chunk stripping, `safeFilename`. Wired at 13 of 14 sites. | **Reuse.** The 14th (`supplier_catalog_ingest`) is the hole. |
| `fn_support_may_act` | Evaluates `active` **and** `expires_at` at execution time; refuses on a missing grant rather than defaulting open. | **Generalise** to `fn_agent_may_act(grantee, class, amount)`; do not copy. |

---

## 5. The commercial rules, confirmed from production

| Rule | Measured | Source |
|---|---|---|
| Reveal fee | **3%**, customer pays, ex-VAT, no cap, suppliers pay no commission | `pricing_config`, `reveal_fee()` |
| Top-3 | **3** — ranks all, shows best three on technical **and** commercial merit, never cheapest-wins | `quote_compare:212`, `deterministic.ts:132` |
| Non-response | **Not a 3% rule.** 5 working days from payment; chase day 3; refund if silent. Then supplier owes 3% + **AED 250** admin + **9%** p.a., and is match-blocked | `pricing_config`, `decision_policy` |
| Anti-circumvention | **AED 15,000 per incident OR 3× the fee, whichever is higher**, plus the unpaid fee, 24-month window | parsed live from `pages.legal_supplier_body` |
| Category opens | **10** verified suppliers | `category_open_min_suppliers` |

Fanout: `match_max_fanout = 5`, per-trade 3, relevance floor 35 — but the live keyword fallback
hard-codes `p_limit: 8`, **contradicting the configured ceiling**.

---

## 6. Security — what must be true before an LLM reads untrusted documents

The authority model would survive a prompt injection. **The content model would not.**

- **No prompt boundary separates instructions from data.** Not one of ~14 call sites. `ai_gateway`
  forwards `sys` and `input` verbatim.
- **The injection test everyone believes in tests a plpgsql regex**, not a model.
  `fn_document_classify` is `IMMUTABLE` and cannot return `approved`. No test anywhere puts
  adversarial text through an LLM.
- **Two model outputs select a branch with no enum check** — `resend_inbound:322`,
  `email_triage`. `license_extract:88-96` does it correctly and is the pattern to copy.
- **`supplier_api:546` grants `verified = true` on `!!licPath`** — the *presence* of a path a model
  chose to write, not a validated licence.
- **SSRF at `resend_inbound:83`**: `fetch(a.url)` from a request-body field. No scheme check, no
  allowlist, no timeout, no size cap, inside a service-role function. Its guard check
  (`reg_fetch_refuses_private_addresses.mjs`) reads a **deleted file**, crashes `ENOENT`, and is
  registered in no CI runner.
- **`supplier_catalog_ingest` has zero upload validation** — extension-only dispatch, no size
  limit, and it expands a ZIP (XLSX) with no entry-count or ratio cap.
- **Pre-reveal leak, confirmed in production**: `documents.file_name` returns
  `AquaLux_Quotation.jpg` to the customer before payment. The supplier's filename is the identity
  the fee exists to sell.

Strong and worth preserving: 437/437 tables RLS-enabled with only 3 client-reachable; 0
anon-executable SECURITY DEFINER routines of 404; Svix HMAC on both Resend webhooks with
fail-closed on a missing secret; Stripe dual-secret verification with a 600s window; reveal
enforced by a **partial unique index** making double-reveal structurally impossible.

---

## 7. Scheduling — pg_cron is dead on purpose; one live path survives

`cron.job` holds **1 row** (`wa_flush`, `active=false`). 234 jobs were deleted on the founder's
7 Sep instruction, and 110 `cron.schedule` statements were stripped from 66 files so re-applying a
file cannot resurrect one. **Reactivating pg_cron wholesale would restart machinery he deleted.**

But automation is not fully stopped. **Vercel cron → `/api/resilience-ping` → `resilience_ping`
edge function** runs every 15 minutes and is provably independent of pg_cron: `send_outbox` has run
**51 times** on it since the crons died, most recently 00:30 UTC today.

**That is where the CEO digest hangs** — not a new pg_cron job.

`alert_founder` was deleted in the same sweep, which is why the `cron_down` alerts stop at 7 Sep
23:15 while `send_outbox` keeps running.

---

## 8. The knowledge pack — validated

All content claims verified by counting: 128 sectors ✅ · 896 fields ✅ · 37+15 guides ✅ ·
32 cases ✅ · 28 metrics ✅ · 1,136 records ✅ · 77,132 words measured vs 77,134 claimed ✅.
All 1,136 validate against `record.schema.json`; `record_id`s unique; 0 duplicate content.

**Three things the ingester must know:**

1. **`content_sha256` is NOT `sha256(content)`** — it is the canonical hash of the whole record
   minus that field. Naive recomputation "fails" all 1,136.
2. **Recursive ingestion would import 2,532 records instead of 1,136 (2.23×)** — the Markdown
   mirrors (+212), the SQLite index (+1,136), the eval scenarios (+48). Use
   `manifest.runtime_files` — a single file — as the pack instructs.
3. **Every record carries the same epistemic status.** `authored_guidance_not_expert_certified`,
   1136/1136. There is no confidence gradation.

**Honest quality read:** the 37 core guides, 15 deep dives and 32 cases are genuinely good — the
takeoff guide distinguishes issued quantity from extracted schedule from calibrated estimate and
says conflicting dimensions are "a material issue, not an averaging opportunity". The 128 sector
guides are thinner than their word count: **74% of sentence instances are identical boilerplate**,
leaving ~12 sector-specific sentences each. **This pack teaches an agent how to reason about
procurement evidence. It does not teach it UAE technical facts** — almost every place a domain fact
would live, it says "resolve from the current applicable authority." That is the safe choice, and
it means retrieval returns *procedure*, never *answers*.

F&B exclusion is correctly implemented: 35 mentions, all boundary statements, no catering content.

---

## 9. Knowledge retrieval — one live path, and no decision logging

- **`kb_search` is called and deployed nowhere**, so `kb_match` — the only true semantic retrieval
  over the field corpus — has **zero callers**. 166,093 embedded chunks and an HNSW index,
  unreachable.
- **`fn_ops_knowledge_match` returns 0 rows for both live agents**: its body begins `if v_dept is
  null then return; end if;` and both agents have `department = NULL`. All 9,139 embedded
  `ops_knowledge` records are unreachable through their own matcher.
- **`fn_agent_context_v3` raises on every call** — it calls four functions that do not exist.
- **`kb_usage_log` has 0 rows and no writer.** Nothing records which knowledge informed a decision,
  which is an explicit spec requirement.
- Embeddings are free and in-region (`gte-small`, 384-dim, `ai_gateway` `{action:'embed'}`) — **not**
  OpenRouter, so the founder hold does **not** block embedding.
- Only `fn_faq_answer` (0.86) and `fn_apply_playbook` (0.85) have a similarity floor. The two
  routines a Sales Engineer would use have **none** — a nearest neighbour is always found.
- **F&B knowledge is live and reachable**: 79 rows across five `cat:` slugs feed `quote_compare`.
  Legacy role identities (`cfo`, `marketing`, `legal`, `sales_director`) persist in
  `agent_knowledge`; `ops_knowledge` carries 4,740 rows across 33 dead `dept_key`s.

---

## 10. What the third agent must do to exist

Measured prerequisites, in dependency order:

1. `org_agents` row — `sales_engineer`, `routing_tier` ∈ {director, analyst_controller,
   operations_specialist, reviewer_auditor} or NULL, `department` NULL.
2. `org_role` row — **mandatory**: `ceo_standing_grant.grantee_role_id` is an FK to it.
3. `org_reporting_edge` — `sales_engineer → ceo`. Without it the report path *refuses* rather than
   inventing a recipient.
4. **Amend `function_owner_owner_ck`** — a live CHECK constraint restricting owners to
   `('ceo','customer_support','website')`. The seat cannot own an edge function until this admits
   `sales_engineer`.
5. **Amend `scripts/checks/support_acceptance_group_org_and_channels.mjs`** — asserts
   `exactly_two_active_roles = '2'`. Not CI-wired, so it will be *silently wrong* rather than
   blocking.
6. `ceo_standing_grant` rows, `issued_by='ceo'` (CHECK-enforced), one per narrow action class.
7. **Generalise `fn_support_may_act`** — its grantee is hard-coded to `customer_support`.
8. Internal credential `app_secrets.cred_fn_sales_engineer`, verified via
   `requireInternal(admin, body.__secret, 'sales_engineer')`. Note the credential travels in the
   **JSON body**, not a header.
9. Emit `agent_runs` rows and expose a health route — **neither existing agent does this**, and
   `fn_agents_board` renders both with `runs24=0`, indistinguishable from down.

**A security defect to fix while here:** `ceo_agent`'s `body.as === 'ceo'` is caller-declared and
unverified. Any holder of an in-scope internal credential can present as the CEO seat and call
`decide`. That is mine, from 8 Sep.

---

## 11. Honest build ledger

| | |
|---|---|
| **Recover from git** | `cad_convert`, `drawing_redact`, `drawing_boq`, `quote_extract`, `doc_extract`, `metadata_scan.mjs` + its 3 tables |
| **Wire what exists** | fact ledger, work packages, gates, capability confirmation, supplier-safe brief, licence sweep, `fn_support_may_act` |
| **Build new** | file-hash provenance (nothing hashes uploaded bytes anywhere), page/entity/cell provenance writer, dispatch ledger, evidence-class dimension, licence record, retrieval with a floor + decision logging, consent schema |
| **Procure** | native DWG — CloudConvert is paid for and configured but is a **rasteriser**; entity-level DWG needs a licensed SDK. Until then DWG must be advertised as **raster preview only** |
| **Founder only** | release the OpenRouter hold; top up credit; decide the lawful basis for supplier acquisition |
