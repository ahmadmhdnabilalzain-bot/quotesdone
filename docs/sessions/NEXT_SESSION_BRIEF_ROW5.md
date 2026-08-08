# START HERE — ROW #5, THE SUPPLIER PORTAL (`supplier portal.txt`)

> ## THE THREE FOUNDER RULES STILL GOVERN EVERYTHING
> 1. **ONE ROW AT A TIME, TO 100%.**
> 2. **THE ORDER IS THE FILE ORDER: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8.**
> 3. **EVERYTHING DEPLOYS TO PRODUCTION, AND IS MERGED.**
>
> `qd_guard` refuses production writes by design. Promote by reading staging's verified definition
> back and posting it verbatim: `node scripts/apply_sql.mjs <file> --promote [--ddl]` for routines
> and schema, `node scripts/promote_rows_to_production.mjs` for config rows. **Never retype a body.**

## ⚠ READ THIS BEFORE PLANNING THE SESSION — THE ORDER IS NOT CLEAN

| row | state | where |
|---|---|---|
| #1 architecture | ✅ 48/48, merged to `main` (PR #8) | `verify_spec_architecture.mjs` |
| #2 `OS.txt` | ⏸ **107/110**, paused | `verify_os_blueprint.mjs`, `docs/sessions/PAUSED_ROWS_2_AND_3.md` |
| #3 `OS 2.txt` | ⏸ paused | same doc |
| #4 customer portal | **146/147**, unmerged on `repair/finish-quotesdone` | `verify_portal_blueprint.mjs`, `docs/sessions/ROW4_SCORE.md` |
| #5 supplier portal | not started | this brief |

Rows #2 and #3 are paused, not finished. Row #2's last three were measured as **clock-blocked and
capacity-blocked, not code-blocked** — two drain on their own after 2026-08-07 10:49 UTC and the
third is a founder throughput decision. **Re-run `verify_os_blueprint.mjs` first: row #2 may already
be 109/110 or 110/110 with no work at all.** That is a ten-minute check and it may close a row.

Row #4's last one is not closable by code — see the next section, because it is also row #5's
central problem.

---

## ⚠⚠ THE THING THAT DECIDES WHETHER ROW #5 IS BUILDABLE AT ALL

**The supplier portal has no suppliers.** Measured on production, 7 Aug 2026:

```
leads 20464 | verified 0 | approved 0 | self_registered 0 | claimed 0
registration_submitted 0 | owner_email_verified 0 | matchable 0
quotes 0 | inquiry_matches 0 | supplier_capabilities 0
```

The estate is a **scraped prospect list**. Not one of the 20,464 has registered, claimed their
listing, uploaded a licence or passed the licence gate. This is not the zero-customer floor that
shaped row #4 — production genuinely holds the whole supplier estate, and the estate is empty of
actual suppliers.

For row #4 that cost exactly one requirement (`disc-found-count`). For row #5 **it is the subject of
the entire spec.** §1–§24 describe what a supplier sees, does and is scored on. Sections that ask
what a supplier's own data looks like — Digital Twin (§3), Product Intelligence (§7), Performance
Intelligence (§13), Gamification (§20), Risk Protection (§17) — have zero rows to describe.

**This needs a founder decision in the first ten minutes of the session, and there are only three
honest answers:**

- **(a) Score the MECHANISM, state the population.** Exactly row #4's discipline: does the
  routine/endpoint/component exist, can a supplier reach it, would it render real data if data
  existed. Every check prints the row count beside its verdict. This is the default and it is what
  the row #4 scorer's header already commits to.
- **(b) Onboard one real supplier first.** Registration, licence upload, licence gate, verified.
  One real supplier turns a dozen §13/§17/§20 checks from unmeasurable into measurable, and it
  closes row #4's `disc-found-count` as a side effect.
- **(c) Build a staging fixture supplier and score there, promote the mechanism to production.**
  `scripts/staging/demo_factory.mjs` already has `makeSupplier()` and
  `makeLicenceGatedSupplier()`.

**What is NOT an answer:** setting `verified` or `approval_status='approved'` on scraped rows. That
was proposed once and correctly refused — it invents a supplier network and puts customers' RFQs in
front of companies who never agreed to receive them. It stays refused.

---

## WHAT EXISTS TODAY, MEASURED (not impressions)

### The supplier's surface is 14 files. The customer's is 62.

```
supplier route closure   14 files, 29 components
edge functions reachable  9  [kyc login_otp messages_api rfq_flag role_guard
                              supplier_api supplier_pay supplier_portal wa_optin_set]
3D / WebGL tokens         0    ← §5 3D Supplier Environment, §19 Network Map have nothing
chart importers           0    ← §13 Performance, §14 Market Intelligence have nothing
SupplierPortal.tsx      100,935 bytes (one file)
```

`src/components/portal/SupplierPortal.tsx` is a **100KB single file**. Row #4 hit exactly this and
split it into `src/components/portal/*`; the same split is almost certainly correct here, and doing
it EARLY is cheaper than doing it after twenty checks are written against the one file.

### Endpoints that exist

- `supplier_api` — 11 actions: `claim, create_company, extract_quote, inbox, me, pay_registration,
  process_docs, projects, save_profile, search, submit_quote`
- `supplier_portal` — 4 actions: `documents, eligibility, overview, save_documents`
- plus `supplier_ack, supplier_pay, supplier_review, quote_extract, quote_quality, quote_review,
  quote_pdf, rfq_flag, embed_leads, export_leads_csv, os_catalog`

### THE DEFECT THAT HAS APPEARED IN EVERY ROW SO FAR IS ALREADY HERE

Built, empty, and read by nothing:

| relation | rows | SQL readers |
|---|---|---|
| `supplier_product` | 0 | **0** |
| `supplier_product_variant` | 0 | **0** |
| `supplier_catalog` | 0 | **0** |
| `supplier_capabilities` | 0 | 3 |
| `inv_items` | 0 | 3 |
| `inv_stock_moves` | 0 | 4 |
| `quote_items` | 0 | 3 |

§7 Product Intelligence ("245 products, 12,500 attributes, searchable") and §8 AI Product Cards
have a schema and **no reader, no writer and no surface**. §5's warehouse view and the Inventory
module in §24 sit on `inv_items`/`inv_stock_moves`, also empty with no supplier-facing reader.

### What IS populated and worth surfacing first

| relation | rows | note |
|---|---|---|
| `supplier_score` | **20,464** | `reliability` non-null on all 20,464 — §13's four bars already exist |
| `catalog_subcategories` | 470 | §7's taxonomy |
| `catalog_domains` | 67 | |
| `catalog_supplier_categories` | 86 | |
| `category_specs` | 56 | 21 carry a `compliance_checklist` — §16 Document Intelligence |
| `taxonomy_trade` | 25 | what `fn_match_capability` gates on |
| `reg_catalog` | 38 | |

**Row #4's headline finding will almost certainly repeat: a large fraction of row #5 is already
built server-side and invisible to the supplier.** Surfacing it is the fastest real value; the
genuinely net-new work (3D factory view §5, network globe §19, Product Intelligence §7/§8,
Market Intelligence §14, Gamification §20) is a smaller set to sequence after it.

---

## THE ORDER OF WORK

### 1. Enumerate the spec into requirements — DO NOT GUESS THE COUNT
24 sections. Row #4 produced 147 requirements from 22 sections; do not assume ~160 and do not
invent a denominator. Enumerate, then assert the total in the runner.

### 2. Build the scorer BEFORE building anything else
Copy the row #4 shape exactly — it is the most-repaired instrument in the repo:

```
scripts/staging/verify_supplier_blueprint.mjs      # runner: discovers section modules, asserts EXPECTED
scripts/staging/supplier_blueprint/*.mjs           # one module per group of sections
scripts/staging/supplier_surface.mjs               # ← the /supplier closure, see below
```

The runner already supports what you need; copy `verify_portal_blueprint.mjs` and change `TOTAL`,
the directory and the header. It has `--staging`, `--only=<prefix>` and `--json=<path>`.

**`scripts/staging/portal_surface.mjs` is hardcoded to the `/me` route.** Row #5 needs the same
computation rooted at `src/app/[locale]/supplier/page.tsx`. Either parameterise the entry list in
that file (preferred — one implementation, two roots) or write `supplier_surface.mjs` beside it.
**Do not let a section module hardcode `SupplierPortal.tsx`.** That is precisely the bug that made
row #4 report 104/147 when the truth was 124 — two of five modules scored one file while three
scored the route's import closure, and one run held two definitions of "the supplier sees it".

### 3. Refute the scorer before trusting a number
Row #4's first scorer scored `sound=false` on all five modules across 101 refutation findings,
including an UNSATISFIABLE check that got harder the more correct the product became. **Quote no
percentage until the instrument has been attacked.** Attack MET and MISSING with equal scepticism.

### 4. Then build, in dependency order
schema → routine → edge function → surface → deploy BOTH projects → prove by execution → re-score.

---

## THE FIVE DEFECT CLASSES THE SCORER MUST BE WRITTEN AGAINST

Carried forward verbatim from rows #2 and #4, where all five shipped at least once:

1. **THE ONLY READER IS THE WRITER.** Count reads and writes separately, BY SITE. Exclude writers by
   pattern. Collapse `pg_proc` overloads with `count(distinct proname)` — `fn_agent_context` has two
   rows on production and inflated every count in row #2 that forgot.
2. **POPULATION STANDING IN FOR DELIVERY.** An endpoint existing is not a supplier seeing it. Every
   "the supplier sees X" requirement needs a RENDER leg measured over the supplier's own surface.
3. **ONE ROW SCORING A WHOLE MECHANISM.** Where the spec enumerates contents, the verdict is a
   per-item coverage count over ONE component.
4. **SATISFIABLE BY FLIPPING A FLAG.** No check may read a flag. Count code that exists.
5. **EVIDENCE THAT DOES NOT COMPUTE THE VERDICT.** Every number in the evidence string must be the
   same number the boolean used, over the same population.

**And the inverse failure, which is just as bad:** nothing may demand what no implementation could
satisfy. Row #4 shipped `assistant-floating-persistent` clamped to 0-or-1 and compared against
`views.length` — the only way to pass was to DELETE a view, and every view the product gained made
it harder. Check every threshold against "can a correct implementation reach this?"

---

## FOUR TRAPS ROW #4 PAID FOR. DO NOT PAY AGAIN.

1. **A comment quoting the markup it removed IS that markup to a static scan.** A comment reading
   `WAS A <table min-w-[380px]>` kept both the table count and the fixed-width count non-zero after
   the table was gone, and failed two requirements on markup that no longer existed. Two more
   comments naming `create_inquiry` took "there is exactly one way to create an RFQ" from 1 site to
   3. **Describe what was removed. Never quote it.**
2. **Do not map a list into navigation buttons and lose the literals.** Replacing nine explicit
   `setView('documents')` calls with `modules.map(...)` left nothing — no grep, no reviewer, no
   route audit — able to answer "where can this portal go" without executing it, AND put a
   server-computed ranking into the DOM order, which is the tab order a keyboard user gets. Keep the
   destinations written out; move them with the flexbox `order` property.
3. **`indexOf` returning -1 into `slice` is a silent false negative.** `slice(text.indexOf('function
   Messages('))` returns the file's LAST CHARACTER when the component is absent, and every count
   over it reads 0 — indistinguishable from a present component with no matches. Use
   `componentSrc()` from `portal_surface.mjs`.
4. **`verify_deploy_parity.mjs` was reporting STALE on code that was live**, and cost two needless
   redeploys before anyone checked. Fixed 7 Aug — its signature scanner treated a *closing* quote as
   an opening one and emitted 38 characters of source code as a "string literal" no bundle could
   contain. It now reads **12/12 LIVE**. Trust it, and if it ever disagrees with a deploy, hash the
   deployed body before redeploying anything.

---

## THE COMMANDS

```bash
node scripts/staging/verify_os_blueprint.mjs                     # row #2 — may already be closed
node scripts/staging/verify_portal_blueprint.mjs --json=out.json # row #4 — 146/147, ~12 min
node scripts/verify_deploy_parity.mjs                            # 12/12 LIVE, both projects
node scripts/apply_sql.mjs scripts/sql/<file>.sql --promote --ddl
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy_functions.ps1 `
  -ProjectRef pglpqrhvozwepymcuunn <slug>...                     # staging
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy_functions.ps1 `
  -ProjectRef htdblwldjkcgjvmqkbeh -IMeanProduction <slug>...    # production
```

**Prove by execution, not by deployment.** Row #4 left three harnesses that drive the DEPLOYED
functions with real JWTs — copy the shape:
`verify_portal_entry.mjs` (11/11), `verify_portal_rfq.mjs` (16/16), `verify_portal_inbox.mjs`
(12/12). Each asserts the negative case too — a second customer is refused another's data, and a
fresh customer matches nobody else's correspondence. **Use `newRun()` with no arguments**; a fixed
run tag collides on the second run with `email_exists`.

## HOUSEKEEPING

- A hook in `.claude/settings.local.json` auto-commits `.claude-flow/` daemon metrics and has twice
  produced commits whose message is the literal text `$(cat <<'EOF'`. Harmless, ugly, on `origin`.
  Worth fixing or untracking `.claude-flow/` before it happens again.
- Row #4 is unmerged on `repair/finish-quotesdone`. Prior rows merged to `main` only at 100%.
