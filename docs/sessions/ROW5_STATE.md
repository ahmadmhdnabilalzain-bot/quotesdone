# ROW #5 — STATE AT 2026-08-07 ~00:50 UTC

## FOUNDER DECISION TAKEN THIS SESSION
**Generate demo suppliers to test the specs. Structure ready and deployed. NO staging — production
is the target.**

Consequence, and it is a design constraint not a footnote: a demo supplier on production that is
*matchable* would receive real customers' RFQs, surface in real search results and be revealed to
real customers. That is the same harm the founder refused when flipping `verified` on scraped rows
was proposed — arriving by a different door. **Demo rows are fenced: marked, excluded from
matching/search/reveal, and removable.** A check that passes only because a demo row leaked into a
real customer's result set is a FAILING check. Still refused: touching `verified` /
`approval_status` on any of the 20,464 scraped rows.

## DONE
- **Row #2 re-run: 107/110.** Unchanged. Same three NOT MET.
- **234 requirements enumerated** → `docs/sessions/ROW5_REQUIREMENTS.md`, per-section table + the
  four known overlap risks to resolve in refutation.
- **`portal_surface.mjs` parameterised**, not copied. New `surfaceFor(entries, entryPath)`; `/me`
  exports kept under their original names as its first instantiation so every row #4 module is
  untouched. New `SUPPLIER` export deliberately has **no `entryPath`**, so `SupplierPortal.tsx`
  cannot be hardcoded by a section module — the row #4 104-vs-124 bug is made unwritable rather
  than merely forbidden.
  - Smoke-tested: customer 62 files / 24 fns, supplier 14 files / 14 fns, one `importClosure`.
- **`verify_supplier_blueprint.mjs` written**, `TOTAL = 234`, dir `supplier_blueprint/`.
  Plumbing-tested: reports `0 checks ran, the spec has 234` and scores nothing. Correct.

## MODULE 1 BUILT AND RUNNING — `entry_and_onboarding.mjs`, §1 §2 §3, EXPECTED 29
Registers 29/29, zero errored, no denominator mismatch. Raw run reads **17/29**.
**THAT NUMBER IS NOT A SCORE AND MUST NOT BE QUOTED.** It has not been refuted, and three defects
were already found in the instrument itself — two fixed, the rest listed below.

### Instrument defects found and FIXED this session
1. **`B()`/`Q()` emitted bare `true` / `'...'`, not a statement.** `req()` sends its 4th and 5th
   arguments to the management API as the whole query, so all nine §1 checks returned 42601 and
   were booked ERRORED — unmeasured, not MISSING. Both helpers now emit `select ...`.
2. **`n()` used `String.match` with a NON-global regex**, so every count was 1 (or 1+capture
   groups), never a count. It made `entry-not-form-wall` read "3 form controls" and **PASS** its
   `< 20` bar against a real 21 — a **false MET** — and put a wrong number in every evidence
   string (defect class #5). The `g` flag is now forced.
   Before → after: form controls 3→21, registration tokens 1→23, animation tokens 1→7.

### REFUTATION TARGETS — suspected FALSE METs, attack these before any percentage
- `onb-extract-*` (6 MET). The two-leg test is far too loose: `/\bcategory\b/i`,
  `/\blocation\b|\bcity\b/i` match any CRUD form. The spec means **AI extraction from a free-text
  conversation**, not the word appearing. Almost certainly 6 false METs.
- `onb-ai-conversation` (MET). `ChatWidget.tsx` — the **marketing chat bubble** — is in the
  supplier closure. Row #4's own module header warns that a marketing chat bubble is not the
  portal's AI assistant. The `role:'user'` shape probably came from it.
- `twin-capabilities-list`, `twin-product-count`, `twin-certifications` (3 MET). Same loose-regex
  problem; `/\bproducts\b/` matches a column name.
- `entry-bg-moving-connections` (MET on **1** token). Weak evidence for "moving connections";
  should also require the animation leg.
- `onb-creates-profile` (MET). Verify the write is the ONBOARDING path, not `save_profile` from
  the existing settings form.

### Confirmed TRUE findings from module 1 (these are real build orders)
- `twin-object` MET: **3 non-writer routines read `supplier_score`, 20,464 rows**. The twin's
  inputs exist for every company on production.
- `twin-supplier-visible` MISSING: **0 twin tokens across all 14 files.** Computed for 20,464
  companies, rendered to nobody. This is the row's headline defect, measured.
- `twin-company-strength`, `twin-production-capacity`, `twin-best-opportunities` MISSING on BOTH
  legs — no endpoint and no surface.
- `entry-not-form-wall` MISSING: **21 form controls.** The spec explicitly rejects the form wall.
- `entry-bg-world-map` MISSING: 0 map/geo tokens.

## NEXT, IN ORDER
1. Write the six section modules into `scripts/staging/supplier_blueprint/`. Suggested split and
   denominators (must sum to 234, each module `export const EXPECTED = n`):
   | module | sections | EXPECTED |
   |---|---|---|
   | `entry_and_onboarding.mjs` | §1 §2 §3 | 29 |
   | `command_and_environment.mjs` | §4 §5 §6 | 31 |
   | `product_intelligence.mjs` | §7 §8 | 23 |
   | `rfq_and_quoting.mjs` | §9 §10 §11 §12 | 33 |
   | `performance_and_risk.mjs` | §13 §14 §15 §16 §17 | 39 |
   | `collab_map_mobile_ui.mjs` | §18 §19 §20 §21 §22 §23 §24 | 79 |
2. **Refute before quoting any percentage.** Attack MET and MISSING equally. Check every threshold
   against "could a correct implementation reach this?" — row #4 shipped one that got harder the
   more correct the product became.
3. Build in dependency order: schema → routine → edge function → surface → deploy BOTH → prove by
   execution → re-score.

## MEASURED FACTS — DO NOT RE-DERIVE
Production (`htdblwldjkcgjvmqkbeh`), 2026-08-07:
```
leads 20464 | verified 0 | approved 0 | claimed 0 | claimed_by 0
registration_submitted 0 | owner_email_verified 0
quotes 0 | inquiries 0 | inquiry_matches 0 | supplier_capabilities 0
supplier_score 20464  (reliability non-null on ALL 20464)
lifecycle: not_contacted 20399 | contacted 57 | undeliverable 5 | responded 3
```
Readers, measured **from a file** (see trap below), production:
```
leads 137 | decision_log 15 | supplier_capabilities 3 | inv_items 4 | inv_stock_moves 6 | quote_items 4
supplier_product 0 | supplier_product_variant 0 | supplier_catalog 0   ← 0 by regex AND by ilike
```
Surface closure: **supplier 14 files / 29 components / 14 edge fns** vs customer 62 files / 75
components. 3D tokens ≈0 (one stray), chart importers **0**, framer-motion **0**.
`SupplierPortal.tsx` is 100,935 bytes — one file. Split it EARLY, before checks are written
against it.

Supplier-reachable edge functions (14, measured — the brief said 9):
`ai_gateway kyc license_extract login_otp messages_api profile_ai quote_extract rfq_flag role_guard
supplier_api supplier_pay supplier_portal supplier_review wa_optin_set`

## ⚠ TRAP FOUND AND CONFIRMED THIS SESSION — COSTS EVERY READER CHECK IF FORGOTTEN
**`node -e` through the shell silently eats the `\y` word-boundary escape**, so every `READERS()`
scan run that way returns **0 — indistinguishable from "nothing exists"**. This is defect class #1
arriving through the tooling instead of the SQL.

Caught by control: `leads` reads **0** via `node -e`, **137** from a `.mjs` file. `READERS()` itself
is sound. **All scorer work goes in files. Never measure with `node -e`.**

## ROW #2 — WHY IT DID NOT CLOSE, MEASURED
The brief expected this session to run after 10:49 UTC. It ran at **00:33 UTC**. Measured directly
on production:
```
utc_now                2026-08-07 00:33:07
gate_last              2026-08-06 10:15:03+00   ← leaves the 24h window 2026-08-07 10:15:03
gate_empty_in_window   17  (was 29; draining as predicted)
```
`comp-10-02-gather-data` frees at **10:15:03 UTC**, `comp-14-should-escalate` at **10:49:05 UTC** —
roughly **9h40m after this session started**. No code will change either verdict; re-running before
those times cannot close them. `contract-consolidation` remains the founder throughput decision
(19% of 675 closed against a required 50%); unchanged and not code-blocked.

---

## REFUTATION ROUND 1 COMPLETE — MODULE 1 IS `10/29`, AND THAT NUMBER IS QUOTABLE
Raw run was 17/29. Refutation removed **seven false METs**. Every surviving MET now names the
function or file that satisfied it, so the evidence computes the verdict.

| defect | checks | cause | fix |
|---|---|---|---|
| marketing bubble certifies the portal | `onb-ai-conversation` | `ChatWidget.tsx` is in the supplier closure and supplies **5** `role:'user'` tokens; the portal itself supplies **0** | assistant legs score over `ASSIST_NC` = surface minus the marketing widget |
| a form field read as AI extraction | 6 × `onb-extract-*` | `/\bcategory\b/` matched a `<label>`; `/\blocation\b\|\bcity\b/` matched **26** address fields. A field the supplier TYPES is the opposite of §2's claim | gate is the mechanism: one AI fn must name the field **and** carry a prompt/schema |
| proximity scan across a concatenation | 6 × `onb-extract-*` (2nd attempt) | `field … within 400 chars … json` over **14 functions joined end to end** — a field in `supplier_api` paired with `json` in `wa_optin_set` | scored **per function**, never over the join |
| any-of-14 read as "the twin's endpoint" | 3 × `twin-*` | `re.test(FN)` searched all 14 joined; `capability` matching in `rfq_flag` certified a twin field | scored per-fn over `supplier_portal`/`supplier_api`/`profile_ai`, and the evidence NAMES them |
| one token read as "MOVING connections" | `entry-bg-moving-connections` | single loose match, no motion leg | requires connection **and** animation tokens |

**Method note for the remaining five modules:** three of the five defects above are the same error —
*a scan whose population is an artefact of the scan* (a concatenation, a closure joined end to end,
a widened window). Write every leg per-file or per-function from the start, and make the evidence
name the file or function that satisfied it. An unnamed "endpoint yes" cannot be refuted.

### Module 1 surviving METs (10) — each with named evidence
`entry-landing-route` · `entry-bg-animated-network` · `entry-bg-moving-connections` ·
`onb-freetext-input` · `onb-creates-profile` · `onb-extraction-routine` · `twin-object` ·
`twin-capabilities-list` · `twin-product-count` · `twin-certifications`

---

## MODULE 2 BUILT AND REFUTED — `command_and_environment.mjs`, §4 §5 §6, EXPECTED 31
Modules 1+2 register **60/60**, zero errored, no denominator mismatch. Combined: **18/60**.
§4 = 4/10, §5 = **0/12**, §6 = 4/9 (approx; see run output).

Shared helpers now live in `scripts/staging/supplier_checks.mjs` — **outside** `supplier_blueprint/`,
because the runner imports every `.mjs` in that directory as a section module and books anything
without a default export as a shortfall, which invalidates the denominator.

### Refutation round 2 — three more false METs removed in §4
| check | why it was false |
|---|---|
| `cc-verified-badge` | all 13 `/verified/i` matches were `mobile_verified` / `phone_verified` / "Required to get verified" — the **phone-verification flow in a settings form**. A confirmed mobile is not a Verified Supplier. Now matches `approval_status`/`approved` and prints the 15 excluded account-verification tokens. |
| `cc-assistant-panel` | all 6 matches were the **support chat inside SupplierPortal.tsx** — "Our assistant handles most questions instantly", `assistant_pre:'Assistant: '`. **The chrome fence is file-level and this leak was intra-file** — excluding ChatWidget.tsx was not enough. Now subtracts support-chat vocabulary and requires PROACTIVE guidance. |
| `cc-perf-quality` | render leg passed on the prose *"it has not reached the quality mark"*. A latent false MET: it would have flipped the moment an endpoint existed. Metric legs now require an identifier shape (`quality_score`), never a bare English word. |

### ⚠ NEW DEFECT CLASS, FOUND IN §4 — worth carrying into every remaining module
**An intra-file vocabulary leak.** Row #4's lesson was "exclude the marketing chrome", which is a
FILE-level fence. It does not help when the wrong thing lives in the right file. A 100KB
`SupplierPortal.tsx` contains the settings form, the support chat AND the command centre, so any
whole-file scan mixes three different subjects. **Subtract the wrong vocabulary explicitly and print
both counts**, so the exclusion is auditable rather than invisible.

### PRODUCT FINDING — DEAD UI, not a scorer artefact
`SupplierPortal.tsx` renders `{s.response_rate != null && <Stat label='Response rate' …/>}`, but
`response_rate` appears in **none of the 14 reachable edge functions**, and the portal fetches
**only** through them (31 `call(…)`, **0** `supabase.from(`). The field is never returned, so the
guard is never true and **the tile can never render**. Same shape as the row's headline defect,
inverted: a surface with no server behind it.

### MARGINAL VERDICT TO REVISIT
`cc-assistant-panel` is MET on **1** proactive-guidance token. Thin. Not tightened further because
demanding many strings risks the inverse failure (a check no correct implementation can reach), but
it should be re-attacked when §15's assistant is built.

---

## MODULE 3 BUILT AND REFUTED — `product_intelligence.mjs`, §7 §8, EXPECTED 23
Modules 1+2+3 register **83/83** (29+31+23), zero errored, no denominator mismatch, no module load
failures. Combined: **22/83**. The runner correctly reports the 151 requirements that have no module
yet rather than scoring them as zero.

§7 = **3/14**, §8 = **1/9**.

### Refutation round 3 — three more false METs, and TWO TRUE METs defended
The interesting result of this round is that scepticism cut **both** ways.

**Defended as TRUE (the check was right to pass):** `prod-upload-catalog`, `prod-upload-pdf`,
`prod-upload-images`. Attribution showed a genuine product-catalog uploader —
`catalogs_ph:'Product catalogs (up to 5):'` with `<FilePick accept=".pdf,.jpg,.jpeg,.png" multiple>`.
That is NOT the registration uploader, and the pre-emptive `REGDOC` subtraction correctly let it
through. Attacking MET and MISSING with equal scepticism means sometimes confirming the MET.

**Removed as FALSE:**
| check | why |
|---|---|
| `prod-ai-extraction` | passed on **7** fns. `license_extract` does read "COMPANY PROFILE and/or PRODUCT CATALOG" but returns `products:[string]` — a comma-separated NAME LIST for the `leads.products` free-text column. `supplier_api`'s `products` is that same column being SELECTed. **None writes a product record.** §7 asks for 245 products / 18 categories / 12,500 attributes: a structured store, not a text field. Leg now requires the structured store as the DESTINATION. |
| `prod-supplier-visible` | its single hit was the English label `catalogs_ph:'Product catalogs (up to 5):'` inside a translations object. **A caption naming a thing is not the thing being rendered** — defect class #2, the label standing in for the delivery. Leg now requires CODE (`supplier_product`, `products.map(`, `<ProductCard`) and prints the caption count separately. |
| `card-match-routine` | passed on `fn_match_capability`-style routines, which score a **SUPPLIER** against an inquiry. §8's match is a **PRODUCT** match. Counting an existing unrelated mechanism as evidence for an unbuilt one would have read MET forever regardless of §8's state. Leg now requires the match to involve products; the capability estate is printed beside it. |

### ⚠ DEFECT CLASS SHARPENED — per-file scoping is NOT fine-grained enough here
Round 2 established that the chrome fence is file-level and misses intra-file leaks. Round 3 shows
why that matters so much on this surface: **`SupplierPortal.tsx` is 81,811 stripped characters and
contains the settings form, the registration uploader, the help desk, the product-catalog uploader
and the command centre.** "1 file pairs the format with a product context" is nearly vacuous when
that file is the whole portal.

**Mitigation that worked:** subtract the wrong vocabulary by name, print both counts, and where the
claim is about a component, score over THAT COMPONENT's own source (`CARD` in §8) so an absent
component yields 0 legitimately. §8's evidence — *"card component ABSENT, so every field leg is 0"* —
is the row #4 `slice(indexOf(...))` lesson holding: a missing component is now distinguishable from
a present one with no matches.

**This is a strong argument for splitting `SupplierPortal.tsx` BEFORE building §7/§8**, exactly as
the brief said. Every check written against the monolith is weaker than it looks.

### CONFIRMED BUILD ORDER (measured, not asserted)
- `supplier_product` — **0 rows, 0 non-writer SQL routines, 0 reachable edge fns**.
- `prod-count-products` / `-categories` / `-attributes` — rendered NO, served by NO fn.
- §8 is **0/8** on everything except the (now failing) match routine: no product card component exists.
- The only product data on production is `leads.products`, a **free-text comma-separated column**.

---

## MODULE 4 BUILT AND REFUTED — `rfq_and_quoting.mjs`, §9 §10 §11 §12, EXPECTED 33
Modules 1-4 register **116/116** (29+31+23+33), zero errored, no denominator mismatch: **29/116**.
§9 = 5/9, §10 = 0/8, §11 = 2/9, §12 = 0/7.

### ⚠⚠ RUNNER DEFECT — a MET with an ERROR where its proof should be
`req()` wrapped the verdict query and the evidence query in ONE try/catch. When the verdict
succeeded and the EVIDENCE threw, `ok` kept the value it already had and the check printed:

```
MET     qb-routine     ERROR REFUSED: read is not read-only; use mgmtWrite against a branch
```

It was **double-counted**: listed among the errored checks at the bottom *and* adding 1 to `met` at
the top, so the percentage was inflated by exactly the checks the report called unmeasured. The two
queries are now caught separately and an evidence failure forces `ok=false`.

**Root cause of the refusal, and it is subtle:** `Q()` defused write keywords by inserting `'||'`
after the **second** character. That works for every keyword of 3+ letters (`create` → `cr'||'eate`)
and is a **NO-OP for the two-letter keyword `do`** — `do'||'` is still a whole word, because the
quote is a non-word character and `\bdo\b` still matches. An evidence string reading *"N fn(s) DO
quote extraction"* was refused by qd_guard. **Split is now after the first character**
(`d'||'o`), fixed in `supplier_checks.mjs` and in module 1's local copy.

### Refutation round 4 — nine false METs removed
§9 initially read **7/9**, and the instrument's own evidence gave it away: `rfq-requirement`
*"served by [kyc login_otp role_guard …]"*, `rfq-deadline` *"served by [login_otp …]"*.
**login_otp does not serve an RFQ deadline.** The regexes were matching platform plumbing:

| token | what it really matched |
|---|---|
| `/scope/` | OAuth/JWT scope in `login_otp`, `role_guard` |
| `/expires?_at/` | the OTP's own expiry |
| `/\btitle\b/` | any HTML title attribute |
| `/\bunits?\b/` | any occurrence of the word |
| `/requests?/` | HTTP "request" in `layout.tsx` — site chrome with no opportunity list |
| `/score/ near /limit/` | `ai_gateway`, which ranks nothing |
| `/ask/` | **ChatWidget.tsx a third time** |

Fix: an `RFQCTX` gate — the field must sit near RFQ subject matter **inside the same function** —
plus `P_FILES` (portal files, chrome excluded) now exported so the wide list is not the default.
`qb-routine` additionally now requires the PROPOSAL vocabulary (price / delivery / warranty) rather
than the word "recommend", which had passed on `messages_api`.

### THE RECURRING NAME: ChatWidget.tsx has produced a false MET in THREE separate sections
§2 `onb-ai-conversation`, §4 `cc-assistant-panel` (its intra-file twin, the support chat), §11
`qb-nl-intent`. Every "does the portal converse / assist / accept intent" leg must use `P_FILES`
or `P`, never `FILES` or `S`. This is now the default-shaped fix rather than a per-check patch.
