# QuotesDone P2-C1 Stage B.6 — holdout v2 authoring brief (sanitized, v2.1)

**Purpose.** This document is the complete and only input for authoring independent holdout v2.
Paste it, in full, as the first message of a **new session with no access to the QuotesDone
repository, no access to the database, and no prior context about the product**. That session
authors the cases. It does not evaluate them.

**Why a separate session.** A holdout measures an implementation. An author who has read the
implementation cannot write one: knowing how the system works, they will unconsciously write around
it — avoiding shapes they sense are hard, or targeting them — and the resulting score stops being
evidence either way. This brief is therefore written entirely at the level of the *specification*.
It contains no code, no matching logic, no term lists, no thresholds, no internal names, and no
information about how any existing implementation behaves on any input.

**Read this next part carefully, because it is the easiest thing to get wrong.** Nothing in this
brief is a hint. Where a rule is stated abstractly, that is deliberate — do **not** ask for examples,
do not infer that a particular wording matters, and do not treat the order or emphasis of the rules
as a signal about where the difficulty lies. Every illustrative phrase has been removed on purpose.
Your job is to derive test material from the specification, in your own words, as a competent
domain author would if the implementation did not yet exist.

---

## 0. What this session produces

Exactly four artefacts:

| file | what |
|---|---|
| `holdout_v2_cases.json` | the canonical case file |
| `holdout_v2_seal.json` | the seal record |
| `holdout_v2_manifest.md` | the authoring manifest |
| `validate_holdout_v2.mjs` | the schema validator and canonicaliser that produced the two above |

Then stop.

---

## 1. Hard constraints on the authoring session

**No repository access of any kind.** No source directory, no migration directory, no scripts, no
documentation directory, no README, no commit history, no design document, no issue tracker. This
brief is self-contained; if something appears to be missing, it is either derivable from section 2
or it is genuinely out of scope, and the correct response is to place the case in the `unknown`
disposition and record the gap in the manifest rather than to go looking.

**No database access.** No connection, no read-only query, no schema inspection, no MCP tool that
reaches a database.

**No search for prior work.** Do not look for an earlier holdout, its cases, its results, its
failures or its checksum. Do not look for known issues, backlog items or bug reports.

**No behavioural reasoning.** If you catch yourself asking "what does the system currently do with
this?", stop. The only admissible question is **"what should the correct answer be?"**

**No tuning.** Do not write cases you believe are easy. Do not avoid cases you believe are hard. Do
not attempt to guess which constructions are risky. Author for even coverage of the specification,
and let the difficulty fall where it falls.

**No evaluation.** Do not run, score, spot-check or sanity-check the cases against anything.

---

## 2. Frozen specification

This section is the approved Stage B.6 scope-disposition specification, and the only source of truth
for expected outcomes. The three vocabularies below — trades, dispositions, components — are
**verified against the approved model**, not assumed. Where a rule is silent, the case belongs in
`unknown` with clarification required. Do not invent a rule to cover a gap; instead, note the gap in
the manifest.

### 2.1 Trades

Five trades. Keys are lowercase and stable.

| key | trade (EN) | trade (AR) | core |
|---|---|---|---|
| `hvac` | HVAC | التكييف والتهوية | yes |
| `electrical` | Electrical | الكهرباء | yes |
| `plumbing` | Plumbing & Sanitaryware | السباكة والأدوات الصحية | yes |
| `fire` | Fire & Life Safety | الحريق والسلامة | no |
| `elv` | ELV & Security | التيار الخفيف والأمن | no |

**Core-three rule.** An umbrella reference to the combined mechanical–electrical–plumbing services
covers the three **core** trades only. It never reaches `fire` or `elv` implicitly. Fire and ELV
enter a case only when named — directly, or as an explicit exception attached to an umbrella
statement.

**Shared-answer trades.** Where a single subject is technically owned by one trade and consumed for
regulatory purposes by another, the technical owner is the trade that gets detected. The regulatory
consumer is detected only if its own scope is otherwise named. Do not duplicate one subject across
two trades.

### 2.2 Dispositions

Ten values. Every trade a case detects carries exactly one. **`contributes` and `clarifies` below
are authoritative** — they are not guidance, they determine activation and clarification.

| disposition | meaning | contributes (activates) | clarifies |
|---|---|---|---|
| `included` | in our scope, to be priced and delivered | **yes** | no |
| `existing_only` | an existing installation, to be surveyed, modified, extended or maintained | **yes** | no |
| `excluded` | outside the scope we will deliver, and **no other responsible party is identified** | no | no |
| `by_others` | not ours because **another responsible party is identified** | no | no |
| `client_supplied` | the counterparty provides the materials or equipment | no | no |
| `future_phase` | belongs to a later phase, stage or contract | no | no |
| `optional` | offered as an option or a provisional item; the customer has not decided | no | **yes** |
| `proposed` | inferred from an attachment or a weak signal, not confirmed by the customer | no | **yes** |
| `unknown` | named, but the disposition cannot be determined from the text | no | **yes** |
| `conflicted` | two statements of equal specificity contradict each other | no | **yes** |

### 2.3 Abstract semantic rules

These are the discriminating rules. They are stated abstractly and deliberately carry no example
wording. Deriving realistic surface forms in both languages is the author's work.

1. **`excluded` versus `by_others` turns on whether a responsible party is identified.** Language
   that removes something from our scope tells us what we are not doing. It does not, by itself,
   tell us who is doing it. Absent an identified other party, the disposition is `excluded`. Only
   when the text identifies another party — by role, by organisation, or by a construction the
   reader would understand as designating a third party — does it become `by_others`.
2. **`client_supplied` is a distinct category and must not collapse into `by_others`.** The
   counterparty is not a third party. When the counterparty provides materials or equipment, that is
   `client_supplied`, whether or not we still perform the work around it. The distinction changes who
   is invoiced and what is procured, so it must survive as its own value.
3. **Scope modifiers require trade or umbrella context.** A word or phrase that quantifies extent —
   totality, completeness, whole-package, entirety, and their equivalents in either language — is a
   *modifier*, not a trigger. It has scope-widening force only when it qualifies a trade term or an
   umbrella services term within the same clause. On its own, or attached to some other noun, it
   carries no trade meaning at all and must not activate anything. This holds in both languages
   independently; a modifier that is inert in one language is inert in the other.
4. **Ambiguous abbreviations require clarification, never assumption.** Short forms that are
   ambiguous between a trade sense and a non-trade sense, or between two trades, do not confirm a
   trade on their own. Where the surrounding text disambiguates, use the disambiguated reading. Where
   it does not, the disposition is `unknown` with clarification required. An abbreviation appearing
   as a substring of a longer term belongs to that longer term and has no independent force.
5. **`existing_only` requires a work verb.** An existing installation mentioned with an action — a
   survey, a modification, an extension, a replacement, a service obligation — is `existing_only`,
   and the trade **is** active, because there is work to do. An existing installation mentioned with
   no action is `unknown`.
6. **Options and future phases never activate**, and an option additionally requires clarification,
   because the customer has not chosen.
7. **Attachments propose; they never activate.** See 2.8.

### 2.4 Scope components

Nine values, describing lifecycle stages rather than equipment. **Verified against the approved
model.**

| key | EN | AR |
|---|---|---|
| `design` | Design | التصميم |
| `supply` | Supply | التوريد |
| `installation` | Installation | التركيب |
| `testing` | Testing | الاختبار |
| `commissioning` | Commissioning | التشغيل والتسليم |
| `authority_approvals` | Authority approvals | موافقات الجهات |
| `maintenance` | Maintenance | الصيانة |
| `coordination` | Coordination | التنسيق |
| `complete_trade_scope` | Complete trade scope | نطاق العمل الكامل |

**Component rules:**

- A component disposition **overrides** the trade disposition for that component only.
- **Unstated components inherit the trade disposition.** A case lists rows only for the components
  its text actually addresses; the remaining components take the trade-level value. This is why an
  override on one component does not disturb the rest of the trade.
- If the text states **no** split at all, emit exactly one row — `complete_trade_scope` — carrying
  the trade disposition. If the text **does** state a split for a trade, `complete_trade_scope` must
  not appear for that trade.
- A trade may be active while one or more of its components is non-contributing: the trade-level
  disposition contributes, a single component is overridden to something that does not, and the rest
  inherit. We perform, we simply do not perform that one part.
- A trade is **not** active if its trade-level disposition does not contribute, or if every one of
  the nine components is explicitly stated and every one of them is non-contributing.
- **A component disposition can demand clarification on its own.** See 2.7 — the override that
  changes activation is not the only override that matters.

### 2.5 Precedence and conflict resolution

**Specificity ladder**, most specific first:

1. a component-level statement about a named trade
2. a trade-level statement about a named trade
3. an exception clause attached to an umbrella statement
4. an umbrella statement about the combined services

**More specific wins.** An exception attached to an umbrella defeats the umbrella for the subject of
the exception. A trade-level statement defeats an umbrella for that trade. A component-level
statement defeats a trade-level statement for that component.

**Equal specificity contradicts.** Two statements at the *same* level that cannot both hold produce
`conflicted`, clarification, and a conflict blocker. **Positional tie-breaks are forbidden** —
last-wins, first-wins and longest-wins are all wrong. If the customer said both, we ask.

**Confirmation resolves without destroying evidence.** A confirmed `conflicted` trade becomes
`included` and the contradicting statement remains on record. Holdout v2 cases are single-turn, so no
case may expect a conflict to resolve itself.

### 2.6 Clause and sentence boundaries

A modifier binds only within its own clause. Clause boundaries include sentence-final punctuation,
semicolons, commas, their Arabic counterparts, line breaks, and adversative conjunctions in either
language.

Author cases where the correct answer depends on the boundary in **both** directions: a boundary
present, where the modifier must fail to reach across it; and a boundary absent, where the modifier
must reach. A suite that only tests one direction proves nothing — a system that ignores boundaries
entirely and a system that respects them will score identically.

### 2.7 Clarification

**Clarification rules apply to trade dispositions and component dispositions alike.** A clarifying
disposition at either level demands clarification. This is not a detail: an unresolved option or
contradiction sitting on a component must not disappear beneath an otherwise contributing trade.
A trade can be perfectly clear, active, and about to be dispatched, while one component of its scope
is still an open question — and that question has to reach the customer.

`clarification_required` is **true** when, and only when, at least one of the following holds:

- any entry in `trade_dispositions` carries a disposition whose `clarifies` flag is set in 2.2 —
  `optional`, `proposed`, `unknown`, `conflicted`; or
- **any entry in `component_dispositions` carries one of those same four values**, whatever the
  trade-level disposition of that trade is; or
- no trade could be detected but the message is a genuine scope enquiry; or
- a scope modifier is present whose clause binding is genuinely ambiguous under 2.6.

It is **false** only for a reading in which every trade disposition **and** every component
disposition is non-clarifying, and for messages that are not scope enquiries at all.

**`clarification_reason`** is stated on every case where clarification is required, and is the
**first** applicable entry in this precedence order, so that the expected value is deterministic when
several triggers co-occur:

| # | reason | trigger |
|---|---|---|
| 1 | `conflict` | any `conflicted` disposition, **at trade or component level** |
| 2 | `ambiguous_trade` | any `unknown` disposition, at either level |
| 3 | `unconfirmed_proposal` | any `proposed` disposition, at either level |
| 4 | `optional_pending_decision` | any `optional` disposition, at either level |
| 5 | `ambiguous_scope_binding` | a modifier whose clause binding is ambiguous under 2.6 |
| 6 | `no_trade_detected` | nothing detected, but the message is a genuine scope enquiry |

**Conflict at component level carries the same consequences as conflict at trade level.** If any
component disposition is `conflicted`, then `scope_conflict_unresolved` must appear in
`dispatch_blockers` and `clarification_reason` must be `conflict` — exactly as it would if the
contradiction sat on the trade.

### 2.8 Detection, activation, and attachments

- **`detected_trades`** — every trade the case gives evidence for, **whatever its disposition**. A
  trade that is excluded is still detected.
- **`active_trades`** — the trades whose disposition contributes (`included`, `existing_only`), minus
  any trade whose components are all non-contributing under 2.4.
- **Attachments never activate.** A trade whose only evidence is an attached document is `proposed`,
  never `included`, and always carries clarification. Text evidence and attachment evidence together
  may yield a contributing disposition.

### 2.9 Dispatch blockers

| blocker | raised when |
|---|---|
| `no_active_trade` | no trade ends up active |
| `scope_conflict_unresolved` | any disposition is `conflicted`, **at trade or component level** |
| `clarification_pending` | clarification is required **and** the answer would change any of the three things below |

**`clarification_pending` applies when resolving the open question would change:**

1. the **active trade set** — the answer decides whether a trade is delivered at all; or
2. the **quoted or delivered component scope** — the answer decides what is priced, procured or
   performed within a trade that is already active; or
3. the **dispatchable supplier brief** — the answer changes what a supplier would be told to quote.

Criterion 2 is the one that a trade-level-only reading misses. An option or a contradiction sitting
on a single component leaves the trade active and the trade set unchanged, yet it still makes the
brief we would send incomplete. That is a blocker.

Two further blockers exist in the wider model — one for missing shared mandatory fields, one for a
trade active but individually ineligible. **Neither may appear in a v2 case**, because v2 texts are
scope statements, not complete inquiries. They are named here only so the evaluator can assert their
absence.

---

## 3. Case schema

One JSON object per case. The file is `{"holdout_version":"v2","cases":[ … ]}`.

The skeleton below is a **field reference with placeholder values**. It is not a model case and its
values are not meaningful; every angle-bracketed slot must be replaced with material you author.

```jsonc
{
  "case_key": "<bucket letter>-<3 digits>",   // /^[A-R]-\d{3}$/, unique
  "bucket": "<one of the 18 bucket ids in section 4>",
  "adversarial": false,                        // true = the case exists to prove the system does NOT fire
  "gulf_phrasing": false,                      // uses UAE/Gulf market register
  "mixed_language": false,                     // deliberately mixes Arabic and English technical terms
  "morphology_variant": null,                  // null | "definite_article" | "proclitic" | "plural" |
                                               // "dual" | "ta_marbuta" | "hamza" | "alef_variant" |
                                               // "alef_maqsura" | "spelling"

  "text_en": "<English scope text>",
  "text_ar": "<Arabic scope text, same meaning and same specificity>",

  "documents": [],                             // optional attachments; see 2.8
  // [{ "filename": "<name>", "text_en": "<extracted>", "text_ar": "<extracted>" }]

  "expect": {
    "detected_trades": [],                     // sorted; every trade with evidence, any disposition
    "active_trades": [],                       // sorted; subset of detected
    "trade_dispositions": {},                  // one entry per detected trade
    "component_dispositions": [],              // sorted by trade, then component
    // [{ "trade": "<key>", "component": "<key>", "disposition": "<key>" }]
    "clarification_required": false,
    "clarification_reason": null,
    "dispatch_blockers": [],                   // sorted
    "must_not_detect": [],                     // author assertion; see the note below
    "must_not_activate": []                    // author assertion; see the note below
  },

  "rationale": "<one or two sentences: why this expectation follows from the specification>",
  "spec_refs": ["<section numbers from part 2>"]
}
```

**Note on `must_not_detect` and `must_not_activate`.** These record author intent and are enforced by
the validator for internal consistency. They are **not separately counted** by the evaluator — the
per-trade confusion matrix in section 8 already scores every trade slot in every case, absent trades
included. Keeping them non-counting avoids double-counting the same error.

### 3.1 Validation rules — the validator must enforce every one

| # | rule |
|---|---|
| V1 | `case_key` unique and matches `^[A-R]-\d{3}$` |
| V2 | `bucket` is one of the 18 ids in section 4, and its letter matches the `case_key` prefix |
| V3 | `text_en` and `text_ar` are both non-empty, idiomatic in their own language, not transliterations or machine glosses of one another, and carry **the same scope meaning at the same specificity** |
| V4 | the key set of `trade_dispositions` equals `detected_trades` |
| V5 | every trade in `active_trades` appears in `detected_trades` |
| V6 | every trade in `active_trades` has a disposition whose `contributes` flag is set in 2.2 |
| V7 | no trade appears in both `active_trades` and `must_not_activate` |
| V8 | no trade appears in both `detected_trades` and `must_not_detect` |
| V9 | every trade in `component_dispositions` appears in `detected_trades`, and every detected trade has ≥ 1 component row |
| V10 | a trade with no stated split has exactly one component row, `complete_trade_scope`, whose disposition equals the trade disposition; a trade **with** a stated split has no `complete_trade_scope` row |
| V11 | a trade appears in `active_trades` **iff** its trade disposition contributes **and** it is not the case that all nine components are explicitly stated and all non-contributing |
| **V12** | if **any** disposition is `conflicted` — **in `trade_dispositions` or in `component_dispositions`** — then `clarification_required` is true, `scope_conflict_unresolved` is in `dispatch_blockers`, and `clarification_reason` is `conflict` |
| **V13** | `clarification_required` is true **iff** at least one of: some entry in `trade_dispositions` has `clarifies` set; **some entry in `component_dispositions` has `clarifies` set**; `clarification_reason` is `ambiguous_scope_binding`; `clarification_reason` is `no_trade_detected` |
| V14 | `clarification_reason` is null when clarification is not required; otherwise it is the **first applicable** entry in the 2.7 precedence table, computed over trade **and** component dispositions together |
| V15 | if `active_trades` is empty, `no_active_trade` is in `dispatch_blockers` |
| V16 | the two out-of-scope blockers named in 2.9 never appear |
| V17 | all trade keys from 2.1, dispositions from 2.2, components from 2.4, blockers from 2.9 |
| V18 | every array the schema marks sorted is sorted ascending; `cases` sorted by `case_key` |
| V19 | `rationale` is 1–2 non-empty sentences; `spec_refs` is non-empty and every entry names a real section of part 2 |
| V20 | a case with non-empty `documents` has ≥ 1 trade dispositioned `proposed`, unless that trade is also named in the text |
| V21 | `text_ar` is Unicode NFC and contains ≥ 1 character in the Arabic block |
| V22 | bucket counts meet the section 4 minimums; total ≥ 126 |
| V23 | all cross-cutting minimums in section 4 are met |
| **V24** | `clarification_pending` is in `dispatch_blockers` **iff** `clarification_required` is true. Every clarifying disposition in this suite meets at least one of the three criteria in 2.9 by construction. An author who believes they have a counterexample raises it as a specification gap in the manifest — they do not silently omit the blocker |

---

## 4. Coverage matrix

**Minimum 126 pairs — 252 interpretations.** Per-bucket figures are floors, not targets; exceed them
freely, but do not pad with near-duplicates. Two cases that differ only in a noun are one case.

| id | bucket | min pairs |
|---|---|---|
| A | `included_plain` — straightforward in-scope requests, one to three trades | 8 |
| B | `excluded_no_party` — scope removed, no other responsible party identified | 8 |
| C | `by_others_named` — another responsible party identified | 7 |
| D | `client_supplied` — the counterparty provides materials or equipment | 7 |
| E | `optional` — offered as an option or provisional item | 5 |
| F | `future_phase` — a later phase, stage or contract | 5 |
| G | `existing_only` — an existing installation with a work verb | 5 |
| H | `umbrella_exclusion_exception` — umbrella removal with a named exception | 7 |
| I | `umbrella_inclusion_exclusion` — umbrella inclusion with a named carve-out | 7 |
| J | `component_split` — lifecycle-stage splits across the nine components | 12 |
| K | `equal_specificity_conflict` — genuine same-level contradictions | 7 |
| L | `clause_boundary` — binding must succeed, and must fail, across boundaries | 7 |
| M | `mixed_language` — one language's sentence carrying the other's technical terms | 6 |
| N | `gulf_phrasing` — UAE market register | 6 |
| O | `arabic_morphology` — the morphological and orthographic variation classes in section 5 | 7 |
| P | `ambiguous_non_trade` — trade-adjacent vocabulary used in a non-trade sense | 10 |
| Q | `document_proposed` — trade evidence only in an attachment | 6 |
| R | `no_detection` — nothing should be detected at all | 6 |
| | **total** | **126** |

**Cross-cutting minimums**, satisfiable by cases anywhere in the table:

- ≥ 22 cases with `adversarial: true`
- ≥ 20 cases with a non-null `morphology_variant`, spanning ≥ 6 of the nine variant classes
- ≥ 15 cases carrying at least one entry in `must_not_detect`
- ≥ 10 cases with two or more component rows on the same trade
- each of the ten dispositions appears in ≥ 6 cases
- each of the nine components appears in ≥ 4 cases
- each of the five trades is `included` in ≥ 8 cases and non-contributing in ≥ 6
- ≥ 8 cases whose correct disposition is `unknown` because of an ambiguity the text does not resolve
- **≥ 8 cases where a trade is active and contributing while one of its components carries a
  clarifying disposition** — `optional`, `proposed`, `unknown` or `conflicted` — so that
  `clarification_required` is true even though the trade itself is clean. Spread these across at
  least three different components and at least three different trades. This is the shape a
  trade-level-only reading silently drops, and a suite without it cannot detect that failure.
- **≥ 3 cases where the *only* `conflicted` disposition is at component level**, so that
  `scope_conflict_unresolved` must be raised by a component contradiction alone
- each of the four clarifying dispositions appears at component level in ≥ 2 cases

---

## 5. Authoring rules

**Pairing.** One expectation per case, applied to both language texts. Parity then becomes a property
the implementation either has or lacks, rather than something the case file asserts. Never make one
language easier than its twin: matched specificity, matched hedging, matched sentence structure where
the languages permit it.

**Register.** Write what a contractor or estimator in the UAE market would actually send: enquiry and
tender correspondence, procurement documents, statutory and utility approval processes, local
building typologies, contract stages and defect-liability conventions. Use the vocabulary the market
uses. Do not caricature it.

**Arabic variation.** Vary deliberately across these classes and record which class each case uses:
definite article; attached proclitics and conjunctions; sound and broken plurals; duals; ta marbuta
versus ha; hamza forms; alef variants; alef maqsura versus yaa; and realistic tender-document
misspellings. Spread them across the buckets rather than concentrating them in bucket O.

**Mixed language.** Include Arabic sentences carrying English technical terms and English sentences
carrying Arabic terms, including cases where the borrowed term is inflected or pluralised in the host
language.

**Ambiguous non-trade vocabulary (bucket P).** The classes to cover are: umbrella service
abbreviations used to describe an organisation rather than a scope; engineering discipline names used
in a non-services sense; equipment abbreviations that collide with non-trade meanings; extent and
completeness adjectives applied to something other than services; container and grouping nouns
applied to something other than services; and abbreviations occurring as substrings of unrelated
terms. **Derive the specific vocabulary yourself from the two languages.** The bar is *plausible*:
every case must be a message a real customer could send. An absurd sentence tests nothing.

**Rationale.** Every case states in one or two sentences why the expectation follows, with
`spec_refs` pointing at part 2. **A case whose rationale cannot cite a rule is a case whose expected
outcome the author invented.** Delete it, or raise the specification gap in the manifest — do not
guess.

---

## 6. Validation, canonicalisation, checksum, seal

### 6.1 Validator

`validate_holdout_v2.mjs` enforces V1–V23, exits non-zero on the first failure, and prints the
coverage tables from which the manifest is generated. **No manifest figure may be typed by hand.**

### 6.2 Canonical form

A checksum over non-deterministic bytes is decoration. Canonical form is:

- UTF-8, **no BOM**
- every string Unicode **NFC**
- object keys sorted ascending at every level
- arrays sorted where the schema marks them sorted; `cases` sorted by `case_key`
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

The checksum is over the **file bytes**, and the file is written by the canonicaliser, so re-running
the canonicaliser over the delivered file must reproduce it unchanged. Report that round-trip in the
manifest.

### 6.3 Seal

`holdout_v2_seal.json`:

```json
{
  "holdout_version": "v2",
  "checksum_sha256": "<64 hex>",
  "case_count": 126,
  "canonicaliser": "validate_holdout_v2.mjs",
  "sealed_at": "<ISO-8601>",
  "sealed_by": "<session identifier>",
  "authored_from": "P2C1_HOLDOUT_V2_AUTHORING_BRIEF_SANITIZED.md",
  "brief_sha256": "<64 hex of this brief>",
  "independence": {
    "read_repository": false,
    "read_database": false,
    "read_prior_holdout": false,
    "read_failure_reports": false,
    "statement": "This session read only the sanitized authoring brief."
  },
  "immutability": "Expected outcomes are frozen. They may be changed only through the approved expectation-change controls, which require a stated reason, a work item and a named person."
}
```

**Sealing at load time is a separate, later act, and it is not optional.** Whoever loads v2 must, in
one transaction: create the case table, insert the cases, install a `BEFORE UPDATE OR DELETE` trigger
on the expectation columns that raises, insert the seal row carrying this checksum, and verify that a
checksum recomputed from the loaded rows equals the sealed one. **No evaluation may run before the
seal verifies.** The authoring session does none of this.

---

## 7. Authoring manifest

`holdout_v2_manifest.md`, generated by the validator:

```
# Holdout v2 — authoring manifest

checksum (sha256)          : <64 hex>
brief checksum (sha256)    : <64 hex>
total cases                : <n>
EN/AR pairs                : <n>    (must equal total cases)
interpretations            : <2n>
trade slots evaluated      : <2n × 5>
sealed at                  : <ISO-8601>

## Coverage by disposition            (cases in which the disposition appears)
included · existing_only · excluded · by_others · client_supplied
future_phase · optional · proposed · unknown · conflicted

## Component-scope coverage           (cases in which the component appears)
design · supply · installation · testing · commissioning
authority_approvals · maintenance · coordination · complete_trade_scope
component vocabulary source: verified against the approved model

## Per-trade coverage
              detected   contributing   non-contributing   must_not_detect
hvac / electrical / plumbing / fire / elv

## Bucket coverage
A..R, counts against the section 4 minimums

## Clarification
clarification required, total                      : <n>
  triggered by a trade disposition only            : <n>
  triggered by a component disposition only        : <n>
  triggered by both                                : <n>
cases: active trade + clarifying component         : <n>   (minimum 8)
cases: conflict at component level only            : <n>   (minimum 3)
clarifying dispositions at component level         : optional <n> · proposed <n> ·
                                                     unknown <n> · conflicted <n>
by clarification_reason                            : conflict <n> · ambiguous_trade <n> ·
                                                     unconfirmed_proposal <n> ·
                                                     optional_pending_decision <n> ·
                                                     ambiguous_scope_binding <n> ·
                                                     no_trade_detected <n>

## Adversarial and variation
adversarial cases · cases with must_not_detect · morphology variants by class
mixed-language cases · Gulf-register cases · document-bearing cases

## Specification gaps raised by the author
<any case the author could not ground in part 2, and what is missing>

## Validation
V1..V23                    : all pass
canonical round-trip       : byte-identical
```

---

## 8. Evaluator reporting contract

Stated here so v2 is authored to support it, and so no metric can be quietly dropped once the results
are known. **The authoring session does not run any of this.**

### 8.1 Per-trade detection — a full confusion matrix

Detection is scored over **every trade slot in every case in both languages**:

> **denominator = 2 × case_count × 5 trades**

For each trade, and in total:

| cell | meaning |
|---|---|
| TP | expected detected, and detected |
| FN | expected detected, **not** detected |
| FP | **not** expected, but detected |
| TN | not expected, not detected |

Report, each with its denominator printed beside it:

- **detection accuracy** = (TP + TN) / (2 × case_count × 5)
- **detection recall** (sensitivity) = TP / (TP + FN)
- **detection specificity** = TN / (TN + FP)
- **detection precision** = TP / (TP + FP)
- **false-positive rate** = FP / (FP + TN)

A positive-only ratio may **never** be reported as "detection accuracy". If a single figure is quoted,
it is the confusion-matrix accuracy above, and it is named as such.

### 8.2 The other metrics

| metric | denominator | notes |
|---|---|---|
| case-level exact accuracy | 2 × case_count | every field of `expect` must match, in that language |
| active-trade-set accuracy | 2 × case_count | exact set equality |
| per-trade disposition accuracy | 2 × Σ expected `detected_trades` | an expected trade that was **not** detected scores **zero** here as well as in detection — it is never removed from this denominator |
| disposition errors on false detections | count | a detected-but-not-expected trade has no expected disposition; it is counted as a detection false positive and reported here, never folded into disposition accuracy |
| component-disposition accuracy | 2 × Σ expected `component_dispositions` | a component row that was not produced scores zero |
| clarification accuracy | 2 × case_count | |
| clarification accuracy, component-triggered subset | 2 × (cases where clarification is triggered by a component disposition) | **reported separately.** A system that derives clarification from trade dispositions alone will score well on the headline figure and near zero here; netting the two together hides exactly that failure |
| blocker-set accuracy | 2 × case_count | exact set equality |
| English/Arabic parity | case_count | EN and AR produce identical output, right or wrong |

### 8.3 Rules that may not be relaxed

1. **An undetected expected trade is a false negative and stays in every denominator** — detection
   *and* disposition. It may not be dropped on the grounds that there was no disposition to compare.
2. **An incorrectly detected absent trade is a false positive** and is counted in the confusion
   matrix. It may not be discarded as "extra".
3. **Parity is reported alongside correctness, never instead of it.** Both languages wrong in the same
   way is 100% parity and 0% correctness.
4. **Never print a bare ratio.** Every figure states whether it means execution, parity, correctness
   or integrity, and prints its denominator.
5. **Unsafe errors are counted and listed separately.** An **unsafe error** is any trade activated
   whose expected disposition is non-contributing — a wrong activation. The opposite direction,
   under-detection, is safe-direction: it costs a clarification question, not a wrong dispatch. Report
   the two directions separately and never net them off.
6. **A missed component-level clarification is an unsafe error, not a near miss.** Where the
   expectation requires clarification because of a component disposition and the system returns
   `clarification_required: false`, the case is counted as unsafe: the trade dispatches, the supplier
   brief goes out, and an unresolved option or contradiction inside the scope goes with it. It is
   reported in the unsafe list alongside wrong activations, never as a plain clarification miss.
7. **Every remaining failure is explained individually.** A failure list without diagnoses is not a
   result.

### 8.4 Acceptance thresholds

| criterion | threshold |
|---|---|
| case-level exact accuracy | ≥ 99% |
| English/Arabic parity | ≥ 99% |
| detection false positives on cases expecting non-detection | **0** |
| unsafe activations | **0** |
| missed component-level clarifications | **0** |
| clarification accuracy, component-triggered subset | ≥ 99% |
| unexplained failures | **0** |

**Do not tune to these.** If v2 fails, the correct response is to fix the interpretation rules, or to
correct a demonstrably wrong expectation through the approved change controls. Never soften a case,
and never edit the sealed file.

---

## 9. Prohibited actions, restated

- Do not open any repository path, including documentation.
- Do not connect to any database or use any database tool.
- Do not search for a previous holdout, its results, or any list of known issues.
- Do not run, evaluate, score or spot-check the cases against anything.
- Do not write cases you expect to pass, or avoid cases you expect to fail. You have no basis for
  either belief, and acquiring one disqualifies you from authoring.
- Do not adjust an expected outcome to make the suite look better. The expectations are the
  specification's answer, not a prediction of behaviour.
- Do not deliver fewer than 126 pairs, and do not pad the count with near-duplicates.

Stop after producing the four artefacts in section 0.
