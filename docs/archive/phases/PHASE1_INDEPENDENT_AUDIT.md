# QuotesDone — Phase 1 independent audit

**Date:** 2 August 2026 · **Commit audited:** `658e675` on `feature/phase1-safety-and-decisions` · **Production:** Supabase `htdblwldjkcgjvmqkbeh`
**Method:** read-only. Repository source and live database/Stripe state inspected directly. The Phase 1 completion reports (`docs/phases/PHASE1_REPORT.md`, `PHASE1_HARDENING_REPORT.md`, `PHASE1_FINAL_ACTIONS.md`) were used for orientation only and were **not** accepted as evidence; every contradiction found is stated.
**No production data was modified.** No migration was created. No finding was fixed.

---

## Scorecard — 42 checks

| Area | PASS | PARTIAL | FAIL | Worst severity |
|---|:--:|:--:|:--:|---|
| 1. Anonymity & drawing redaction | 2 | 2 | 1 | high |
| 2. Registration & legal evidence | 0 | 0 | 3 | **critical** |
| 3. Control Mode | 2 | 3 | 1 | **critical** |
| 4. Supplier pricing | 0 | 1 | 3 | **critical** |
| 5. Refunds | 1 | 3 | 2 | **critical** |
| 6. Supplier exception process | 1 | 2 | 2 | **critical** |
| 7. Authority & autonomy | 1 | 2 | 1 | **critical** |
| 8. Repository & production integrity | 1 | 2 | 1 | **critical** |
| 9. Remaining launch blockers | 0 | 0 | 5 | **critical** |
| **Total** | **8** | **15** | **19** | |

Nothing was recorded as wholly NOT TESTED; several checks contain NOT TESTED sub-elements, each named in place with what would settle it.

**Launch blockers: 19 checks. Phase 2 blockers: 12 checks.**

---

## Independently re-verified by the lead auditor

These findings were re-run first-hand rather than taken from a delegated check:

| Finding | Verification | Result |
|---|---|---|
| `supplier-docs` open to every authenticated user | `select policyname,cmd,roles,qual,with_check from pg_policies where schemaname='storage'` | 2 policies only: `SELECT`/`INSERT` to `{authenticated}`, predicate `bucket_id='supplier-docs'`, **no owner clause** |
| Terms version overwritten to `v4` | `pg_get_functiondef('qd_norm_supplier_ver')` | `if NEW.accepted_terms_at is not null then NEW.accepted_terms_version := 'v4'` — unconditional, on INSERT **and** UPDATE |
| Autonomy live while WI-001 open | `app_secrets` + `spec_backlog` | `agent_autonomy_enabled=true`, `agent_autonomy_from=2026-07-30`, `cos_frozen=false`; `spec_backlog` id 201 `WI-001 status=open priority=0` |
| `inbound_secret` blast radius | `select count(*) filter (where command ilike '%inbound_secret%') from cron.job` | **43 of 148** cron jobs (40 active) — the documented "146 cron jobs" is wrong by ~3.4× |
| Refund events not delivered | Stripe `GetWebhookEndpoints` | One endpoint, `we_1TqVtRC45SqX5pVbEbnsquAL`, `enabled_events: ["checkout.session.completed"]`, `has_more:false` |
| Control Mode covers one console only | `grep -rl control_mode supabase/functions/` | Exactly one file: `os_api/index.ts`. `os_ops` dispatches 30 actions, references `control_mode` **0** times |
| No Phase 1 rollback | `ls supabase/rollback/` | `p2_c1_stage_a_down.sql`, `p2_c1_stage_b_down.sql` — Phase 2 only; zero Phase 1 artefacts |
| Redaction publishes unmodified pages | `supabase/functions/drawing_redact/index.ts:99-100` | `const hasId = identityByPage[i] !== false; if (hasId && regions.length === 0) { skipped++; continue; }` — when the model returns `has_identity:false` the guard does not fire and the page is uploaded with no boxes |
| Arabic page sells a 2% commission | JSON walk of `src/content/legal.json` | `/refund-policy/ar/html`: «ويكونون مدينين لـ QuotesDone **بعمولة 2% على كل وظيفة يتم الفوز بها**» — "owe QuotesDone a 2% commission on every job won" |

---

# 1. Customer anonymity and drawing redaction

### 1.1 Arbitrary redacted path rejected — **PASS**
- **Evidence:** `customer_api/index.ts:344-363` builds the allow-list only from `drawing_redaction_runs.output_paths`; unknown paths return `redacted_paths_unverified` (400). `output_paths` can only contain server-generated names — `drawing_redact/index.ts:78-79` reduces the caller's `prefix` to one sanitised segment and appends `crypto.randomUUID()`; `:114` writes `${prefix}_p${i}.jpg`. `edit_inquiry` (`customer_api:708-715`) whitelists 9 fields, none of them path fields. Deployed `drawing_redact` v10 is identical to the repo file.
- **Queries/commands:** `grep -rn "drawing_redaction_runs\|drawing_redacted_paths"`; `mcp__Supabase__get_edge_function(drawing_redact)`; `information_schema.columns` on `drawing_redaction_runs`.
- **Affected:** `customer_api/index.ts`, `drawing_redact/index.ts`, `attach_photos/index.ts`, `public.drawing_redaction_runs`, `inquiries.drawing_redacted_paths`.
- **Severity:** low (residual: binding is customer-level, not job-level — any path from the caller's last 60 runs attaches to any new inquiry). **Blocks launch:** no. **Blocks Phase 2:** no.

### 1.2 Original upload path rejected — **PASS**
- **Evidence:** originals live at `drawings/<customer>/<ts>_<name>` (`customer_api:168-169`), redacted at `redacted/<uuid>/page_pN.jpg`; only the latter can enter `output_paths`, so naming the original hits the same 400. Live `storage.objects` confirms both namespaces in the one `drawing-files` bucket, which has **zero** storage policies (no direct client read).
- **Residual:** `supplier_api/index.ts:94` `signedRedacted()` will sign **any** object in `drawing-files` with the service role — no `name like 'redacted/%'` assertion. The DB allow-list is the only layer.
- **Queries:** `select bucket_id, name from storage.objects where bucket_id='drawing-files'`.
- **Severity:** low. **Blocks launch:** no. **Blocks Phase 2:** no.

### 1.3 Another customer's path rejected — **PARTIAL**
- **Evidence — function code passes:** ownership enforced twice at `customer_api:344-355` (server-side `.or()` filter plus a JS re-filter); a named job id not owned by the caller returns `redaction_job_not_found` (403). Client roles have no table access at all: `information_schema.role_table_grants` returns **zero rows** for `anon`/`authenticated` on `inquiries`, `customers`, `drawing_redaction_runs`, `inquiry_matches`; `pg_policies` returns zero policies on those tables (RLS on, deny by default).
- **Evidence — storage RLS fails:** the complete policy set on `storage.objects` is two rows, both `{authenticated}`, both keyed only on `bucket_id = 'supplier-docs'`, with **no owner predicate**. Any signed-in account can list, download and overwrite the entire supplier document store — trade licences, Emirates ID, establishment cards, VAT and IBAN letters (`supplier_portal/index.ts:21-29` `DOC_KINDS`, paths `${folder}/${leads.id}/...`). It also defeats the paid reveal in the other direction: `supplier_portal/index.ts:23` describes the company-profile document as *"Shown to customers after a reveal"*.
- **NOT TESTED:** the enumeration was not executed — minting an `authenticated` JWT is a mutation. The verdict rests on policy text plus the confirmed absence of any other restricting policy. One `POST /storage/v1/object/list/supplier-docs` with an existing user token would settle it.
- **Queries:** `select policyname,cmd,roles,qual,with_check from pg_policies where schemaname='storage'`; `role_table_grants`; `select bucket_id, split_part(name,'/',1), count(*) from storage.objects group by 1,2`.
- **Affected:** `storage.objects` policies `supplier read docs` / `supplier upload docs`, bucket `supplier-docs`, `supplier_portal/index.ts`, `supplier_api/index.ts`, `public.leads`.
- **Severity:** high. **Blocks launch:** yes — supplier KYC/PII readable and writable by any authenticated account. **Blocks Phase 2:** yes — anything that adds documents inherits the unbounded policy.

### 1.4 Incomplete redaction rejected — **FAIL**
- **Evidence:** nothing verifies that redaction happened. `drawing_redact/index.ts:99-100`:
  ```ts
  const regions = regionsByPage[i] || [];
  const hasId = identityByPage[i] !== false;
  if (hasId && regions.length === 0) { skipped++; continue; }
  ```
  with `:92` `identityByPage[i] = p?.has_identity !== false`. When the model returns `has_identity:false`, `hasId` is false, the guard does not fire, and `:102-117` decodes, resizes, re-encodes and uploads the page **with zero black boxes**, then counts it in `pages_out`. The system prompt at `:23` instructs the model to emit exactly that for a clean page, so this is the designed happy path.
  Also: no coverage floor (`.filter(g=>g.w>0&&g.h>0)` accepts `w:0.001`); no page-index validation (`Number.isFinite(i)` only — a shifted or duplicated index applies page N's boxes to page M); `status` at `:120` is pure arithmetic on array lengths. The downstream gate `customer_api:372-376` compares `pages_in` to `pages_out` — counters written by the same run. No OCR re-scan, no checksum, no coverage ratio, no second model, no `verified` column on `drawing_redaction_runs`.
- **Queries:** full read of `drawing_redact/index.ts`; `customer_api/index.ts:314-378, 401-431`; `information_schema.columns` on `drawing_redaction_runs`.
- **Severity:** high. **Blocks launch:** yes — "we anonymise your drawing" is the sold promise and the only thing behind it is an LLM's self-report on the same call. **Blocks Phase 2:** yes.

### 1.5 Supplier cannot access buyer identity before reveal — **PARTIAL**
- **Evidence — what holds:** `supplier_api/index.ts:493-534` (`inbox`) omits `customer_id`, never selects `raw_input` or `drawing_file_path`, forces `drawing_file_name: null`, and scrubs `summary`/`spec`/`boq`/`budget` pre-reveal against the buyer's name. Reveal gate is a `transactions` row (`:504-505`). Chat is gated on `revealed_at not null` (`messages_api:40-41,93`). Supplier drawing URLs are opaque signed UUID paths, and JPEG re-encoding drops EXIF. The DB trigger `trg_mask_inquiry_contact` and the six `*_masked` shadow columns exist in production, and `inquiries_supplier_safe` omits `customer_id`.
- **Evidence — gap 1:** the supplier notification email is scrubbed more weakly than the portal. `customer_api/index.ts:147` calls `scrubIdentity(summary, null, [])` — `ownName` is `null`, so the name regex is never built and **the buyer's name is not removed**; the portal passes `buyerName` for the identical text (`supplier_api:524`). The DB backstop `mask_contacts(text)` removes emails, URLs, messenger links and UAE numbers only — no name handling. A brief reading *"Villa fit-out for Ahmed Khan"* is emailed verbatim to every matched supplier.
- **Evidence — gap 2:** the durable backstop is dead code. `grep -rn "inquiries_supplier_safe"` returns only `supabase/schema/full_schema.sql:5464` and the defining migration. No edge function and nothing in `src/` reads it; `supplier_api:497` reads raw `public.inquiries`.
- **NOT TESTED:** no live supplier payload — `customers`, `inquiries`, `quotes`, `transactions` are all **0 rows**. Reproducing an `inbox` response requires creating a customer, inquiry, match and claim.
- **Queries:** `pg_get_viewdef('inquiries_supplier_safe')`; `pg_get_functiondef('mask_contacts(text)')`; `pg_get_functiondef` of the `inquiry_matches` trigger; `has_function_privilege('anon',oid,'EXECUTE')` sweep over `pg_proc`.
- **Severity:** medium alone; high combined with 1.3. **Blocks launch:** yes — the notification email is the first supplier-facing surface and is the one place the buyer's name survives. **Blocks Phase 2:** yes — the reader-independent masking layer is on no read path, so every new supplier surface must re-implement the scrub by hand.

---

# 2. Registration and legal evidence

### 2.1 Backend registration completeness — **FAIL**
- **Evidence:** `supplier_api/index.ts:6` defines 23 `PROFILE_COLS` and `:332` writes them with `for (const c of PROFILE_COLS) if (body[c] !== undefined) upd[c] = body[c];` — no length, format, type or range validation on `trn`, `bank_iban`, `emirates_id`, `license_expiry`, `founded_year`. The database does not compensate: `leads` has zero CHECK or FK constraints on these columns and all are nullable.
  Every "mandatory" rule is client-side only — `SupplierPortal.tsx:803-807` requires contact name, phone, licence number, company profile document, verified phone and accepted terms; `save_profile` enforces **none** of them, requires only a claimed row, and at `:397/:419` sets `approval_status='approved', verified=true` on a bare licence number.
  `owner_dob` is in form state and has a label but is in neither the submit whitelist (`:816`) nor `PROFILE_COLS` — yet `compliance_archive/index.ts:103` reads it for the acceptance certificate, so every certificate carries a blank DOB. `bank_iban` and `emirates_id` are in `PROFILE_COLS` and returned by `me` but have no input anywhere.
  Customers have no registration endpoint at all — `auth_api/index.ts:8` returns 410. Rows are created as a side effect with email only in three places (`customer_api:388`, `kyc:155`, `mobile_otp:54`), and **`customers.email` has no unique index** (`customers_pkey` is the only index) although all three paths key on it and use `.maybeSingle()`.
- **Queries:** `information_schema.columns` + `pg_constraint` + `pg_indexes` on `customers` and `leads`; `select count(*) from pg_constraint where contype='f' and conrelid in (...)` → `[]`; `grep -rn "from('customers').insert"`.
- **Live state:** `leads 20464`, `claimed 0`, `customers 0` — nothing is broken yet because nobody has registered.
- **Severity:** high. **Blocks launch:** yes — a supplier self-approves with a licence number and no verified identity. **Blocks Phase 2:** no.

### 2.2 Correct customer and supplier terms versions — **FAIL**
- **Evidence:** there is **no terms-version table** and no FK from any acceptance column to any version record. Five disagreeing supplier-agreement version strings:

  | Source | Value |
  |---|---|
  | `app_secrets.supplier_terms_version` | `v5` |
  | **live trigger `qd_norm_supplier_ver()` — overrides all writers** | **`v4`** |
  | served page header (`legal/index.ts:4`, `legal.json`) | `v6` |
  | served page body (`legal.json`) | `Version 4` |
  | browser payload (`SupplierPortal.tsx:815`) | `v2` |

  The trigger is unconditional and fires on INSERT **and** UPDATE:
  ```sql
  CREATE OR REPLACE FUNCTION public.qd_norm_supplier_ver() RETURNS trigger AS $$
  begin if NEW.accepted_terms_at is not null then NEW.accepted_terms_version := 'v4'; end if; return NEW; end $$;
  CREATE TRIGGER trg_norm_supplier_ver BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW ...
  ```
  So `kyc:192` and `supplier_api:358`, which both compute `v5`, are discarded. The customer twin `qd_norm_customer_ver()` hard-codes `'v3'`. **Neither trigger exists in `supabase/migrations/`** (`grep -rn "qd_norm" supabase/migrations/` → no output) — production-only drift.
  Three distinct supplier-agreement texts are live: `app_secrets.supplier_terms_html` (18,135 chars, "Version 5", the one `compliance_archive:98` hashes), `legal.json` `supplier-agreement.en.html` (11,676 chars, the one actually served and linked from the acceptance checkbox), and `pages.legal_supplier_body` (10,156 chars, still mentions commission). Customer side mirrors it: 15,492 chars hashed vs 16,933 served.
  `scripts/checks/pricing_consistency.test.mjs` never reads `app_secrets`, never compares `legal.json` to the DB, and asserts no version string — so it cannot catch this.
- **Queries:** `pg_get_functiondef` for both `qd_norm_*` triggers; `select key,left(value,120),updated_at from app_secrets where key ilike '%terms%'`; `select slug,length(html),(html ilike '%Version 5%') from pages where slug in (...)`; `select ... from legal_documents`.
- **Severity:** critical. **Blocks launch:** yes — the first supplier will be recorded as accepting `v4` (the commission model) while shown a `v6`/`v4` page and issued a certificate for a `v5` document they never saw. **Blocks Phase 2:** no.

### 2.3 Acceptance evidence remains consistent — **FAIL**
- **Evidence:** acceptance is four mutable, nullable columns on the business table (`leads.accepted_terms_*`, `customers.tos_*`). No append-only table, no history, no CHECK, no FK, no `terms_hash` column.
  - **Evidence is actively rewritten.** `trg_norm_supplier_ver` has no `WHEN` clause and no column list, so a supplier who accepted `v9` in 2027 and later edits their phone number has the version rewritten to `v4` by that unrelated UPDATE.
  - **The hash is computed at render time from mutable storage.** `compliance_archive/index.ts:98-100` reads `app_secrets.supplier_terms_html` (or `pages.legal_terms_body`) *now* and hashes it; the certificate text asserts the hash fingerprints "the exact Terms text that was accepted", which is false. The migration `20260802115311` rewrote `supplier_terms_html` in place with nine `regexp_replace` calls, retaining no prior version.
  - **Re-signing overwrites the pointer.** `:110-111` updates `signed_terms_url/path/at` with no idempotency guard; `sign` is authenticated by the shared `inbound_secret` and takes an arbitrary email. Editing the terms and re-calling `sign` yields a certificate bearing the new hash against the original `accepted_terms_at`.
  - **Certificates can precede acceptance.** `trg_sign_supplier` fires on **email verification**, before terms acceptance in the flow; `compliance_archive:101` then does `const acceptedIso = rec.accepted_terms_at || new Date().toISOString()` — **fabricating the acceptance timestamp** and printing `IP address: Not recorded`.
  - The certificate names `https://quotesdone.com/supplier-agreement` as the source of the hashed document; that URL serves a different document (see 2.2).
- **Queries:** `pg_get_triggerdef` for all triggers on `leads`/`customers`; `pg_get_functiondef` for `qd_sign_supplier`/`qd_sign_customer`; acceptance/orphan counts.
- **Live state:** 0 acceptances, 0 customers — every defect is latent and fires on the first registration.
- **Severity:** critical. **Blocks launch:** yes. **Blocks Phase 2:** no — though `collections_legal` cites `accepted_terms_version` as dispute evidence, so it propagates into collections.

---

# 3. Control Mode

### 3.1 Every API action explicitly classified — **FAIL**
- **Evidence:** within `os_api` the parity is exact and verified against production — `node scripts/checks/extract_os_actions.mjs` → `62 dispatched, 62 classified`; live `control_mode_action` has **62 rows** and the set difference in both directions is empty; classes `read_only 44 / mutating 14 / mode_control 4`; deployed `os_api` v34 is identical to the repo.
  **But the registry knows only `os_api`.** `grep -rl "control_mode" supabase/functions/` returns exactly one file. `os_ops` — the sibling admin console called from the same React shell via `osClient.ts:42` — dispatches 30 actions behind `os_ops/index.ts:55 if (!(await isAdmin(email))) return J({error:'forbidden'},403);` and nothing else. Eighteen of them mutate and none is in `control_mode_action`: `action_decide, cancel_inquiry, content_save, customer_decide, doc_review_decide, field_set, gl_post, kb_approve, kb_gov, kb_reject, note_add, po_approve, prompt_reject, rfq_outcome, rfq_stage, supplier_decide, task_create, task_done`. `supplier_decide` (approve/reject/ban a supplier), `po_approve` and `gl_post` are precisely the acts the Control Mode migration says it exists to gate. The UI already calls one (`OsxShell.tsx:2175`).
  Separately, `os_api:275` forwards the caller's own JWT to `refunds_api`, whose `authed()` accepts any address in `app_secrets.admin_emails` and whose `action:'resolve'` calls Stripe — a money path reachable with no Control Mode session.
- **Queries:** `extract_os_actions.mjs`; `grep -rl control_mode supabase/functions/`; set-difference SQL against `control_mode_action`; `select action,classification from control_mode_action`.
- **Severity:** critical. **Blocks launch:** yes — a signed-in admin can approve a supplier, post to the GL or refund a customer today without opening Control Mode. **Blocks Phase 2:** yes — `os_action_classification.test.mjs` is hard-wired to `OS_API_PATH`, so every new privileged function ships outside the registry by construction.

### 3.2 Unknown action fails closed — **PASS**
- **Evidence:** two independent refusals. `os_api/index.ts:121-128` returns 403 `action_classification_required` before any handler, after identity. Live `fn_control_mode_require` body: `select classification into v_class from control_mode_action where action=p_action; if v_class is null then ... return jsonb_build_object('allowed',false,...)`. The Phase 1 default-allow branch is gone from production.
- **Queries:** `pg_get_functiondef('fn_control_mode_require')`.
- **Severity:** none. **Blocks launch:** no. **Blocks Phase 2:** no.

### 3.3 Database failure fails closed — **PARTIAL**
- **Evidence:** *exception* path denies — `os_api:223-237` throws on `gerr` and the `catch` returns 503 for anything not `read_only`. *Zero rows* denies at the DB layer (`select ... into` leaves `v_class` NULL → refusal branch). **A null/absent RPC payload allows**: line 228 is `if (g && g.allowed === false)`, so a null `gate` with no error falls through to the handler ungated. The fail-closed form is `if (g?.allowed !== true)`. Not reachable against the current function body (every branch returns a `jsonb_build_object`), but the caller's contract is "allow unless told no" — the same shape this work existed to remove.
- **NOT TESTED** dynamically: proving the null path requires invoking a privileged mutating action.
- **Severity:** medium (latent). **Blocks launch:** no. **Blocks Phase 2:** no — but close it before a second function calls the gate.

### 3.4 MFA purpose-bound to control_mode — **PASS**
- **Evidence:** live constraint `control_mode_challenge_purpose_chk CHECK (purpose = 'control_mode')` — a challenge for any other purpose cannot exist in the table. The verify predicate binds challenge id + identity + purpose under `for update`. Live probe of `fn_control_mode_open`: `reads_phone_verifications=false`, `binds_purpose=true`, `hashes_code=true`, `row_locked=true`. The weaker 7-argument opener was **dropped**, not shadowed — the catalogue lists exactly one overload. Three factors: challenge id + 144-bit nonce + HMAC of the code; the plaintext code never reaches the database; the destination phone is resolved from the registered identity, never from the request body.
- **Severity:** none. **Blocks launch:** no. **Blocks Phase 2:** no.

### 3.5 Only the authorised founder identity can open it — **PARTIAL**
- **Evidence:** live `control_mode_identity` has exactly **one** active row, `management@quotesdone.com`; the second identity is deactivated and cannot mint a challenge. The constraint exists in the live catalogue, not only in a migration: `CREATE UNIQUE INDEX control_mode_identity_one_active_per_phone ON control_mode_identity (phone_secret_key) WHERE active`. All five `control_mode_*` tables are RLS-enabled with zero policies and no `anon`/`authenticated` grants; all ten `fn_control_mode_*` functions are `anon_exec=false, authed_exec=false`.
  **Why PARTIAL:** the index forbids two active identities *sharing a phone*, not a second active identity — `('attacker@x','admin_mfa_phone_2',true)` violates nothing. `fn_control_mode_open` never re-checks `identity.active` (checked only at mint time), and the deactivation sweep was a one-time UPDATE in a migration, not a trigger. And `control_mode_session.mfa_ref` has **no foreign key** and no NOT NULL, so any service-role caller — all 190 edge functions — can insert a session row and be in Control Mode with no MFA at all.
- **Queries:** `select admin_email,phone_secret_key,active from control_mode_identity`; `pg_indexes` + `pg_constraint` for the four tables; `has_function_privilege` sweep.
- **Severity:** medium. **Blocks launch:** no — live state is correct and unreachable by unprivileged roles. **Blocks Phase 2:** no.

### 3.6 Expiry, replay and rate limits work end to end — **PARTIAL / NOT TESTED**
- **Evidence:** all mechanisms are present in the live function bodies — challenge TTL 5 min (`fn_control_mode_challenge_minutes()`), session TTL 15 min, single-use via `consumed_at` under `for update`, prior challenges superseded on mint, `attempts >= max_attempts` (5) lockout, 5-challenges-per-hour rate limit, sweep cron job 179 `*/5 * * * *` active. **Every TTL uses the database clock**; nothing compares against a client-supplied timestamp.
  **Gaps:** none of it has a database constraint behind it (no CHECK on `expires_at > created_at`, none on `attempts <= max_attempts`, nothing preventing a service-role session insert with an arbitrary expiry). The rate limit is `count(*)` then insert with no advisory lock and no index covering `created_at` — it races. `fn_control_mode_identity_active` has zero callers; `v_control_mode_status`, `v_control_mode_identity`, `v_os_action_classification` have zero readers.
  **The gate is shut and there is no key in the console.** `grep -rc "control_mode\|Control Mode" src/` returns **nothing** — the Next.js app has no Control Mode UI. `osClient.ts:22` maps every 403 to `'Not authorized (admin only)'`, while `OsxShell.tsx` calls gated actions directly (`refund_resolve` :1939, `fraud_resolve` :1877, `blog_publish` :1748, `review_decide` :1769, `inbox_send` :1167, `secretary_chat` :1010). Those buttons now fail with no in-product recovery.
  **Production:** `control_mode_session` **0 rows**, `control_mode_challenge` **0 rows**, `control_mode_audit` 13 rows whose only post-hardening event is a single `challenge_started` with **no matching `open`**. Every successful `open` predates the purpose-bound rewrite.
- **NOT TESTED:** whether challenge → WhatsApp → open completes. Settling it requires a real code delivery; the evidence would be an audit pair plus one session row with `mfa_method='control_mode_challenge'`.
- **Severity:** high. **Blocks launch:** yes — the console's mutating buttons are permanently 403 with no way to open the gate, and the hardened path has never completed once. **Blocks Phase 2:** yes.

---

# 4. Supplier pricing

### Surface-agreement matrix

| Surface | Amount | Currency | Interval | Starts | Exemption | Commission |
|---|---|---|---|---|---|---|
| DB `pricing_config` / `fn_supplier_subscription` | 1000 (**column default 100**, no value CHECK) | AED | yearly (CHECK allows `monthly`) | 2027-08-01 | rank ≤ 1000, stored, permanent | none |
| `registered_supplier_count()` + `supplier_api.setRegistration` | 1000 | aed | yearly | **ignored — charges now** | mutable `count(*)`, **≤ 999** | none |
| Stripe checkout | `registration_fee_due × 100` = 100000 fils | aed | `mode=payment` one-off, **no Stripe interval** | n/a | reads `registration_status` | none |
| Public pages EN | AED 1,000 | AED | /year | 1 Aug 2027 | first 1,000, permanent | "no commission" |
| **Public pages AR** | 1,000 درهم | AED | سنويًا | **absent — 0 occurrences of "2027"** | **"free during launch"** | "لا عمولة" |
| Agreement EN / `supplier_terms_html` v5 | AED 1,000 | AED | per year | 1 Aug 2027 | first 1,000, permanent | none |
| **Agreement AR** | 1,000 درهم | AED | سنويًا | **absent** | first 1,000 **then charged** | none |
| **Refund policy AR** | — | — | — | — | — | **2% on every job won** |
| Edge constants (`wa_inbound:155`, `site_assistant:59`, `supplier_pay:11`) | AED 1,000 | AED | /year | 1 Aug 2027 | first 1,000, permanent | none |
| `fn_company_facts_sync` → `agent_knowledge#279` ("OVERRIDES any pricing figure stated elsewhere") | AED 1000 | AED | /yearly | **absent** | "first 1000 FREE" | "NO commission" |

### 4.1 AED 1,000/year — **PARTIAL**
- **Evidence:** live `pricing_config` = `1000 / yearly / AED / free_count 1000`; `v_pricing_consistency` reports all five facts agreeing; `fn_supplier_subscription()` resolves correctly. No hard-coded Stripe price id or `unit_amount` anywhere — `supplier_api:474-476` builds `price_data` from `registration_fee_due` with correct fils conversion. **Divergences:** `pricing_config.supplier_reg_fee` has `column_default '100'` and **no CHECK on the value** (`pg_constraint` shows only currency and period checks), so a re-insert of the singleton yields AED 100; the period CHECK permits `monthly`, which `v_supplier_pricing` would publish while the biller still charges annually; and the auto-synced `agent_knowledge#279`, which declares itself authoritative over all other pricing text, omits the 1 Aug 2027 start date. Also `legal.json:35` states the reveal fee as 2% where the terms and `pricing_config.standard_reveal_rate` say 3%.
- **Queries:** `select * from pricing_config`; `pg_constraint` and `information_schema.columns` on `pricing_config`; `select * from v_pricing_consistency`; `prosrc` of `fn_company_facts_sync`; `select id,topic,left(content,500) from agent_knowledge where ...`.
- **Severity:** medium. **Blocks launch:** no — every live value is correct today. **Blocks Phase 2:** yes — an unguarded `DEFAULT 100` on the only fee column plus an "authoritative" knowledge row missing the start date.

### 4.2 First 1,000 permanently exempt — **FAIL**
- **Evidence:** the rule exists **twice, with different thresholds**. `fn_assign_founding_rank()` uses `max(founding_rank)+1` against `app_secrets.founding_free_limit`, stamped once — stable, deletion-proof, permanent, **1000 exempt**. `supplier_api/index.ts:95-102` `setRegistration()` uses `registered_supplier_count()` — a mutable `count(*)` over `claimed = true or source in ('self_registered','email_inbound')` — against `pricing_config.supplier_free_count`, evaluated *after* insert, so `N < 1000` is false at N=1000: **only 999 free**. Supplier #1000 is simultaneously `subscription_exempt=true` and `registration_status='due', registration_fee_due=1000`.
  The counter drifts (deleting a lead frees a slot; unclaimed `email_inbound` leads consume slots), and `v_supplier_pricing.free_slots_remaining` uses a *fourth* counter over `approval_status='approved'`.
  `setRegistration()` has **no date test**, so from today it marks suppliers `due` and `supplier_api:562` blocks them from quoting — a year before the contractual start.
  **Nothing writes `leads.subscription_paid_until`**: `select proname from pg_proc where prosrc ~* 'subscription_paid_until'` → 0 rows; `grep` in `supabase/functions` → 0 hits. `v_supplier_billing` decides `active` solely from that column, so a supplier who pays stays `due` and `fn_subscription_billing_run` re-invoices every 30 days forever.
- **Queries:** `pg_get_functiondef` for `registered_supplier_count`, `fn_assign_founding_rank(s)`, `fn_supplier_subscription`; `prosrc` of `fn_subscription_billing_run`; `select proname from pg_proc where prosrc ~* 'subscription_paid_until'`; live counts.
- **Severity:** critical. **Blocks launch:** yes. **Blocks Phase 2:** yes.

### 4.3 No supplier commission — **FAIL**
- **Evidence:** no take-rate is charged in code — `fn_supplier_success_engine` states *"NO commission is charged on won jobs"* and `qd_on_refund_resolved()` uses `commission_pct` only as a label. Residual: `supplier_dues.commission_pct` still has `column_default '2'`.
  **But the published Arabic legal text sells a 2% commission.** `src/content/legal.json`, `/refund-policy/ar/html`: «ويكونون مدينين لـ QuotesDone **بعمولة 2% على كل وظيفة يتم الفوز بها** من خلال المنصة» and «تصبح العمولة مستحقة عندما يفوز المورد بوظيفة». The English text at the same slug says the exact opposite. `/acceptable-use/ar/html` twice adds «أو عمولة المورد» where EN says only "Reveal Fee"; `/privacy/ar/html` says «سجلات رسوم الكشف والعمولة».
  The guard cannot see it: `scripts/checks/pricing_consistency.test.mjs:108` matches English only (`/commission\s*(?:of|:)?\s*(\d+)\s*%/gi`) and string-matches the whole JSON rather than per locale. `node --test scripts/checks/pricing_consistency.test.mjs` → **8 pass, 0 fail** with the Arabic clause in the tree.
- **Queries:** `information_schema.columns where column_name ~* '(commission|take_rate|...)'`; `regexp_matches` over `app_secrets.supplier_terms_html`; per-locale JSON walk of `legal.json`; `node --test`.
- **Severity:** critical. **Blocks launch:** yes — a live Arabic legal page contractually asserts a commission the product does not charge and the English agreement forbids. **Blocks Phase 2:** yes — the guard that exists to prevent this is locale-blind and green.

### 4.4 All five surfaces agree — **FAIL**
- **Evidence:** the matrix above. `legal.json:10` names English as governing, which mitigates but does not cure a published Arabic contract stating different commercial terms. The Arabic FAQ contains **zero** occurrences of "2027" and frames the exemption as temporary («خلال الإطلاق» — during launch); the Arabic agreement says free for the first 1,000 **then** AED 1,000/yr, with no permanence.
- **Severity:** critical. **Blocks launch:** yes. **Blocks Phase 2:** yes.

---

# 5. Refunds

Deployed `stripe_webhook` v11 is byte-identical to the repo, so static reading is valid evidence for live behaviour. All refund tables are empty (`refunds` 0, `refund_event_quarantine` 0, `stripe_events` 0).

### 5.1 No fabricated monetary values — **PASS**
- **Evidence:** live column `amount_fils bigint NULL`, `column_default null`; live CHECKs `refunds_amount_fils_check CHECK (amount_fils IS NULL OR amount_fils > 0)`, `refunds_settled_needs_amount`, `refunds_amount_source_check`. `fn_refund_settle` does `v_amount := nullif(coalesce(p_amount_fils,0),0)` and labels source `null` when the amount is null; the update path coalesces against the existing value, not a literal. `stripe_webhook:208-231` asks Stripe for the refund and passes NULL on failure. No other writer exists.
- **Severity:** none. **Blocks launch:** no. **Blocks Phase 2:** no.

### 5.2 Unknown amounts quarantined — **PARTIAL**
- **Evidence:** quarantine fires for unknown amounts, for events with no refund id (`stripe_refund_id_required` + quarantine id), and for events with no refund object; `reason` is NOT NULL. `v_refund_metrics` correctly pairs `refunded_aed` with `settled_amount_unknown` and `amount_unknown_total`.
  **Gap A — un-clearable rows.** `fn_refund_amount_resolve` clears only `where stripe_refund_id = p_stripe_refund_id and reason like 'amount unknown%'`. Rows with reason `'event carried no refund id'`, `'event contained no refund object'` (both `stripe_refund_id NULL`) or `'transition not permitted: …'` match neither predicate, and nothing else updates `resolved_at`.
  **Gap B — nobody reads the quarantine.** `grep -rn "quarantine\|needs_attention\|unreconciled" src/ supabase/functions/ scripts/` matches only inside the writer and `docs/`. `fn_refund_amount_resolve` has zero callers. `needs_attention` is permanently true once any row exists and nothing surfaces it.
- **Severity:** medium. **Blocks launch:** no. **Blocks Phase 2:** yes — an operational queue with no reader and no clear path.

### 5.3 Explicit permitted state transitions — **PARTIAL**
- **Evidence:** live `refund_status_transition` — `{"total":32,"allowed_rows":11,"empty_note":0}`. Terminal states `succeeded`, `failed`, `cancelled`, `rejected`. `fn_refund_transition_allowed` reads the table and defaults to `false` on an undeclared pair; the refusal message appends the declared note. `pg_proc` shows **exactly one** `fn_refund_settle` signature and `fn_refund_status_rank` does not exist — the overload defect is genuinely fixed.
  **The defect:** the create-new-row path hard-codes the status literal and discards the computed `v_status` — `insert into refunds (... status ...) values (..., 'processing', ...)`. A first-seen event carrying `status=succeeded` lands as `processing` with `settled_at` NULL. It self-heals only if a later event arrives.
- **Severity:** high. **Blocks launch:** yes — a dashboard-issued refund can be recorded as in-flight after Stripe has paid it. **Blocks Phase 2:** yes.

### 5.4 Idempotent and out-of-order webhook handling — **PARTIAL / NOT TESTED**
- **Evidence:** `stripe_events.event_id` is unique (`stripe_events_pkey`) and `fn_stripe_event_seen` increments `delivery_count` — but it is **not a gate**: `stripe_webhook:65-68` wraps it in `try { ... } catch (_e) {}`, ignores the return, and proceeds. The real idempotency is state-based and does hold: `refunds_stripe_refund_id_key UNIQUE`, plus `if r.status = v_status then ... 'idempotent',true,'applied',false` under `for update`. Out-of-order is refused **and** quarantined with the declared rule, with no status write. Signature verification is mandatory, HMAC-SHA256 over `t.payload`, 600 s tolerance, constant-time compare.
  **Adversarial:** the webhook signing secret is read at request time from `app_secrets` — RLS-locked from `anon`/`authenticated`, but ~20 other service-role edge functions read and write that table.
- **NOT TESTED:** duplicate and reversed deliveries have never been exercised (0 rows everywhere). Settling it requires a test-mode delivery, which 5.6 shows is impossible today.
- **Severity:** medium. **Blocks launch:** no. **Blocks Phase 2:** no.

### 5.5 Finance reconciliation correct — **FAIL**
- **Evidence:** `v_refunds_unreconciled` correctly keeps unknown-amount rows regardless of status and states a `blocker`; `needs_attention` is derived from real conditions; no double-counting.
  **The failure follows from 5.3.** A dashboard refund whose first delivered event carries `succeeded` **with a known amount** is stored as `processing`, therefore: excluded from `refunded_aed` (filters `succeeded`); excluded from `v_refunds_unreconciled` (predicate is `status='succeeded' OR amount_fils IS NULL`); no quarantine row; `needs_attention` false. `v_refund_metrics` has **no counter for `processing` at all**. Real money leaves the account and appears in no total, no queue and no flag.
  Secondary: no product surface reads any of these views; `refunds_api` operates on `transactions` and never calls `fn_refund_request`/`fn_refund_decide`, so every platform refund arrives labelled `decided_by='stripe_dashboard'`.
- **Severity:** high. **Blocks launch:** yes. **Blocks Phase 2:** yes.

### 5.6 Live/test Stripe webhook configuration complete — **FAIL**
- **Evidence (re-verified by the lead auditor):** the code branches on `charge.refunded`, `refund.updated`, `refund.created`, `refund.failed` (`stripe_webhook/index.ts:184-185`) plus `checkout.session.completed` (`:70`). Stripe `GetWebhookEndpoints` returns one endpoint for account `acct_1To5DvC45SqX5pVb`:
  ```json
  {"id":"we_1TqVtRC45SqX5pVbEbnsquAL","livemode":true,"status":"enabled",
   "url":"https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/stripe_webhook",
   "enabled_events":["checkout.session.completed"],"api_version":"2026-06-24.dahlia"}
  ```
  `has_more:false`. **None of the four refund events is subscribed** — the entire refunds ledger is unreachable in production, consistent with 0 rows everywhere.
  The documented test-mode path is also unconfigured: `app_secrets` holds `stripe_secret_key` and `stripe_webhook_secret` but **not** `stripe_webhook_secret_test` or `stripe_secret_key_test`, so `whsecTest` is `''`, the test branch is dead, and any test delivery is rejected with a bad signature.
  **Contradiction:** `PHASE1_FINAL_ACTIONS.md:152-153` cites "0 quarantine rows, `needs_attention` false" as evidence of health; both are vacuously true because no refund event can reach the system. The 7/7 and 8/8 claims are not supported by the live configuration.
- **NOT TESTED:** whether a test-mode endpoint exists in Stripe's test dashboard — the available credential is live-mode. Moot, since the test secret is absent.
- **Severity:** critical. **Blocks launch:** yes — every refund the business issues today produces no ledger row. **Blocks Phase 2:** yes.

---

# 6. Supplier exception process

**State machine.** Store is `public.leads` (`exception_opened_at / _due_at / _reminders / _last_reminder_at / _closed_at / _outcome`, `licence_gate_reason`). `action_required` + open window → `approved` (via `save_profile`) or → `rejected` (`expired_auto_rejected`, via the sweep). Two unintended states are reachable: `approved`/`verified` with an open window, and `action_required` with a NULL `exception_due_at`.

### 6.1 14-day deadline — **PASS**
- **Evidence:** live `app_secrets.supplier_exception_days = '14'`; `select public.fn_supplier_exception_days()` → `{"days":14}`. Writer `exception_due_at = now() + make_interval(days => v_days)`; reader `l.exception_due_at <= now()` — same column, confirmed against the live function body. **Caveat:** the reminder ladder hard-codes 3/7/12 days rather than deriving from the config, so changing the config breaks the ladder.
- **Severity:** low. **Blocks launch:** no. **Blocks Phase 2:** no.

### 6.2 Reminders — **PARTIAL**
- **Evidence:** cron job **178** `supplier_exception_sweep_daily`, `20 6 * * *`, `active=true`, command `select public.fn_supplier_exception_sweep()`; the function exists. **Never run:** `cron.job_run_details` for jobid 178 → `[]`, against 95,433 rows of history back to 19 July — the job was created today, first fire 3 Aug 06:20 UTC.
  Two silent-loss paths: `send_outbox:137` sets supplier-side mail to `status='held'` when `supplier_emails_enabled` is off, and `:105` never re-selects `held` — terminal. The `isDocRequest` exemption regex matches `expir` (so closure notices send) but not `supplier_exception_reminder` (so reminders die). Separately the reminder loop requires `claimed_by is not null` while the expiry loop does not, so an unclaimed row is auto-rejected having received zero reminders.
- **NOT TESTED:** actual emission. Settled by letting job 178 fire against an aged row.
- **Severity:** medium. **Blocks launch:** no — live config has supplier email enabled. **Blocks Phase 2:** no.

### 6.3 Corrected-document recovery — **FAIL**
- **Evidence:** only `supplier_api` `save_profile` (`:392-434`) re-runs the licence gate and calls `fn_supplier_exception_close(...,'resolved')`. **The Documents tab does not.** `SupplierPortal.tsx:581` calls `supplier_portal` `save_documents`, and `kind='license'` is a first-class document there; `supplier_portal/index.ts:212-213` ends with a plain `update` — no gate re-run, no `approval_status` write, no exception close. The reminder text the sweep writes points at exactly that surface: *"Upload a clear copy of your current trade licence in your supplier portal and your account activates automatically."* A supplier who complies stays `action_required` and is auto-rejected on day 14 **with a valid licence on file**.
  Also: `fn_supplier_exception_close` is `where exception_closed_at is null`, so a supplier auto-rejected then recovered keeps `exception_outcome='expired_auto_rejected'` forever — permanently miscounting recoveries as rejections in the very metric `PHASE1_REPORT.md:65` calls "the number to watch".
  **Contradicts `PHASE1_REPORT.md:44`**, which claims re-uploading a licence runs the gate; true for the Profile tab only. The report's six tests drove the RPCs directly on synthetic rows, never the portal path.
- **Severity:** high. **Blocks launch:** yes. **Blocks Phase 2:** no.

### 6.4 Automatic closure — **PARTIAL / NOT TESTED**
- **Evidence:** the closure block sets `approval_status='rejected'`, `exception_outcome='expired_auto_rejected'`, writes a closing email and a telemetry row; nothing is deleted and it is reversible via `save_profile` (which has no `approval_status` guard). Job 178 is active but has never fired. `cron_job_seen` and `cron_registry` both have 0 rows for it, so it is currently unclassified in the automation inventory. The whole sweep is one transaction with no per-row exception handling — one `notifications` insert failure aborts both loops for the day.
- **Severity:** medium. **Blocks launch:** no. **Blocks Phase 2:** no.

### 6.5 No permanent dead queue — **FAIL**
- **Evidence:** three reachable states with no shipped exit, plus a queue with no reader.
  - **(a)** `action_required` + `exception_due_at IS NULL` — both sweep loops require `exception_due_at is not null`. Reachable because `supplier_api:422` commits the status **before** `:432`'s `try { rpc(fn_supplier_exception_open) } catch (_e) {}`. The migration adding the columns has no backfill, so any pre-existing `action_required` row is permanently in this state.
  - **(b)** `approved`/`verified=true` with an open window — `:430` opens the window on `autoApprove && !licenceOk` regardless of the `:420` guard, so an approved supplier with a lapsed licence opens a window while `approval_status` stays `approved`. Every sweep loop and both views filter `approval_status='action_required'` → never reminded, never closed, invisible. Worse, `fn_supplier_exception_open` then returns `reopened:false` forever, so if that supplier is later demoted the next sweep sees a months-old due date and auto-rejects **immediately, with zero reminders**.
  - **(c)** the same for `verified=true` with pending/NULL status.
  - **(d)** the queue has no reader. `grep -rn "v_supplier_exception"` outside the defining migration returns only `docs/phases/PHASE1_REPORT.md`. No DB function or view references the exception columns. `pending_digest:20` reads `.in('approval_status',['pending','submitted'])` — `action_required` is excluded from the only admin digest. The portal shows a binary badge (`SupplierPortal.tsx:237`) so an `action_required` supplier is literally shown the word "Pending" — the word the migration rejected as *"a promise nobody is going to keep"* — and `licence_gate_reason`, `exception_due_at` and `days_remaining` are never returned to the UI. The "why am I not matched" panel has no `action_required` check and reports such a supplier as eligible.
  - **(e)** `notifications.status='held'` is terminal.
  - **(f)** `match_suppliers_kw` never mentions `action_required`, so such suppliers still receive RFQs while `submit_quote:561` forbids them from quoting.
- **Contradicts `PHASE1_REPORT.md:47/63`** ("Queue depth, visible"): the views exist and are empty, but nothing reads them, so the depth is visible to no one.
- **Severity:** critical. **Blocks launch:** yes. **Blocks Phase 2:** no.

---

# 7. Authority and autonomy controls

| Hard gate | Enforced by | Reachable? | Verdict |
|---|---|---|---|
| money_move | `fn_dept_authority` regex + `org_authority(finance)=gated` | yes (`intent_router` only) | **bypassed** by `refund_within_window`=autonomous |
| ad_spend | `org_authority(marketing)=gated` | yes | enforced |
| authentication_identity | regex `auth` + 15 gated rows | yes | enforced |
| secrets_security | regex `secret` + 15 gated rows | yes | enforced |
| destructive_data | table rows only | yes | cron `retention_purge_weekly` bypasses the model |
| production_deploy | 15 gated rows; real class `code_deploy` = **supervised** | partly | **declared, not enforced** — `auto_deploy` runs every 2 min |
| public_claim_publish | 15 gated rows; real class `content_publish` = **autonomous** | no | **declared, not enforced** |
| legal_commitment | 15 gated rows | yes | enforced |
| supplier_enforcement | regex `ban` | partly | **bypassed** by cron `fn_ban_overdue_dues` |
| autonomy_framework | 15 gated rows | no consumer | **declared, not enforced** |

### 7.1 All hard gates covered — **PARTIAL**
- **Evidence:** the authoritative list is `ops_kb_stage.hard_gates` — **10 rows**, not 8, all `default_tier='gated'`. `v_ops_hard_gate_coverage` reports **10/10 covered**; `org_authority` is 153 rows (126 gated, 24 autonomous, 2 advisory, 1 supervised).
  **But the function that implements them has zero callers.** `fn_ops_authority_check` is the only code reading `ops_kb_stage.hard_gates`; repo-wide grep finds only its definition and comments, and `select jobid from cron.job where command ilike '%fn_ops_authority%'` → `[]`. The actual runtime gate is `fn_dept_authority`, called from exactly one place (`intent_router/index.ts:61`), which never reads the hard-gate table and caps by regex on the class *name*. The two vocabularies differ, so gated corpus classes coexist with autonomous runtime classes doing the same thing: `fn_dept_authority('customer_success','refund_within_window')` → `autonomous, capped false`, with a live `refunds_api` executor.
  **Contradicts `PHASE1_REPORT.md:122`** — true of `fn_ops_authority_check`, but that function is on no execution path.
- **Severity:** high. **Blocks launch:** yes. **Blocks Phase 2:** no.

### 7.2 No imported `target_state` rule active — **PASS**
- **Evidence:** **1,317 `target_state` records, none approved.** `workflows 0/18 enabled`, `event_subscriptions 0/100 active`, `decision_rules 0/240 enabled`; the `enabled`/`active` columns default FALSE. No cron job, edge function, view or DB function outside the corpus's own helpers references `ops_kb_stage`; the schema is `revoke all from public, anon, authenticated`, RLS on every table with zero policies. `public.event_subscription` (the live table, 48/48 active) is a different, pre-existing object.
  Minor latent defect: `fn_ops_department_context` filters on `validation_status` but not `implementation_status`, so it would hand a model 1,290 `reviewed` `target_state` records as "department knowledge" — it has no callers today.
- **Severity:** none. **Blocks launch:** no. **Blocks Phase 2:** no.

### 7.3 No company-operations workflow active unintentionally — **PARTIAL**
- **Evidence:** imported workflows are all disabled. But **148 cron jobs, 143 active**, and several autonomous runners mutate business state with no human in the loop: `cos_execute_hourly` (runs any registered executor for `status='assigned'` tasks), `dept_plan_daily` (tier from a hard-coded list, not the authority model), `event_dispatch_15min` (`fn_event_dispatch` inserts `org_tasks ... 'assigned','autonomous'` — hard-coded, never calls `fn_dept_authority`), `autonomy_dispose_hourly` (sets `leads.approval_status='approved'`), `auto_deploy`/`site_autodeploy` (production deploy every 1–2 minutes, no approval record), `dues_ban_overdue_daily` (`update leads set banned=true`), `subscription_billing_daily`, `retention_purge_weekly`.
  `cos_execute/index.ts:127-146` re-checks nothing — whoever writes the row decides. Of the three writers, only `intent_router` consults the authority model. `fn_autonomy_class` places `refund_within_window → 'ack'` **before** the money rail.
  **Last 48 h:** `site_autodeploy 2880/2880 ok`, `auto_deploy 1440/1440 ok`, `cos_execute_hourly 48/48 ok`; `org_tasks` 7 days: `done/autonomous 68`; `agent_actions` 14 days: **`auto_done 501`**. `leads.banned = 0`, and no `refund_within_window` or `approve_supplier` has fired — luck of scheduling, not a control.
- **Severity:** high. **Blocks launch:** yes. **Blocks Phase 2:** no.

### 7.4 Broad autonomy remains blocked while WI-001 is open — **FAIL**
- **Evidence (re-verified by the lead auditor):** `spec_backlog` id 201 — `WI-001`, `status='open'`, `priority=0`, notes *"BLOCKS BROAD PRODUCTION AUTONOMY."* Nothing reads `spec_backlog` to refuse anything: no CI check, no trigger, no code path. Meanwhile the switch is already on — `app_secrets`: `agent_autonomy_enabled='true'` (28 Jul), `agent_autonomy_from='2026-07-30'`, `cos_frozen='false'`, no `ai_kill_switch` row; `fn_role_of('cfo')` → `'agent'`; 66 active `org_agents`. Combined with 7.3, autonomy was switched on 30 July and WI-001 was opened 2 August **on top of a running system**. Widening it further requires only an `update org_authority` or one new `org_action_executor` row — no approval object, no second party. `cos_frozen` is the only mechanical brake and it is a single unprotected `app_secrets` row.
- **NOT TESTED:** whether `cos_frozen='true'` halts an in-flight run. Settled on a branch project with a synthetic `org_tasks` row.
- **Severity:** critical. **Blocks launch:** yes. **Blocks Phase 2:** no — WI-001's own text permits shadow development.

---

# 8. Repository and production integrity

### 8.1 Phase 1 production objects represented in Git — **PASS**
- **Evidence:** the Phase 1 set was derived independently as the 20 applied migrations matching `p1\_%` or `p1h\_%`, versions `20260802142957`–`20260802154746` (10 + 10; no `p1_01` exists in either place). **Applied 20 / present 20 / missing 0.** Objects extracted from the applied statements — 8 tables, 23 function names, 11 views, 12 indexes, 1 trigger, 2 cron jobs — are all present in production and all have repository source. The one apparent gap, `fn_refund_status_rank`, is a deliberate `drop` at `p1h_07:255`. **Zero production objects with no repository source.**
  Edge functions: deployed `os_api` v34 and `supplier_pay` v3 match the repo on length, line count, head, tail and full marker census. `stripe_webhook` v11 was separately confirmed identical in area 5.
- **NOT TESTED:** git history (no `.git` in the extract); `supplier_api` deployed body (size).
- **Severity:** none. **Blocks launch:** no. **Blocks Phase 2:** no.

### 8.2 No production/repository drift for Phase 1 — **PARTIAL**
- **Evidence:** row direction is clean both ways (20/20/0/0). Live-definition drift: none — all 22 live Phase 1 function bodies are contained verbatim in the applied SQL, and no later migration re-creates any of them.
  **Content drift: 2 of 20 files are not the SQL that was applied.** Whitespace-normalised md5, repo vs `array_to_string(statements,';')`:

  | file | repo | applied | md5 |
  |---|---|---|---|
  | `…154210_p1h_06_control_mode_single_identity.sql` | 3,363 B | 3,554 B | `feb009a1…` ≠ `a2d24421…` |
  | `…154652_p1h_09_drop_superseded_refund_settle_overload.sql` | 519 B | 685 B | `87aa6a37…` ≠ `dff4bb60…` |

  The differences are a comment block and a trailing diagnostic `select` — not DDL — but the repo file is provably not the applied artefact.
  **The parity tooling cannot detect it, by construction:** `scripts/verify_repo_production_parity.mjs:26` hard-codes `WIN_FROM='20260802165328', WIN_TO='20260802184500'`, so every Phase 1 version falls outside the gate window and into buckets excluded from the exit code; and the SHA-256 check at `:79-89` only runs for files carrying an `-- Applied version:` header, which hand-authored Phase 1 files do not. Adjacent evidence of renamed migrations: `p2_01`/`p2_02`/`p2_03` are stored under versions that were never applied, and both parity scripts still exit 0. **Neither script is referenced by `.github/workflows/`.**
- **Severity:** medium. **Blocks launch:** no. **Blocks Phase 2:** yes as a control gap — the parity gate structurally cannot fail on Phase 1 or on renamed migrations.

### 8.3 Rollback procedures actually restore the prior state — **FAIL**
- **Evidence (re-verified by the lead auditor):** **there are no Phase 1 rollback artefacts at all.** `supabase/rollback/` contains only `p2_c1_stage_a_down.sql` and `p2_c1_stage_b_down.sql`. Production `%rollback%` functions are all P2-C1 or unrelated. `grep -rn "p1.*rollback|rollback.*Phase 1"` across `docs/`, `scripts/`, `supabase/` returns **zero hits**.
  Every Phase 1 object therefore has zero rollback coverage: 8 tables (`refunds`, `refund_event_quarantine`, `refund_status_transition`, the five `control_mode_*`), 22 functions, 11 views, 12 indexes, 1 trigger, 2 cron jobs. Phase 1 also contains **irreversible** forward changes: `p1h_07` drops `fn_refund_status_rank`; `p1h_09` drops the 6-argument settle overload; `p1h_10` relaxes nullability; and `p1h_06` deactivates every non-primary Control Mode identity, consumes their challenges, closes their sessions and appends free text to `note` — nothing restores the prior `active` flag or the original notes.
  **The one rollback that does exist is broken as written.** `p2_c1_stage_b_down.sql:8-13` instructs the operator, as mandatory step 2, to re-apply five files — `20260802190000_p2_c1_stage_a_mep_model.sql` and four siblings. **All five paths do not exist**; the files were moved to `migrations-superseded-consolidated/`. Step 1 drops `shared.brand_acceptance_policy` with `cascade` first, so following the documented procedure leaves those Stage A objects dropped and unrestorable from the path given.
- **NOT TESTED:** executing any rollback, including inside an aborted transaction — out of scope.
- **Severity:** critical. **Blocks launch:** yes — a refunds ledger and a privileged-action gate shipped with no reversal path. **Blocks Phase 2:** yes — the only rollback in the repository fails at step 2.

### 8.4 CI checks genuinely pass — **PARTIAL**
- **Evidence:** `.github/workflows/checks.yml` has three jobs — `checks` (`npm test`), `typecheck` (`npm ci` + `tsc --noEmit`, which excludes `supabase/`), and `deno-check` (gated over 4 files; the advisory step over all 191 carries `continue-on-error: true` — the **only** one in the repo, and it is on the advisory step, not the gate). No `deno.json` exists, so the gate runs at strict defaults.
  **Observed:** `npm test` → **31 pass / 0 fail / 0 skipped**, 581 ms. This **contradicts `PHASE1_FINAL_ACTIONS.md:155` ("28/28")** and the hardening report's 25 — both stale.
  **Could not run:** `typecheck` (no `node_modules`, `npm ci` cannot resolve offline) and `deno check` (deno not installed). CI status for `658e675` is **NOT TESTED** — the reports' "run #5 green" refers to `d54fc12`, a different commit.
  **Would the green checks catch what they exist to catch — partially.** All 31 tests are regex/substring assertions over repository source text; none executes a handler. Two are genuinely self-verifying (an injected unclassified action; a synthetic wrong price). The weakest is `stripe_refund_events.test.mjs:22-26` — `src.includes('refund.failed')` on raw source with no comment stripping, so a comment would satisfy it. More importantly, **the tests and `deno check` run against the repository copy, not the deployed function**; `supabase/functions/SYNCED_FROM_PRODUCTION.md` records that exact failure twice (27 Jul: 10 functions behind production; 29 Jul: **31 deployed and absent from the repo**). No CI job compares deployed functions or applied migrations against git.
- **Severity:** medium. **Blocks launch:** no. **Blocks Phase 2:** no — but a green build is evidence about the repository, not about production.

---

# 9. Remaining launch blockers

### 9.1 Universal attachment sanitisation — **FAIL** · *not started*
No shared sanitisation module exists (`supabase/functions/_shared/` contains one file, `llm.ts`). Exactly **one** magic-byte check exists across 192 edge functions (`reg_fetch/index.ts:32`, `%PDF`). Of 15 storage buckets, 14 have `allowed_mime_types = null`; the one exception matches the **client-declared** content type. The only malware control is `fn_run_vt`, a VirusTotal **hash lookup** capped at `limit 4` files/day over 4 of 15 buckets — `select status,count(*) from vt_results group by 1` → `[{"status":"unknown","n":52}]`, i.e. 100% inconclusive. And the storage RLS policy lets any authenticated user write arbitrary bytes straight into `supplier-docs`, bypassing every edge function.

| # | Inbound path | Size cap | Server allow-list | Magic-byte | Metadata strip | Re-encode | Malware |
|---|---|:--:|:--:|:--:|:--:|:--:|:--:|
| 1 | Customer drawing (`customer_api:169`) | 25 MB | — | — | — | — | post-hoc |
| 2 | Drawing → redacted (`drawing_redact:102`) | ≤8 pages | — | — | Y | Y | post-hoc |
| 3 | Reference photos (`attach_photos:19`) | ≤24 | — | — | Y | Y | post-hoc |
| 4 | Supplier portal docs (`supplier_portal:145`) | — | — | — | — | — | post-hoc |
| 5 | Supplier API licence/profile (`supplier_api:256`) | — | — | — | — | — | post-hoc |
| 6 | Quotation file (`supplier_api:549`) | — | — | — | — | — | post-hoc |
| 7 | Quote images (`extract_quote`) | — | — | — | — | — | — |
| 8 | Email-inbound attachments (`resend_inbound:186`) | ≤6 | — | — | — | — | post-hoc |
| 9 | Email-inbound receipts (`resend_inbound:161`) | ≤8 | header string only | — | — | — | post-hoc |
| 10 | Inbound email images (`inbound_email:56`) | — | declared only | — | — | — | n/a |
| 11 | Admin invoice upload (`finance_doc:26`) | — | — | — | — | — | — |
| 12 | Console extract (`extract_text:18`) | — | declared only | — | — | — | — |
| 13 | CAD conversion (`cad_convert:23`) | — | ext from filename | — | — | 3rd party | — |
| 14 | Voice (`transcribe:22`) | ~22 MB | declared mime | — | — | — | n/a |
| 15 | Regulatory PDF (`reg_fetch:30`) | min 30 KB | Y | **Y** | — | — | — |
| 16 | Dropbox ingest (`assets_ingest:16`) | <200 KB | Y | — | n/a | n/a | n/a |
| 17 | KB corpus put (`kb_corpus_import:151`) | — | forced text/plain | — | n/a | n/a | — |
| 18 | **Direct client storage write** (RLS) | 1 GB | declared only | — | — | — | post-hoc |
| 19 | Source ingest (`put_src`, `src_io`) | — | — | — | — | — | — |
| 20 | WhatsApp inbound | n/a — no media handling | | | | | |
| 21 | Brand upload | decommissioned (410) | | | | | |

**Ten paths have no sanitisation of any kind:** 4, 5, 6, 7, 8, 11, 12, 13, 18, 19.
**Severity:** critical. **Blocks launch:** yes. **Blocks Phase 2:** yes.

### 9.2 Post-redaction verification — **FAIL** · *not started*
`grep -rniE "redaction_verif|verify_redact|post_redaction|second_pass|leak_check"` → zero relevant hits. `drawing_redaction_runs` records `status, pages_in, pages_out, skipped` — every one written by the process about itself (`drawing_redact:37-54`), and `status='complete'` at `:120` means only that the compositing loop did not throw. No OCR re-scan, no second model, no pixel diff, no human sample. See also check 1.4.
**Severity:** high. **Blocks launch:** yes. **Blocks Phase 2:** no.

### 9.3 Immutable `supplier_safe_brief` — **FAIL** · *built but not on the live path*
`grep -rn "supplier_safe_brief\|safe_brief"` → **0 hits**. What exists is `public.inquiries_supplier_safe`, a view over six mutable `*_masked` shadow columns maintained by `trg_mask_inquiry_contact`, a **BEFORE INSERT OR UPDATE** trigger — no write-once constraint, no append-only table, no version row. **Readers: zero.** `grep -rn "inquiries_supplier_safe" --include=*.ts src supabase/functions` → 0 hits, against **69 occurrences of `from('inquiries')` across 31 edge functions**. The supplier inbox reads raw columns and re-derives safety in TypeScript (`supplier_api:497, 522-531`). **Contradicts `docs/audit/backend-current-state.md:36`** — "present" is not "on the live path".
**Severity:** high. **Blocks launch:** yes. **Blocks Phase 2:** yes.

### 9.4 Canonical `dispatch_eligible` gate — **FAIL** · *built but not on the live path*
`dispatch_eligible` exists only in the P2-C1 model (`v_workstream_dispatch`, `v_group_dispatch`). `grep -rn "v_workstream_dispatch\|v_group_dispatch\|dispatch_eligible" src supabase/functions` → **0 hits**; the only DB readers are P2-C1 self-test and rollback scaffolding. The live concept is `inquiries.rfq_ready`, enforced in four independent places (`trg_rfq_complete`, `trg_autodispatch_inquiry`, `dispatch_inquiry:90`, `trg_gate_incomplete_match`).
**The divergence that matters:** `customer_api` runs its own dispatcher, `matchAndNotify` (`:109-146`, called at `:523, :536, :544`), which never checks `rfq_ready`. When `rfq_ready` is false, `trg_gate_incomplete_match` returns `null` and drops the match **silently** — the insert reports no error, `customer_api` records `outcome:'dispatched'` and **still emails every supplier**. When it is true, `fn_notify_matched_supplier` fires and the supplier gets a **second** `new_inquiry` notification. Two of the three call sites also pass `useRouter:false`, bypassing the adjudicator for a third eligibility definition.
**Severity:** high. **Blocks launch:** yes. **Blocks Phase 2:** yes — `PHASE2_KICKOFF.md:17,44` names `dispatch_eligible` as the Phase 2 completeness output.

### 9.5 Shared `inbound_secret` separation (WI-001) — **FAIL** · *not started*
Measured blast radius: **43 of 148 cron jobs** reference it (40 active), reaching **42 distinct edge functions**; **20 public DB functions** embed it; of 192 edge functions, **137 mention it, 135 accept `__secret === inbound_secret`, and 96 have no `auth.getUser` alternative** — the secret is their sole authenticator. `app_secrets` holds one `inbound_secret` (last touched 7 July) plus a rotation artefact; **no `inbound_secret_<context>` keys exist**. The design's objects do not exist: no `internal_credential` table, no verifier function, no dual-accept window, no last-used-at view, no attribution column. `spec_backlog` id 201 is `open`, priority 0, updated today; related item 190 (split deployment authority off the same secret) is still pending.
**Contradiction:** WI-001 and `PHASE1_HARDENING_REPORT.md:179` both claim "146 cron jobs (141 active)". Production says **43 (40 active)** — the document apparently counted all cron jobs rather than those passing the secret, and sized its risk estimate off the wrong number. The direction of the finding is right; the headline is wrong by ~3.4×.
**Severity:** critical. **Blocks launch:** yes. **Blocks Phase 2:** no for shadow work; yes for autonomy.

---

# Cross-cutting patterns

1. **Built, verified, and then not wired in.** `inquiries_supplier_safe` (0 readers), `v_workstream_dispatch.dispatch_eligible` (0 readers), `fn_ops_authority_check` (0 callers), `v_supplier_exception_queue`/`_health` (0 readers), `v_refund_metrics`/`v_refunds_unreconciled`/`v_refund_quarantine_open` (0 readers), `fn_refund_amount_resolve` (0 callers), `fn_control_mode_identity_active` (0 callers), and Control Mode itself (no UI). Seven independent controls exist as correct objects that nothing consumes. Several Phase 1 report claims are true of the object and false of the system.
2. **The checks that would have caught this are scoped so they cannot fail.** `pricing_consistency.test.mjs` is English-only and passes with an Arabic 2% commission clause in the tree. `os_action_classification.test.mjs` is hard-wired to `os_api` and cannot see `os_ops`. `verify_repo_production_parity.mjs` hard-codes a window that excludes all of Phase 1 and is not referenced by CI at all. Every one of the 31 repository tests asserts on source text, never on behaviour, and always against the repo rather than what is deployed.
3. **Emptiness is being read as health.** `refunds` 0, `customers` 0, `inquiries` 0, quarantine 0, `needs_attention` false — these are consequences of pre-launch state and, for refunds, of events that are not subscribed. Almost every defect above is latent and fires on the first real user.
4. **Production-only objects.** `qd_norm_supplier_ver` and `qd_norm_customer_ver` are live triggers that rewrite legal evidence and appear in **no migration file**.

---

# Verdict

## **C. Phase 1 requires major rework.**

Nineteen of 42 checks fail and 15 more are partial. Eleven distinct findings are launch-blocking at critical severity, and they are not a tail of polish items — they sit on the four things Phase 1 was created to guarantee.

The determining findings:

- **The refunds ledger is inert.** Only `checkout.session.completed` is subscribed on the sole Stripe endpoint, so none of the four refund events the code handles is ever delivered. Everything Phase 1.7 built has never executed, and the reports' "0 quarantine rows, `needs_attention` false" is a measurement of an unreachable subsystem. Separately, `fn_refund_settle` hard-codes `'processing'` on the create path, so a settled external refund can leave the bank and appear in no total, no queue and no flag.
- **The anonymity promise has no verification behind it.** `drawing_redact` publishes a page completely unmodified whenever the model says `has_identity:false`, counts it as redacted, and records the run `complete`.
- **Legal evidence is self-corrupting.** A production-only trigger rewrites `accepted_terms_version` to `'v4'` on every write, five version strings disagree, three different supplier agreements are in circulation, the certificate hash is computed at render time from mutable storage, and a certificate can be issued with a fabricated acceptance timestamp before anyone has accepted anything.
- **A published Arabic contract sells a 2% supplier commission** the product does not charge and the English agreement forbids — with the CI guard that exists to prevent exactly this passing green because it is English-only.
- **Every supplier's KYC documents are readable and writable by any authenticated account** through a storage policy with no owner predicate, and no inbound path in the product sanitises file content.
- **Control Mode gates one console and not its sibling**; 18 mutating `os_ops` actions and a Stripe-calling `refunds_api` are reachable with an admin JWT alone — and there is no UI anywhere to open Control Mode, so the gate is shut with no key.
- **Autonomy is already live** (`agent_autonomy_enabled=true` since 30 July, 501 auto-completed agent actions in 14 days, production deploys every two minutes) while the work item that declares itself the precondition for it is open at priority 0 and enforced by nothing.
- **Phase 1 has no rollback of any kind**, and the only rollback in the repository cites five files that do not exist.

What is genuinely sound should not be lost in the rework: the refunds transition matrix (32 rows, 11 allowed, complete coverage, every rule reasoned, the overload defect really fixed and `amount_fils` really nullable); Control Mode's purpose-bound MFA and fail-closed unknown-action handling; the redacted-path provenance model; the imported corpus, which is correctly inert (1,317 `target_state` records, none approved, nothing reachable); and the Phase 1 migration set, which is 20/20 represented in Git with every object traceable to source. The engineering is not weak. The failure is consistently at the last connection — controls that were built, tested against themselves, and never put on the path that real traffic takes.

**Recommended sequencing before any launch decision** (not performed here): subscribe the Stripe refund events and re-verify 5.3–5.5 against real delivery; close the `supplier-docs` storage policy; drop the two `qd_norm_*_ver` triggers and give acceptance an immutable, hashed record; correct the Arabic legal pages and make the pricing guard locale-aware; extend the action registry to `os_ops` and `refunds_api` and ship a Control Mode UI; add post-redaction verification; put `inquiries_supplier_safe` and a canonical `dispatch_eligible` on the live read paths; author a Phase 1 rollback and rehearse it; then re-audit.
