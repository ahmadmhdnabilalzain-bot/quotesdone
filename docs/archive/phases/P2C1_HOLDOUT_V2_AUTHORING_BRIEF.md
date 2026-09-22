# QuotesDone P2-C1 Stage B.6 — holdout v2 authoring brief

**Purpose.** This document is the complete input for authoring independent holdout v2. Paste it, in
full, as the first message of a **new session that has never seen the QuotesDone repository or
database**. That session authors the cases; it does not evaluate them.

**Why a separate session.** A holdout measures an implementation. An author who has read the
implementation cannot write one — they will unconsciously write around what they know. The session
that produced this brief had, in the course of recovering the repository, read the scope adjacency
regex, the term-matching regex, the holdout runner and the rollback internals. It is therefore
disqualified from authoring, and it has deliberately written this brief at the level of the
*specification* only: no regex, no alias list, no threshold, no function body, and no knowledge of
which cases the current implementation passes or fails appears anywhere below.

---

## 0. How to use this brief

1. Open a fresh session with no repository access, or with access only to `docs/`.
2. Paste this document as the first message.
3. The session produces exactly four artefacts:
   - `holdout_v2_cases.json` — the canonical case file
   - `holdout_v2_seal.json` — the seal record
   - `holdout_v2_manifest.md` — the authoring manifest
   - `validate_holdout_v2.mjs` — the schema validator and canonicaliser used to produce the two above
4. The session stops there. It does not load the cases, does not run anything against the
   application, and does not open `supabase/`.

---

## 1. Hard constraints on the authoring session

**Permitted.** `docs/phases/**` may be read to confirm the approved trade taxonomy and route
numbering. Nothing else in the repository.

**Forbidden, without exception:**

- `supabase/migrations/**`, `supabase/functions/**`, or any SQL in the repository
- any connection to the database, including read-only queries and the Supabase MCP tools
- holdout v1: its cases, its expectations, its results, its failure list, its checksum
- current aliases, keyword lists, patterns, matching rules, evidence weights or thresholds
- any prior session summary, commit message or verification record describing P2-C1 behaviour

If the authoring session finds itself reasoning about "what the system currently does", it has
already failed. The only question it may ask is **"what should the answer be?"**

**Do not tune to a target.** Do not write cases you believe are easy. Do not avoid cases you
believe are hard. The suite's value is proportional to how much it can surprise us.

---

## 2. Frozen specification

Everything in this section is the approved Stage B.6 scope-disposition specification. It is the
*only* source of truth for expected outcomes. Where a rule below is silent, the case belongs in the
`unknown` disposition with clarification required — do not invent a rule.

### 2.1 Trades

Five trades. Keys are lowercase and stable.

| key | trade |
|---|---|
| `hvac` | Heating, ventilation and air conditioning |
| `electrical` | Electrical |
| `plumbing` | Plumbing and drainage |
| `fire` | Fire fighting, fire alarm and life safety |
| `elv` | Extra-low voltage — access control, CCTV, data, BMS, intercom |

**Core-three rule.** An umbrella reference to "MEP", "المقاولات الكهروميكانيكية", "mechanical,
electrical and plumbing" or an equivalent full-scope phrase covers **`hvac`, `electrical`,
`plumbing` only**. It never silently reaches `fire` or `elv`. Fire and ELV enter a case only when
named — directly, or as an explicit exception to an umbrella.

**Emergency lighting.** Primary technical owner is `electrical`. `fire` is a secondary regulatory
consumer of the same answers. Emergency lighting alone therefore detects `electrical`; it detects
`fire` only if life-safety scope is otherwise named.

*Confirm these keys against `docs/phases/P2-C1_STAGE_A_DESIGN.md` before authoring. If the design
document uses different keys, use the design document's and record the correction in the manifest.*

### 2.2 Dispositions

Ten values. Every trade that a case detects must carry exactly one.

| disposition | meaning | activates the trade? |
|---|---|---|
| `included` | In our scope, to be priced and delivered | **yes** |
| `excluded` | Explicitly not in our scope, no other party named | no |
| `by_others` | Not ours because a *named* other party is responsible | no |
| `client_supplied` | Materials or equipment provided by the client; we may still install | depends — see 2.3 |
| `optional` | Priced separately, customer decides later | no, until confirmed |
| `future_phase` | Belongs to a later phase or a later contract | no |
| `existing_only` | An existing system, to be surveyed, modified, extended or maintained | **yes** |
| `proposed` | Inferred from a document or weak signal, not yet confirmed by the customer | no — never auto-activates |
| `unknown` | Named but the disposition cannot be determined from the text | no |
| `conflicted` | Two statements of equal specificity contradict each other | no |

**Decision rules, in order:**

1. **`by_others` requires a named party.** "By others", "by the main contractor", "by the fit-out
   contractor", "بواسطة مقاول آخر", "من قبل المقاول الرئيسي" → `by_others`. If no responsible party
   is named, the disposition is `excluded`, not `by_others`. **"Not in our scope", "outside our
   package", "ليس ضمن نطاقنا", "خارج نطاق أعمالنا" are `excluded`** — being outside our package does
   not tell us who else is doing it.
2. **Client supply is `client_supplied`, not `by_others`.** "Supply by client", "client to supply",
   "client supplied", "free issue", "التوريد من قبل العميل", "العميل سيوفر", "توريد العميل" →
   `client_supplied` on the supply component. The client is not "others"; they are the counterparty,
   and the distinction changes who we invoice.
3. **`existing_only` needs a modification verb.** "Existing chillers to be serviced", "extend the
   existing fire alarm loop", "modify the existing DB", "النظام القائم يحتاج صيانة" →
   `existing_only`, and the trade **is** active — there is work to do. A bare mention of an existing
   system with no work verb is `unknown`.
4. **`optional` and `future_phase` never activate.** "If budget allows", "as an option", "provisional
   sum", "Phase 2", "later stage", "كخيار إضافي", "المرحلة الثانية", "في مرحلة لاحقة".
5. **`proposed` is the only disposition a document may produce on its own.** See 2.9.

### 2.3 Scope components

**Declared vocabulary — see the note below.** Nine keys, describing lifecycle stages, not equipment.

| key | covers |
|---|---|
| `design` | Design, calculations, load schedules, authority-ready drawings |
| `shop_drawings` | Shop drawings, coordinated services drawings, as-builts |
| `supply` | Supply, procurement, delivery of materials and equipment |
| `install` | Installation, erection, fixing, first and second fix |
| `testing` | Testing, inspection, T&C witnessing |
| `commissioning` | Commissioning, balancing, handover, demonstration |
| `maintenance` | Maintenance, DLP, AMC, servicing |
| `authority_approval` | DEWA / SEWA / ADDC / Civil Defence / Trakhees NOCs and approvals |
| `complete_trade_scope` | Sentinel: the whole trade scope, used when no split is stated |

> **Declared-assumption notice.** The approved Stage B.6 model defines nine `scope_component`
> values, but the approved list was not available to this brief. The nine keys above are a declared
> vocabulary, not a quotation. **The authoring session must reproduce this table verbatim in the
> manifest as `component_vocabulary` with `"source": "declared"`.** If the approved keys differ,
> only a one-line mapping table changes at load time — the 126 cases do not.

**Component rules:**

- A component disposition **overrides** the trade disposition for that component only.
- A trade with `complete_trade_scope: included` and `supply: client_supplied` is still an **active**
  trade — we install, we just do not buy.
- A trade whose *every* component is `excluded`, `by_others` or `future_phase` is **not** active,
  whatever the trade-level line says.
- If no component is named, emit exactly one component row: `complete_trade_scope`, carrying the
  trade disposition.

### 2.4 Precedence and conflict resolution

**Specificity ladder**, most specific first:

1. Component-level statement about a named trade
2. Trade-level statement about a named trade
3. Exception clause attached to an umbrella ("except…", "باستثناء…", "excluding…")
4. Umbrella statement about MEP / all services

**More specific wins.** "All MEP is excluded, except fire fighting" → the exception (level 3) beats
the umbrella (level 4): `hvac`/`electrical`/`plumbing` `excluded`, `fire` `included`.
"MEP works included, but electrical is by the main contractor" → the trade-level statement (level 2)
beats the umbrella: `electrical` `by_others`, the other two `included`.

**Equal specificity contradicts → `conflicted`.** Two statements at the same level that cannot both
hold produce `conflicted`, `clarification_required: true`, and the blocker
`scope_conflict_unresolved`. **Do not resolve by document order.** Last-sentence-wins, first-
sentence-wins and longest-sentence-wins are all wrong. If the customer said both, we ask.

**Confirmation resolves without deleting evidence.** A `conflicted` trade that the customer later
confirms becomes `included`; the contradicting statement remains recorded. Holdout v2 cases are
single-turn, so no case may expect a conflict to self-resolve.

### 2.5 Sentence and clause boundaries

A scope modifier binds only within its own clause. Clause boundaries are `.` `;` `,` `،` `؛`,
a newline, and the coordinating break in "however", "but", "لكن", "غير أن".

- *"The building is complete. MEP works are required."* — `complete` is in a different clause from
  `MEP`; it is not a full-scope modifier. This is an **adversarial** case.
- *"Complete MEP package required."* — same clause; full scope of the core three.
- *"Full MEP package for tower A; tower B is a separate future tender."* — the future-phase modifier
  binds to tower B only, not to the MEP scope.

Authors must include cases where the correct answer depends on the boundary in **both** directions:
boundary present and it must block, boundary absent and it must not.

### 2.6 Named interpretation rules

Four rules that are easy to get wrong and must be exercised deliberately.

1. **"Not in our scope" → `excluded`.** `by_others` requires a *named* responsible party. Being
   outside our package is not, by itself, evidence that someone else has it.
2. **Arabic `حزمة` ("package") is a scope modifier only with an anchor.** It qualifies an MEP or
   trade anchor in the same clause — "حزمة الأعمال الكهروميكانيكية" — and never triggers full MEP on
   its own. "حزمة المستندات" (a package of documents) detects nothing.
3. **"Central AC" is an exact multi-token phrase.** "Central AC", "central air conditioning",
   "تكييف مركزي" → `hvac`. **Standalone "AC" never auto-confirms a trade** — it is ambiguous
   (alternating current, air conditioning, an abbreviation in a document reference). Standalone "AC"
   with no supporting HVAC evidence yields `unknown` at most, with clarification. **"Access control"
   must never produce `hvac`** — it is `elv`.
4. **Client supply language is `client_supplied`.** Listed in 2.2 rule 2.

### 2.7 Clarification

`clarification_required: true` when, and only when:

- any trade is `conflicted`; or
- any trade is `unknown`; or
- a trade is `proposed` and would be active if confirmed; or
- the message is a genuine scope enquiry but no trade can be detected; or
- a scope modifier is present whose binding is genuinely ambiguous under 2.5.

`clarification_required: false` for a clean included/excluded/by_others/client_supplied/optional/
future_phase/existing_only reading, and for adversarial messages that are not scope enquiries at all.

Every case with `clarification_required: true` must state `clarification_reason` as one of:
`conflict`, `ambiguous_trade`, `unconfirmed_proposal`, `no_trade_detected`, `ambiguous_scope_binding`.

### 2.8 Dispatch blockers

Declared vocabulary. Zero or more per case, sorted.

| blocker | raised when |
|---|---|
| `no_active_trade` | no trade ends up active |
| `scope_conflict_unresolved` | any trade is `conflicted` |
| `clarification_pending` | `clarification_required` is true and the answer would change activation |
| `shared_mandatory_missing` | a mandatory shared field is absent — **do not use in v2**; v2 texts are scope texts, not full inquiries |
| `trade_not_eligible` | a trade is active but its own mandatory fields are missing — **do not use in v2** |

v2 cases therefore use only the first three. The last two are listed so the evaluator can assert
they never appear.

### 2.9 Detection versus activation, and documents

- **`detected_trades`** — every trade the case gives evidence for, **whatever its disposition**. A
  trade that is excluded is still detected. This is the denominator for per-trade detection accuracy.
- **`active_trades`** — the subset that becomes a live workstream: dispositions `included` and
  `existing_only`, minus any trade whose components are all non-delivering (2.3).
- **Documents never activate.** A trade whose only evidence is an attached document is `proposed`,
  never `included`, and always carries clarification. Text evidence and document evidence together
  may yield `included`.

---

## 3. Case schema

One JSON object per case. `holdout_v2_cases.json` is `{"holdout_version":"v2","cases":[ … ]}`.

```jsonc
{
  "case_key": "H-042",                    // unique, /^[A-R]-\d{3}$/, bucket letter + sequence
  "bucket": "umbrella_exclusion_exception",// one of the 18 bucket ids in section 4
  "adversarial": false,                    // true = the case exists to prove the system does NOT fire
  "gulf_phrasing": true,                   // uses UAE/Gulf market vocabulary
  "mixed_language": false,                 // deliberately mixes Arabic and English technical terms
  "morphology_variant": null,              // null | "definite_article" | "plural" | "ta_marbuta" |
                                           // "hamza" | "alef_variant" | "proclitic" | "spelling"

  "text_en": "All MEP works are excluded from our package, except the fire fighting system, which remains in our scope.",
  "text_ar": "جميع الأعمال الكهروميكانيكية مستثناة من نطاق أعمالنا، باستثناء نظام مكافحة الحريق الذي يبقى ضمن نطاقنا.",

  "documents": [],                         // optional; see 2.9
  // [{ "filename": "boq.pdf", "text_en": "…", "text_ar": "…" }]

  "expect": {
    "detected_trades": ["electrical", "fire", "hvac", "plumbing"],   // sorted
    "active_trades": ["fire"],                                        // sorted
    "trade_dispositions": {                                           // one entry per detected trade
      "electrical": "excluded",
      "fire": "included",
      "hvac": "excluded",
      "plumbing": "excluded"
    },
    "component_dispositions": [                                       // sorted by trade, then component
      { "trade": "electrical", "component": "complete_trade_scope", "disposition": "excluded" },
      { "trade": "fire",       "component": "complete_trade_scope", "disposition": "included" },
      { "trade": "hvac",       "component": "complete_trade_scope", "disposition": "excluded" },
      { "trade": "plumbing",   "component": "complete_trade_scope", "disposition": "excluded" }
    ],
    "clarification_required": false,
    "clarification_reason": null,
    "dispatch_blockers": [],                                          // sorted
    "must_not_detect": ["elv"],                                       // hard false-positive guard
    "must_not_activate": ["electrical", "hvac", "plumbing"]           // detected but must never be live
  },

  "rationale": "The exception clause is more specific than the umbrella, so fire survives the exclusion. ELV is never reached by an MEP umbrella.",
  "spec_refs": ["2.1", "2.4"]
}
```

### 3.1 Validation rules — all must hold, the validator must enforce every one

| # | rule |
|---|---|
| V1 | `case_key` unique across the file and matches `^[A-R]-\d{3}$` |
| V2 | `bucket` is one of the 18 ids in section 4, and its letter matches the `case_key` prefix |
| V3 | `text_en` and `text_ar` are both non-empty; neither is a transliteration or a machine gloss of the other — they must be idiomatic in their own language and must carry **the same scope meaning** |
| V4 | every key in `trade_dispositions` appears in `detected_trades`, and vice versa |
| V5 | every trade in `active_trades` appears in `detected_trades` |
| V6 | every trade in `active_trades` has disposition `included` or `existing_only` |
| V7 | no trade in `active_trades` appears in `must_not_activate` |
| V8 | no trade in `must_not_detect` appears in `detected_trades` |
| V9 | every trade in `component_dispositions` appears in `detected_trades`; every detected trade has at least one component row |
| V10 | a trade with no stated split has exactly one component row, `complete_trade_scope`, whose disposition equals its trade disposition |
| V11 | if any trade disposition is `conflicted`, then `clarification_required` is true and `scope_conflict_unresolved` is in `dispatch_blockers` |
| V12 | if `clarification_required` is true, `clarification_reason` is non-null and from the enum in 2.7; if false, it is null |
| V13 | if `active_trades` is empty, `no_active_trade` is in `dispatch_blockers` |
| V14 | `shared_mandatory_missing` and `trade_not_eligible` never appear |
| V15 | all trade keys are from 2.1; all dispositions from 2.2; all components from 2.3; all blockers from 2.8 |
| V16 | every array that the schema marks sorted is sorted ascending |
| V17 | `rationale` is 1–2 sentences and non-empty; `spec_refs` is non-empty |
| V18 | a case with `documents` non-empty has at least one trade whose disposition is `proposed`, unless the same trade is also named in the text |
| V19 | Arabic text is Unicode NFC and contains at least one character in `؀-ۿ` |
| V20 | bucket counts meet the minimums in section 4 and the total is ≥ 120 |

---

## 4. Coverage matrix

**Target 126 pairs — 252 interpretations.** The numbers are minimums; exceed them freely.

| id | bucket | min pairs |
|---|---|---|
| A | `included_plain` — straightforward in-scope requests, one to three trades | 8 |
| B | `excluded_no_party` — exclusion language with no other party named → `excluded` | 8 |
| C | `by_others_named` — a responsible party is named → `by_others` | 7 |
| D | `client_supplied` — free issue, client to supply, supply by client | 7 |
| E | `optional` — provisional sums, "if budget allows", priced as an option | 5 |
| F | `future_phase` — phase 2, later contract, subsequent tender | 5 |
| G | `existing_only` — survey, modify, extend, service an existing system | 5 |
| H | `umbrella_exclusion_exception` — "all MEP excluded except X" | 7 |
| I | `umbrella_inclusion_exclusion` — "full MEP included but X is not ours" | 7 |
| J | `component_split` — supply / install / design / testing / commissioning / maintenance / authority approval splits | 12 |
| K | `equal_specificity_conflict` — genuine contradictions → `conflicted` | 7 |
| L | `clause_boundary` — modifier must bind, or must not, across a boundary | 7 |
| M | `mixed_language` — Arabic sentence with English technical terms and vice versa | 6 |
| N | `gulf_phrasing` — UAE market vocabulary, authority names, local building types | 6 |
| O | `arabic_morphology` — definite article, proclitics, plurals, ta marbuta, hamza and alef variants, common misspellings | 7 |
| P | `adversarial_unrelated` — MEP, mechanical, AC, package, complete, central used in non-trade senses | 10 |
| Q | `document_proposed` — trade evidence only in an attachment → `proposed` | 6 |
| R | `no_detection` — nothing should be detected at all | 6 |
| | **total** | **126** |

**Cross-cutting minimums**, satisfied by cases anywhere in the table:

- ≥ 22 cases with `adversarial: true`
- ≥ 20 cases with a non-null `morphology_variant`
- ≥ 15 cases carrying `must_not_detect` with at least one entry
- ≥ 10 cases with two or more component rows on the same trade
- every one of the ten dispositions appears in ≥ 6 cases
- every one of the nine components appears in ≥ 4 cases
- every one of the five trades is `included` in ≥ 8 cases and `excluded`/`by_others` in ≥ 6

---

## 5. Authoring rules

**Pairing.** One expectation per case, applied to both languages. Parity is then a property the
implementation either has or lacks, rather than something the case file asserts. Never write an
Arabic text that is easier or harder than its English twin — if the English says "except the fire
fighting system", the Arabic must say the same thing with the same specificity, not "excluding fire".

**Gulf phrasing.** Use vocabulary a UAE contractor would actually send: G+2 villa, podium, fit-out,
DEWA/SEWA/ADDC connection, Civil Defence NOC, Trakhees, Musataha, shell and core, Cat A / Cat B,
snagging, DLP, AMC, BOQ, RFQ, LPO, "kindly revert", "as per attached". Mix formal MSA with the
register a Gulf estimator writes in.

**Arabic morphology.** Deliberately vary, and record which variant each case uses:
- definite article and proclitics: `سباكة` / `السباكة` / `للسباكة` / `بالسباكة` / `والسباكة`
- plurals and duals: `مكيف` / `مكيفات` / `وحدة` / `وحدات`
- ta marbuta and ha: `صيانة` / `صيانه`
- hamza and alef variants: `إنشاء` / `انشاء`, `أعمال` / `اعمال`
- yaa and alef maqsura: `مبنى` / `مبني`
- common tender misspellings, kept realistic

**Mixed language.** Arabic sentences carrying English equipment names (`AHU`, `FCU`, `chiller`,
`DB`, `MCB`, `CCTV`, `BMS`), and English sentences carrying Arabic terms. Include at least two cases
where the English term is a plural (`AHUs`, `FCUs`) and at least two where an Arabic term carries a
proclitic.

**Adversarial.** The bar is *plausible*, not absurd. Every adversarial case must be a message a real
customer could send. Cover at least: "complete" and "package" as ordinary English words; "mechanical"
as a material property; "AC" as alternating current and as a document reference; "access control" as
ELV, never HVAC; "MEP" as a company description rather than a scope request; a full stop between a
modifier and an anchor; "central" applied to something other than air conditioning.

**Rationale.** Every case states in one sentence *why* the expectation is what it is, with a
`spec_refs` pointer. A case whose rationale cannot cite a rule in section 2 is a case whose expected
outcome the author invented — delete it or fix the specification first.

---

## 6. Worked examples

Six illustrative cases. They are format anchors, not a style to copy — the real suite must be far
more varied.

**A-001 · included_plain**
> EN: "We need HVAC and plumbing works for a G+2 villa in Al Barsha. Kindly revert with your quote."
> AR: "مطلوب أعمال التكييف والسباكة لفيلا أرضي وطابقين في البرشاء. نرجو موافاتنا بعرض السعر."
> detected `[hvac, plumbing]` · active `[hvac, plumbing]` · both `included` ·
> components `complete_trade_scope` on each · clarification `false` · blockers `[]` ·
> must_not_detect `[electrical, elv, fire]`

**B-003 · excluded_no_party** — rule 2.6.1
> EN: "Electrical works are not in our scope for this project."
> AR: "الأعمال الكهربائية ليست ضمن نطاق أعمالنا في هذا المشروع."
> detected `[electrical]` · active `[]` · `electrical: excluded` — **not** `by_others`, because no
> other party is named · clarification `false` · blockers `[no_active_trade]`

**D-002 · client_supplied** — rule 2.6.4, component override
> EN: "Chillers and FCUs will be supplied by the client as free issue. We are to install, test and commission only."
> AR: "سيتم توريد المبردات ووحدات الفان كويل من قبل العميل. علينا التركيب والاختبار والتشغيل فقط."
> detected `[hvac]` · active `[hvac]` · `hvac: included` ·
> components: `supply: client_supplied`, `install: included`, `testing: included`,
> `commissioning: included` · clarification `false` · blockers `[]`
> *The trade stays active: we are not buying, but we are working.*

**K-004 · equal_specificity_conflict** — rule 2.4
> EN: "Plumbing works are included in this package. Plumbing is not part of our scope of works."
> AR: "أعمال السباكة مشمولة ضمن هذه الحزمة. السباكة ليست ضمن نطاق أعمالنا."
> detected `[plumbing]` · active `[]` · `plumbing: conflicted` · clarification `true`,
> reason `conflict` · blockers `[clarification_pending, scope_conflict_unresolved]`
> *Two trade-level statements, equal specificity. The second sentence does not win for being second.*

**P-007 · adversarial_unrelated** — rules 2.5 and 2.6.3
> EN: "The structural works are complete. Please confirm the access control package price."
> AR: "الأعمال الإنشائية مكتملة. نرجو تأكيد سعر حزمة أنظمة التحكم بالدخول."
> detected `[elv]` · active `[elv]` · `elv: included` · clarification `false` · blockers `[]` ·
> **must_not_detect `[hvac, electrical, plumbing, fire]`** · adversarial `true`
> *"complete" sits in a different clause from any anchor; "package" qualifies access control, not
> MEP; the letters "AC" inside "access control" are not air conditioning.*

**Q-002 · document_proposed** — rule 2.9
> EN: "Please find the attached BOQ and revert with your best price."
> AR: "مرفق جدول الكميات، نرجو موافاتنا بأفضل سعر."
> documents: one BOQ whose extracted text lists fire fighting pipework
> detected `[fire]` · active `[]` · `fire: proposed` · clarification `true`,
> reason `unconfirmed_proposal` · blockers `[clarification_pending, no_active_trade]`
> *A document may propose a trade. It may never activate one.*

---

## 7. Validation, canonicalisation, checksum, seal

### 7.1 Validator

`validate_holdout_v2.mjs` enforces every rule V1–V20 and exits non-zero on the first failure. It
prints a coverage table so the manifest is generated from the file, never typed by hand.

### 7.2 Canonical form

The checksum is meaningless unless the bytes are deterministic.

- UTF-8, **no BOM**
- all strings Unicode **NFC**
- object keys sorted ascending at every level
- arrays sorted where the schema says sorted; `cases` sorted by `case_key`
- `JSON.stringify(value, null, 2)`, LF line endings, exactly one trailing newline

```js
const canon = v => Array.isArray(v) ? v.map(canon)
  : v && typeof v === 'object'
    ? Object.fromEntries(Object.keys(v).sort().map(k => [k, canon(v[k])]))
    : typeof v === 'string' ? v.normalize('NFC') : v;

const bytes = Buffer.from(JSON.stringify(canon(doc), null, 2) + '\n', 'utf8');
writeFileSync('holdout_v2_cases.json', bytes);
const sha = createHash('sha256').update(bytes).digest('hex');
```

The checksum is taken over the **file bytes**, and the file is written from the canonicaliser — so
re-running the canonicaliser on the delivered file must reproduce the file unchanged. State that
round-trip result in the manifest.

### 7.3 Seal

`holdout_v2_seal.json`:

```json
{
  "holdout_version": "v2",
  "checksum_sha256": "<64 hex>",
  "case_count": 126,
  "canonicaliser": "validate_holdout_v2.mjs",
  "sealed_at": "<ISO-8601>",
  "sealed_by": "<session identifier>",
  "authored_from": "P2C1_HOLDOUT_V2_AUTHORING_BRIEF.md",
  "brief_sha256": "<64 hex of this brief>",
  "independence": {
    "read_implementation": false,
    "read_holdout_v1": false,
    "read_database": false,
    "statement": "This session read only the authoring brief and, where stated, docs/phases/."
  },
  "immutability": "Expected outcomes are frozen. They may be changed only through the P2-C5 expectation-change controls, which require a reason, a work item and a named person."
}
```

**Sealing at load time is a separate, later act, and it is not optional.** Whoever loads v2 into the
database must, in the same transaction: create the case table, insert the cases, install a
`BEFORE UPDATE OR DELETE` trigger on the expectation columns that raises, insert the seal row with
this checksum, and verify that a checksum recomputed from the loaded rows equals the sealed one.
**No evaluation may run before the seal verifies.**

---

## 8. Authoring manifest template

`holdout_v2_manifest.md`, generated by the validator:

```
# Holdout v2 — authoring manifest

checksum (sha256)        : <64 hex>
brief checksum (sha256)  : <64 hex>
total cases              : <n>
EN/AR pairs              : <n>   (must equal total cases)
interpretations          : <2n>
sealed at                : <ISO-8601>

## Coverage by disposition        (cases in which the disposition appears)
included <n> · excluded <n> · by_others <n> · client_supplied <n> · optional <n>
future_phase <n> · existing_only <n> · proposed <n> · unknown <n> · conflicted <n>

## Component-scope coverage       (cases in which the component appears)
design <n> · shop_drawings <n> · supply <n> · install <n> · testing <n>
commissioning <n> · maintenance <n> · authority_approval <n> · complete_trade_scope <n>
component_vocabulary source: declared        <- see section 2.3 of the brief

## Per-trade coverage
             detected  included  excluded/by_others  must_not_detect
hvac         <n>       <n>       <n>                 <n>
electrical   …
plumbing     …
fire         …
elv          …

## Bucket coverage
A..R with counts against the minimums in section 4

## Adversarial
adversarial cases        : <n>
cases with must_not_detect: <n>
morphology variants      : <n>   (by variant)
mixed-language cases     : <n>
Gulf-phrasing cases      : <n>
document-bearing cases   : <n>

## Validation
V1..V20                  : all pass
canonical round-trip     : byte-identical
```

---

## 9. Evaluator reporting contract

This is what the *later* evaluation session must report. It is stated here so v2 is authored to
support it, and so no metric can be quietly dropped once results are known.

**Nine separate figures, each with its own denominator printed next to it.**

| metric | denominator |
|---|---|
| case-level exact accuracy | 2 × case count — every field of `expect` must match, in that language |
| active-trade-set accuracy | 2 × case count — exact set equality |
| per-trade detection accuracy | 2 × Σ `detected_trades` |
| per-trade disposition accuracy | 2 × Σ `detected_trades` |
| component-disposition accuracy | 2 × Σ `component_dispositions` |
| clarification accuracy | 2 × case count |
| false positives | count of activations of a trade in `must_not_activate` or a detection in `must_not_detect` |
| false negatives | count of expected-detected trades that were not detected, **plus** expected-active trades that were not activated |
| English/Arabic parity | case count — EN and AR produce identical output, right or wrong |

**Rules that must not be relaxed:**

1. **An undetected expected trade is a false negative and stays in every denominator.** It may not
   be dropped from per-trade disposition accuracy on the grounds that there was no disposition to
   compare. A missing trade scores zero on detection *and* zero on disposition.
2. **Parity is reported alongside correctness, never instead of it.** Both languages wrong in the
   same way is 100% parity and 0% correctness. Any headline number must say which it is.
3. **Never print a bare ratio.** "126/126" must always be qualified: executed, parity, correct, or
   integrity.
4. **Unsafe errors are counted and listed separately.** An unsafe error is any case where a trade
   expected `excluded`, `by_others`, `client_supplied`, `optional`, `future_phase`, `proposed` or
   `conflicted` came back `included` or active — a wrong activation. The reverse direction
   (under-detection) is safe-direction: it costs a clarification question, not a wrong dispatch.
5. **Every remaining failure is explained individually.** A failure list without diagnoses is not a
   result.

**Acceptance thresholds:**

| criterion | threshold |
|---|---|
| case-level exact accuracy | ≥ 99% |
| English/Arabic parity | ≥ 99% |
| false-positive activation from exclusion language | **0** |
| unsafe disposition errors | **0** |
| unexplained failures | **0** |

**Do not tune to these thresholds.** If v2 fails, the correct response is to fix the interpretation
rules or to correct a demonstrably wrong expectation through the P2-C5 change controls — never to
soften a case, and never to edit the sealed file.

---

## 10. Prohibited actions for the authoring session

- Do not open `supabase/`, connect to the database, or use any Supabase tool.
- Do not look for holdout v1, its results, or any description of them.
- Do not run, evaluate, score or "sanity check" the cases against anything.
- Do not write cases you expect the implementation to pass, or avoid ones you expect it to fail —
  you have no basis for either belief, and acquiring one disqualifies you.
- Do not adjust an expected outcome to make a suite look better. The expectations are the
  specification's answer, not a prediction.
- Do not deliver fewer than 120 pairs, and do not pad the count with near-duplicates.

Stop after producing the four artefacts.

---

## SUPERSEDED - DO NOT USE AS THE INDEPENDENT AUTHORING BRIEF

This version is contaminated. Its "Named interpretation rules" section listed the exact lexical
triggers of four known interpretation gaps, and its worked examples repeated them. An author given
this document would be steered straight at the cases the implementation is known to mishandle,
which is the opposite of what a holdout is for.

Use `P2C1_HOLDOUT_V2_AUTHORING_BRIEF_SANITIZED.md` instead. This file is retained only as the
record of what was removed and why.