# QuotesDone P2-C1 — sealed holdout v2, failure report

Companion to `P2C1_HOLDOUT_V2_RESULT_OF_RECORD.md`. Written **after** result of record `1` was
recorded and made immutable. **Nothing was fixed in this session.** No interpretation rule, alias,
weight, expectation or database function was changed; the interpretation-code fingerprint is
identical before and after (`26c2596817db2f01cf3d8af28e37ba78`).

99 of 131 cases failed in at least one language; 176 of 262 interpretations are not exact.
Every one of them is listed individually below with its diff and its root cause. There are
**no unexplained failures**.

---

## 1. What the numbers actually say

Three findings dominate, and they are structural rather than a long tail of vocabulary misses.

### 1.1 Nothing in the scope layer can ask a question

`clarification_required` is produced by the *trade-identification* stage plus the single
`scope_conflict` flag. It is not produced by the scope-disposition layer. The consequence is exact
and mechanical: a trade or component carrying `optional`, `proposed` or `unknown` is recorded
correctly in `v_trade_scope_status` / `v_scope_disposition_effective`, is correctly non-contributing
— and then asks nothing.

* **Component-triggered clarification accuracy: 0 / 28.** Not one of the 14 cases built for the
  v2.1 amendment produced a question.
* 51 of the 68 interpretations that expect a clarification did not ask.
* The reference table `scope_disposition_kind` already carries `requires_clarification = true` for
  `optional`, `proposed`, `unknown` and `conflicted`, and `v_trade_scope_status` already exposes a
  `requires_clarification` column. The flag is computed and then never read. This is a wiring
  defect, not a modelling gap, which is why it shows as a clean 0 / 28 rather than a scatter.
* Per rule 8.3.6 of the brief every one of these 28 is an **unsafe** error: the trade dispatches
  and the unresolved option or contradiction goes out inside the supplier brief.

### 1.2 A named responsible party does not, by itself, mean `by_others`

Stage B.7 replaced the old phrase list with a composed rule: *removal marker* + *party marker* +
*attribution connector*. The composition is sound, but it still requires a **removal marker** to be
present. Ordinary attributive scope statements carry a party and no removal marker at all:

> "Fire fighting is under the specialist contractor appointed directly by the developer."
> "The ELV package is with the client's IT integrator."
> "HVAC is with the nominated subcontractor named in the tender."
> "The ELV works for the building are with another contractor."

`specialist contractor`, `nominated subcontractor`, `another contractor` and `client` are all
already in the party vocabulary. In each case the trade fell through to the default `included`,
activated, and would have been dispatched to a supplier. That is 14 unsafe activations on trades
the customer explicitly said someone else is doing — the single most expensive class in this run.

The mirror-image gap is the removal-marker list itself: 92 English and Arabic disposition patterns
do not cover "not **included** in our scope", "outside the scope of **this offer**", "not part of
what we will deliver", or "**dropped** from our scope", even though they cover the near neighbours
"not in our scope", "outside our scope", "not part of our scope" and "removed from our scope".
13 further unsafe activations come from there.

### 1.3 Contradiction is only detected at trade level, and only for the listed phrasings

`scope_conflict` fires when two trade-level markers of equal specificity disagree using recognised
phrases (`K-001` EN passes end to end). It does **not** fire when the contradiction sits on a
component (`K-005` approvals, `K-006` coordination, `K-007` maintenance, `K-008` testing) — those
resolve silently to `included`. It also misses trade-level contradictions expressed through document
names rather than markers (`K-002` covering letter vs scope matrix, `K-004` Arabic). Five trades
were activated whose sealed expectation is `conflicted`.

### 1.4 English and Arabic are not the same system

Parity is 81 / 131. The asymmetries are specific, not diffuse:

* the Arabic MEP umbrella confirms `electrical` and `plumbing` but leaves `hvac` a weak proposal —
  12 cases, always in the same direction (`A-007`, `H-002`, `H-003`, `I-001`, `I-002`, `I-004`,
  `I-005`, `I-006`, `I-007`, `K-004`, `L-003`, and `H-006` in mirror);
* Arabic equipment aliases are missing where the English ones exist — chillers, ductwork, intercom,
  water tanks, pumps (`D-001`, `D-005`, `G-005`, `K-008`, `Q-001`, `Q-002`, `Q-005`, `Q-006`);
* the reverse also happens: `O-003` "air conditioners", `O-006` "fire extinguishing works",
  `G-004` "chilled water pumps", `N-003` "water tanks and pumps" are missed in **English** and
  found in Arabic.

Both directions are alias-catalogue coverage, not grammar. Part 3 closed the two Arabic false
negatives that holdout v1 exposed; v2 shows the catalogue is still asymmetric in both directions.

### 1.5 Two smaller but sharp defects

* **A bare English "MEP works" umbrella identifies no trade.** `fn_mep_full_scope` requires a
  completeness or container word beside the anchor, so "The MEP works for the villa are within our
  scope" (`A-007`) produced scope dispositions for all three core trades and **zero** candidates,
  hence zero active workstreams — the disposition record and the workstream record disagree with
  each other inside the same interpretation. This is the single case in bucket A that failed.
* **The token `no` is a disposition marker.** In `N-004`, "Civil Defence **no**-objection
  certificate" excluded the fire trade the customer was asking to price. `no` and `without` are
  listed as bare exclusion patterns; they carry no scope meaning on their own.

### 1.6 The two fields the implementation does not have

`clarification_reason` and `dispatch_blockers` are not produced anywhere in the system. They were
derived for scoring from the implementation's own outputs (§7 of the result of record). This is a
reporting gap rather than a semantic one, but it matters operationally: an operator reading the
record today cannot tell *why* a question was asked, and the `scope_conflict_unresolved` and
`no_active_trade` blockers named in the specification exist only as inferences. **No case's verdict
depends on it** — 0 interpretations fail on a derived field alone.

---

## 2. Classification summary

| classification | root causes | failing cases |
|---|---|---|
| implementation defect | RC-01 … RC-08, RC-09a, RC-09c, RC-10, RC-11, RC-12, RC-14, RC-16, RC-17, RC-18 | 95 |
| unsupported vocabulary | RC-09b (Arabic aliases), RC-13 (English aliases) | 18 |
| specification ambiguity | RC-15 (ambiguous abbreviations, candidate set) | 2 |
| demonstrably incorrect sealed expectation | none found | 0 |
| evaluator defect | none found | 0 |
| environmental failure | none — 262 / 262 executed, 0 errors | 0 |

Cases can carry more than one root cause, so the column sums exceed 99.

**On the "unsupported vocabulary" line.** These are catalogue-coverage gaps, not defects in the
matching machinery: the missing alias exists in the other language, so the machinery demonstrably
works. They are separated because the fix is data, not code, and because a vocabulary fix must not
be mistaken for a semantic fix.

**On "demonstrably incorrect sealed expectation".** I found none. Two expectations are worth a
review under the existing **P2-C5 expectation-change controls**, and neither may be changed here —
the sealed file was not edited and the case table refuses UPDATE and DELETE:

1. **`P-007` and `P-008` (RC-15).** The sealed manifest already raises this as specification gap 3:
   §2.3 rule 4 fixes an ambiguous short form as `unknown` but does not say whether both candidate
   trades are detected or neither. The author detected *every* candidate. `P-008` "the AC panels"
   therefore expects both `electrical` and `hvac` as `unknown`, while §2.3 rule 4's own second
   sentence — "where the surrounding text disambiguates, use the disambiguated reading" — arguably
   makes "panels" disambiguating. The implementation proposed `hvac` alone. **Whichever way this is
   resolved, the implementation is still wrong**: it returns `proposed`, not `unknown`, and it does
   not ask. Resolving the gap changes the diagnosis, not the verdict.
2. **`L-007` (RC-11).** "Kindly quote the HVAC, electrical and plumbing works in full" expects
   `ambiguous_scope_binding`. That reading follows §2.6 and §2.7 rule 5, but it is the only case in
   the suite that turns on it, and `ambiguous_scope_binding` is not modelled anywhere in the
   implementation. Worth confirming the expectation is what the business wants before anyone builds
   binding-ambiguity detection to satisfy a single case.

---

## 3. Recommended order of work — not done here

Ordered by expected reduction in unsafe outcomes per unit of work, not by case count.

| # | change | closes | why first |
|---|---|---|---|
| 1 | Read `requires_clarification` from the scope layer into `clarification_required`, at trade **and** component level, and stop asking when nothing was detected in a non-scope message | RC-05 (26 cases), RC-06 (28 cases) | Turns 28 unsafe silent dispatches into questions, and removes 49 spurious questions. The flag is already computed; this is wiring. |
| 2 | Treat an attributed party as sufficient for `by_others` without a removal marker | RC-02 (9 cases) | 14 unsafe activations, the most expensive per case: a supplier is dispatched for work the customer said is someone else's. |
| 3 | Extend conflict detection to component level and to document-name contradictions | RC-08 (13 cases) | 5 unsafe activations plus the whole component-conflict class the v2.1 amendment exists to catch. |
| 4 | Apply component-level overrides for `by_others`, `client_supplied`, `future_phase`, `unknown` | RC-04 (40 cases), RC-17 (4 cases) | Largest single case count; each one silently widens the quoted scope. |
| 5 | Compose removal markers instead of listing them; delete the bare `no` / `without` patterns | RC-01 (19), RC-03 (2), RC-12 (1) | 17 unsafe activations, and `no` is actively harmful. |
| 6 | Make the exception clause defeat the umbrella (specificity ladder rank 3) | RC-07 (8 cases) | Fails in both directions today; H-002 activates three trades the customer excluded. |
| 7 | Even up the alias catalogue in both directions; fire the umbrella on a bare "MEP works" | RC-09a/b (26), RC-10, RC-13 (6), RC-14 | Restores parity; mechanical and low risk. |
| 8 | Emit `clarification_reason` and `dispatch_blockers` as first-class fields | RC-11 | Not a correctness fix. It is what makes every future evaluation readable, and it removes a derivation from the evaluator. |

Items 1–3 alone would move case-level exact accuracy, unsafe activations and the component-triggered
subset more than everything else combined. None of it was attempted in this session.

---

## Root-cause register

| id | defect | classification | cases | case keys |
|---|---|---|---|---|
| RC-01 | Removal-marker vocabulary gap | implementation defect | 19 | B-001 B-003 B-004 B-005 B-006 D-003 E-002 E-004 G-001 I-006 J-008 J-014 N-001 O-005 P-001 P-002 P-003 P-004 Q-003 |
| RC-02 | Named responsible party without a removal marker is not by_others | implementation defect | 9 | C-001 C-002 C-003 C-004 C-006 C-007 H-003 O-007 P-009 |
| RC-03 | future_phase marker gap | implementation defect | 2 | F-002 F-004 |
| RC-04 | Component-level override not applied; the component inherits included | implementation defect | 40 | B-001 B-003 B-004 B-005 B-006 C-001 C-002 C-003 C-004 C-005 C-006 C-007 E-002 E-003 E-004 F-002 F-003 F-004 G-001 G-003 G-006 H-002 H-003 I-002 I-003 I-006 I-007 J-001 J-002 J-005 J-007 J-008 J-010 J-012 J-013 J-014 O-007 P-009 Q-004 Q-007 |
| RC-05 | No scope disposition raises clarification (optional / proposed / unknown) | implementation defect | 26 | E-001 E-002 E-003 E-004 E-005 G-003 G-005 G-006 I-006 J-007 J-008 J-009 J-013 J-014 K-001 K-002 K-003 K-004 K-005 K-006 K-007 K-008 Q-003 Q-004 Q-006 Q-007 |
| RC-06 | Clarification raised whenever nothing activates, including non-scope messages | implementation defect | 28 | B-002 D-001 D-004 D-005 F-001 G-004 H-001 H-003 H-005 H-007 I-001 I-003 I-005 N-003 N-004 O-003 O-004 O-006 P-001 P-003 P-004 P-005 P-006 R-001 R-002 R-003 R-005 R-006 |
| RC-07 | Exception clause does not defeat the umbrella statement (2.5 ladder rank 3) | implementation defect | 8 | H-001 H-002 H-003 H-005 H-006 I-001 I-002 I-005 |
| RC-08 | Conflict not detected: component level absent, trade level misses paraphrases | implementation defect | 13 | D-004 H-003 I-001 I-003 I-005 K-001 K-002 K-003 K-004 K-005 K-006 K-007 K-008 |
| RC-09a | Arabic umbrella yields hvac as a weak proposal while electrical and plumbing confirm | implementation defect | 12 | A-007 H-002 H-003 I-001 I-002 I-004 I-005 I-006 I-007 L-003 P-003 Q-003 |
| RC-09b | Arabic equipment alias gap | unsupported vocabulary | 14 | C-007 D-001 D-005 F-002 G-004 G-005 K-008 N-003 O-002 Q-001 Q-002 Q-003 Q-005 Q-006 |
| RC-09c | Arabic attribution bound to the wrong component | implementation defect | 1 | D-002 |
| RC-10 | Bare English "MEP works" umbrella identifies no trade | implementation defect | 1 | A-007 |
| RC-11 | ambiguous_scope_binding is not modelled | implementation defect | 1 | L-007 |
| RC-12 | Over-broad marker token ("no") produces a false exclusion | implementation defect | 1 | N-004 |
| RC-13 | English equipment alias gap | unsupported vocabulary | 6 | G-004 G-005 N-003 O-003 O-006 Q-006 |
| RC-14 | Mixed-language: the host-language matcher misses the embedded foreign term | implementation defect | 1 | M-005 |
| RC-15 | Ambiguous abbreviation: candidate set and unknown disposition | specification ambiguity | 2 | P-007 P-008 |
| RC-16 | Trade-adjacent vocabulary in a non-trade sense is detected as a trade | implementation defect | 0 | — |
| RC-17 | client_supplied actor and hand-over forms not recognised | implementation defect | 4 | D-003 D-004 D-006 D-007 |
| RC-18 | existing installation with no work verb is not unknown | implementation defect | 5 | G-003 G-005 G-006 J-008 K-008 |

---

## Every failing case, individually

### A-007 — included_plain (adversarial) · EN/AR parity: no

> EN: The MEP works for the villa are within our scope; kindly price them.
> AR: أعمال الميكانيكا والكهرباء والصحية للفيلا ضمن نطاق عملنا، نرجو تسعيرها.

*Sealed rationale:* An umbrella reference to the combined mechanical, electrical and plumbing services reaches the three core trades only. Fire and ELV are never reached implicitly and must not be detected here.  (spec 2.1, 2.2)

- **EN** — RC-10
    - `act` expected [electrical,hvac,plumbing] got []
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — RC-09a
    - `act` expected [electrical,hvac,plumbing] got [electrical,plumbing]
    - `disp` hvac: included -> proposed
    - `comp` hvac.complete_trade_scope: included -> proposed

---

### B-001 — excluded_no_party · EN/AR parity: yes

> EN: Our quotation covers the HVAC works only; the electrical works are not included in our scope.
> AR: عرضنا يشمل أعمال التكييف فقط؛ أعمال الكهرباء غير مشمولة في نطاق عملنا.

*Sealed rationale:* The removal of electrical tells us what we are not doing but identifies nobody else, so the disposition is excluded rather than by_others. Electrical is still detected because the text gives evidence of it.  (spec 2.3, 2.8)

- **EN** — RC-01, RC-04
    - `act` expected [hvac] got [electrical,hvac]
    - `disp` electrical: excluded -> included
    - `comp` electrical.complete_trade_scope: excluded -> included
- **AR** — RC-01, RC-04
    - `act` expected [hvac] got [electrical,hvac]
    - `disp` electrical: excluded -> included
    - `comp` electrical.complete_trade_scope: excluded -> included

---

### B-002 — excluded_no_party · EN/AR parity: yes

> EN: The plumbing works are excluded from this proposal.
> AR: اعمال السباكة مستثناة من هذا العرض.

*Sealed rationale:* A single trade is removed from scope with no other party identified, so it is detected as excluded and does not contribute. With no trade active the no_active_trade blocker is raised.  (spec 2.3, 2.9)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### B-003 — excluded_no_party · EN/AR parity: no

> EN: We will carry out the HVAC works. The fire fighting works are outside the scope of this offer.
> AR: سنقوم بتنفيذ أعمال التكييف. أما أعمال مكافحة الحريق فهي خارج نطاق هذا العرض.

*Sealed rationale:* Fire is named and removed with no responsible party identified, so it is excluded and detected. HVAC remains the only active trade.  (spec 2.3, 2.8)

- **EN** — RC-01, RC-04
    - `act` expected [hvac] got [fire,hvac]
    - `disp` fire: excluded -> included
    - `comp` fire.complete_trade_scope: excluded -> included
- **AR** — matched the sealed expectation in full.

---

### B-004 — excluded_no_party · EN/AR parity: yes

> EN: Electrical works are included. The ELV and security systems are not part of what we will deliver.
> AR: أعمال الكهرباء مشمولة. أما أنظمة التيار الخفيف والأمن فليست جزءًا مما سنقوم بتنفيذه.

*Sealed rationale:* ELV is named and removed without any other party being identified, which is excluded and not by_others. Electrical contributes and activates.  (spec 2.2, 2.3)

- **EN** — RC-01, RC-04
    - `act` expected [electrical] got [electrical,elv]
    - `disp` elv: excluded -> included
    - `comp` elv.complete_trade_scope: excluded -> included
- **AR** — RC-01, RC-04
    - `act` expected [electrical] got [electrical,elv]
    - `disp` elv: excluded -> included
    - `comp` elv.complete_trade_scope: excluded -> included

---

### B-005 — excluded_no_party · EN/AR parity: yes

> EN: We are pricing the plumbing package. The electrical works have been dropped from our scope on this project.
> AR: نقوم بتسعير حزمة أعمال السباكة، وقد استُبعدت أعمال الكهرباء من نطاقنا في هذا المشروع.

*Sealed rationale:* Dropping a trade from our scope without naming a successor is excluded. Plumbing is unaffected and remains active.  (spec 2.3)

- **EN** — RC-01, RC-04
    - `act` expected [plumbing] got [electrical,plumbing]
    - `disp` electrical: excluded -> included
    - `comp` electrical.complete_trade_scope: excluded -> included
- **AR** — RC-01, RC-04
    - `act` expected [plumbing] got [electrical,plumbing]
    - `disp` electrical: excluded -> included
    - `comp` electrical.complete_trade_scope: excluded -> included

---

### B-006 — excluded_no_party (adversarial) · EN/AR parity: yes

> EN: The HVAC works are not included in our scope of works.
> AR: أعمال التكييف غير مشمولة في نطاق أعمالنا.

*Sealed rationale:* Language that removes a trade from our scope does not by itself say who will do it, so the disposition is excluded and never by_others. The trade is detected but does not activate.  (spec 2.3, 2.8)

- **EN** — RC-01, RC-04
    - `act` expected [] got [hvac]
    - `disp` hvac: excluded -> included
    - `comp` hvac.complete_trade_scope: excluded -> included
    - `blk` expected [no_active_trade] got []
- **AR** — RC-01, RC-04
    - `act` expected [] got [hvac]
    - `disp` hvac: excluded -> included
    - `comp` hvac.complete_trade_scope: excluded -> included
    - `blk` expected [no_active_trade] got []

---

### C-001 — by_others_named · EN/AR parity: no

> EN: The electrical works will be carried out by the main contractor's own subcontractor; we are pricing the HVAC only.
> AR: سيقوم مقاول الباطن التابع للمقاول الرئيسي بتنفيذ أعمال الكهرباء؛ ونحن نسعّر أعمال التكييف فقط.

*Sealed rationale:* A responsible party is identified by role, so the electrical trade is by_others rather than excluded. HVAC is included and is the only active trade.  (spec 2.2, 2.3)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-02, RC-04
    - `act` expected [hvac] got [electrical,hvac]
    - `disp` electrical: by_others -> included
    - `comp` electrical.complete_trade_scope: by_others -> included

---

### C-002 — by_others_named · EN/AR parity: yes

> EN: Fire fighting is under the specialist contractor appointed directly by the developer.
> AR: أعمال مكافحة الحريق تقع على عاتق المقاول المتخصص المعيّن مباشرة من قبل المطوّر.

*Sealed rationale:* Another party is identified by role and by appointing organisation, so fire is by_others and is detected without activating. No trade is active, so the no_active_trade blocker is raised.  (spec 2.3, 2.9)

- **EN** — RC-02, RC-04
    - `act` expected [] got [fire]
    - `disp` fire: by_others -> included
    - `comp` fire.complete_trade_scope: by_others -> included
    - `blk` expected [no_active_trade] got []
- **AR** — RC-02, RC-04
    - `act` expected [] got [fire]
    - `disp` fire: by_others -> included
    - `comp` fire.complete_trade_scope: by_others -> included
    - `blk` expected [no_active_trade] got []

---

### C-003 — by_others_named · EN/AR parity: yes

> EN: The ELV package is with the client's IT integrator. We will handle the electrical works.
> AR: حزمة التيار الخفيف مع مزوّد أنظمة تقنية المعلومات لدى العميل. وسنتولى نحن أعمال الكهرباء.

*Sealed rationale:* An identified third party holds the ELV package, which is by_others and not client_supplied because the integrator is not the counterparty itself. Electrical is included.  (spec 2.3)

- **EN** — RC-02, RC-04
    - `act` expected [electrical] got [electrical,elv]
    - `disp` elv: by_others -> included
    - `comp` elv.complete_trade_scope: by_others -> included
- **AR** — RC-02, RC-04
    - `act` expected [electrical] got [electrical,elv]
    - `disp` elv: by_others -> included
    - `comp` elv.complete_trade_scope: by_others -> included

---

### C-004 — by_others_named (adversarial) · EN/AR parity: no

> EN: Plumbing is by others. Please quote the HVAC and electrical scope.
> AR: أعمال السباكة على عهدة الغير. نرجو تسعير نطاق التكييف والكهرباء.

*Sealed rationale:* The bare construction designating a third party is understood by the reader as identifying another responsible party, so plumbing is by_others rather than excluded. The other two named trades are included.  (spec 2.3)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-02, RC-04
    - `act` expected [electrical,hvac] got [electrical,hvac,plumbing]
    - `disp` plumbing: by_others -> included
    - `comp` plumbing.complete_trade_scope: by_others -> included

---

### C-005 — by_others_named · EN/AR parity: yes

> EN: The authority approvals for the electrical works will be submitted by the consultant; the rest of the electrical scope is ours.
> AR: سيتولى الاستشاري تقديم موافقات الجهات الخاصة بأعمال الكهرباء، أما بقية نطاق أعمال الكهرباء فهي علينا.

*Sealed rationale:* A component-level statement about a named trade defeats the trade-level statement for that component only, so approvals are by_others while the unstated components inherit included. The trade stays active because its trade-level disposition contributes.  (spec 2.4, 2.5)

- **EN** — RC-04
    - `comp` electrical.authority_approvals: by_others -> included
- **AR** — RC-04
    - `comp` electrical.authority_approvals: by_others -> included

---

### C-006 — by_others_named · EN/AR parity: yes

> EN: HVAC is with the nominated subcontractor named in the tender; kindly quote the plumbing works only.
> AR: أعمال التكييف مع مقاول الباطن المسمّى في وثائق المناقصة؛ نرجو تسعير أعمال السباكة فقط.

*Sealed rationale:* A nominated subcontractor is an identified other party, so HVAC is by_others and detected but not active. Plumbing is included.  (spec 2.3, 2.8)

- **EN** — RC-02, RC-04
    - `act` expected [plumbing] got [hvac,plumbing]
    - `disp` hvac: by_others -> included
    - `comp` hvac.complete_trade_scope: by_others -> included
- **AR** — RC-02, RC-04
    - `act` expected [plumbing] got [hvac,plumbing]
    - `disp` hvac: by_others -> included
    - `comp` hvac.complete_trade_scope: by_others -> included

---

### C-007 — by_others_named · EN/AR parity: no

> EN: The security systems are in the developer's direct package. The fire and life safety works remain with us.
> AR: أنظمة الأمن ضمن حزمة المطوّر المباشرة، وتبقى أعمال الحريق والسلامة لدينا.

*Sealed rationale:* The developer is identified as the responsible party for the security scope, making it by_others. Fire is named directly and remains included.  (spec 2.1, 2.3)

- **EN** — RC-02, RC-04
    - `act` expected [fire] got [elv,fire]
    - `disp` elv: by_others -> included
    - `comp` elv.complete_trade_scope: by_others -> included
- **AR** — RC-09b
    - `det` expected [elv,fire] got [fire]
    - `disp` elv: by_others -> NOT DETECTED
    - `comp` elv.complete_trade_scope: by_others -> (absent)

---

### D-001 — client_supplied · EN/AR parity: no

> EN: The chillers will be supplied by the client; we are to install, test and commission them.
> AR: سيقوم العميل بتوريد المبردات، وعلينا تركيبها واختبارها وتشغيلها وتسليمها.

*Sealed rationale:* The counterparty providing equipment is client_supplied and must not collapse into by_others, and it sits on the supply component only. The trade is active because its trade-level disposition contributes and the remaining stages are ours.  (spec 2.3, 2.4)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-09b, RC-06
    - `det` expected [hvac] got []
    - `act` expected [hvac] got []
    - `disp` hvac: included -> NOT DETECTED
    - `comp` hvac.commissioning: included -> (absent)
    - `comp` hvac.installation: included -> (absent)
    - `comp` hvac.supply: client_supplied -> (absent)
    - `comp` hvac.testing: included -> (absent)
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [] got [clarification_pending,no_active_trade]

---

### D-002 — client_supplied · EN/AR parity: no

> EN: All sanitary wares are free issue by the client and will be fixed by us.
> AR: جميع الأدوات الصحية يوردها العميل مجانًا وسنقوم نحن بتركيبها.

*Sealed rationale:* Free issue by the counterparty is client_supplied on the supply component while the fixing work stays ours. The trade remains active with one non-contributing component.  (spec 2.3, 2.4)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-09c
    - `comp` plumbing.installation: included -> client_supplied
    - `comp` plumbing.supply: client_supplied -> included

---

### D-003 — client_supplied · EN/AR parity: no

> EN: Light fittings are client supplied; our price is for the electrical installation only.
> AR: وحدات الانارة يوردها العميل، وسعرنا يشمل التركيبات الكهربائيه فقط.

*Sealed rationale:* Materials provided by the counterparty are client_supplied on the supply stage, and the installation stage remains included. Tender-document misspellings do not change the reading.  (spec 2.3, 2.4)

- **EN** — RC-01, RC-17
    - `det` expected [electrical] got [electrical,plumbing]
    - `act` expected [electrical] got [electrical,plumbing]
    - `disp` plumbing: (not expected) -> included
    - `comp` electrical.supply: client_supplied -> included
- **AR** — RC-17
    - `comp` electrical.supply: client_supplied -> included

---

### D-004 — client_supplied · EN/AR parity: no

> EN: The CCTV cameras and recorders are provided by the client from their central procurement, and no other ELV scope is requested.
> AR: كاميرات المراقبة وأجهزة التسجيل يوفرها العميل من مشترياته المركزية، ولا يوجد نطاق آخر مطلوب من أعمال التيار الخفيف.

*Sealed rationale:* The counterparty provides the equipment and no work around it is requested, so the trade-level disposition is client_supplied and does not contribute. With no active trade the no_active_trade blocker is raised.  (spec 2.2, 2.3, 2.9)

- **EN** — RC-17, RC-06
    - `disp` elv: client_supplied -> excluded
    - `comp` elv.complete_trade_scope: client_supplied -> excluded
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-08, RC-06
    - `disp` elv: client_supplied -> conflicted
    - `comp` elv.complete_trade_scope: client_supplied -> conflicted
    - `clar` expected false got true
    - `rsn` expected null got conflict
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade,scope_conflict_unresolved]

---

### D-005 — client_supplied (adversarial) · EN/AR parity: no

> EN: The ductwork material is free issue by the employer; the installation remains in our scope.
> AR: مواد مجاري الهواء يوردها صاحب العمل مجانًا، ويبقى التركيب ضمن نطاقنا.

*Sealed rationale:* The employer is the counterparty, not a third party, so this is client_supplied and not by_others even though someone other than us provides the material. The distinction changes who is invoiced and must survive.  (spec 2.3)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-09b, RC-06
    - `det` expected [hvac] got []
    - `act` expected [hvac] got []
    - `disp` hvac: included -> NOT DETECTED
    - `comp` hvac.installation: included -> (absent)
    - `comp` hvac.supply: client_supplied -> (absent)
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [] got [clarification_pending,no_active_trade]

---

### D-006 — client_supplied · EN/AR parity: yes

> EN: The client will hand over the fire extinguishers and hose reels to us; we will install and test them.
> AR: سيسلمنا العميل طفايات الحريق وبكرات الخراطيم، وسنقوم بتركيبها واختبارها.

*Sealed rationale:* Fire is named directly and the counterparty supplies the equipment, so supply is client_supplied while installation and testing are included. The trade contributes and activates.  (spec 2.1, 2.3, 2.4)

- **EN** — RC-17
    - `comp` fire.supply: client_supplied -> included
- **AR** — RC-17
    - `comp` fire.supply: client_supplied -> included

---

### D-007 — client_supplied (adversarial) · EN/AR parity: yes

> EN: The client supplies the booster pumps, the builder's work in the pump room is with the main contractor, and we carry out the plumbing installation.
> AR: يقوم العميل بتوريد مضخات التقوية، وأعمال البناء في غرفة المضخات مع المقاول الرئيسي، ونقوم نحن بتنفيذ أعمال تركيب السباكة.

*Sealed rationale:* Counterparty supply is client_supplied on the supply stage, and the reference to a main contractor attaches to builder's work rather than to any trade in the vocabulary. No second trade is detected from a non-trade subject.  (spec 2.3, 2.6)

- **EN** — RC-17
    - `comp` plumbing.supply: client_supplied -> included
- **AR** — RC-17
    - `comp` plumbing.supply: client_supplied -> included

---

### E-001 — optional · EN/AR parity: yes

> EN: The HVAC works are in our scope. A one-year maintenance contract is offered as an option for your consideration.
> AR: أعمال التكييف ضمن نطاقنا. ونعرض عقد صيانة لمدة سنة كخيار اختياري لتقديره من جانبكم.

*Sealed rationale:* An option sits on the maintenance component while the trade itself is clean and active, and a clarifying component disposition demands clarification on its own. The unresolved option changes the quoted component scope, so the clarification_pending blocker applies.  (spec 2.4, 2.7, 2.9)

- **EN** — RC-05
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-05
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []

---

### E-002 — optional · EN/AR parity: yes

> EN: The ELV and security package is quoted as a provisional item; the client has not yet decided whether to proceed.
> AR: حزمة التيار الخفيف والأمن مسعّرة كبند احتياطي، ولم يقرر العميل بعد المضي فيها.

*Sealed rationale:* A provisional item on which the customer has not decided is optional, which never activates and always clarifies. No trade is active, so both the clarification and the no_active_trade blockers are raised.  (spec 2.2, 2.3, 2.9)

- **EN** — RC-01, RC-04, RC-05
    - `act` expected [] got [elv]
    - `disp` elv: optional -> included
    - `comp` elv.complete_trade_scope: optional -> included
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending,no_active_trade] got []
- **AR** — RC-01, RC-04, RC-05
    - `act` expected [] got [elv]
    - `disp` elv: optional -> included
    - `comp` elv.complete_trade_scope: optional -> included
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending,no_active_trade] got []

---

### E-003 — optional · EN/AR parity: no

> EN: The electrical installation is included. Detailed design is offered as an option if you wish us to take it on.
> AR: التركيبات الكهربائية مشمولة. والتصميم التفصيلي معروض كخيار إذا رغبتم بأن نتولاه.

*Sealed rationale:* The design stage is offered as an option while the installation stage is included, so the trade is active with a clarifying component. Clarification is required even though the trade-level disposition is clean.  (spec 2.4, 2.7)

- **EN** — RC-05
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-04, RC-05
    - `comp` electrical.design: optional -> included
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []

---

### E-004 — optional · EN/AR parity: no

> EN: HVAC is confirmed. The plumbing works are offered as an option and the client will decide later.
> AR: اعمال التكييف مؤكدة. أما أعمال السباكة فمعروضة كخيار وسيقرر العميل لاحقًا.

*Sealed rationale:* An option at trade level does not activate and requires clarification, so plumbing is detected but excluded from the active set. HVAC remains active, so no_active_trade is not raised.  (spec 2.2, 2.7, 2.9)

- **EN** — RC-05
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-01, RC-04, RC-05
    - `act` expected [hvac] got [hvac,plumbing]
    - `disp` plumbing: optional -> included
    - `comp` plumbing.complete_trade_scope: optional -> included
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []

---

### E-005 — optional · EN/AR parity: yes

> EN: The ELV works are included. Coordination with the interior fit-out contractor is offered as an optional item.
> AR: أعمال التيار الخفيف مشمولة. والتنسيق مع مقاول التشطيبات الداخلية معروض كبند اختياري.

*Sealed rationale:* The coordination stage carries the option while the trade stays active, which is exactly the shape a trade-level-only reading drops. The answer changes what a supplier would be told to do, so the clarification blocker applies.  (spec 2.4, 2.7, 2.9)

- **EN** — RC-05
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-05
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []

---

### F-001 — future_phase · EN/AR parity: yes

> EN: The ELV and security systems belong to Phase 2 of the development.
> AR: أنظمة التيار الخفيف والأمن تعود إلى المرحلة الثانية من المشروع.

*Sealed rationale:* Work assigned to a later phase is future_phase, which never activates. Future phase is not a clarifying disposition, so clarification is not required.  (spec 2.2, 2.3)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### F-002 — future_phase · EN/AR parity: no

> EN: Please price the HVAC works for the current stage. The plumbing works fall under the next stage of the contract.
> AR: نرجو تسعير أعمال التكيف للمرحلة الحالية. أما أعمال السباكة فتقع ضمن المرحلة التالية من العقد.

*Sealed rationale:* Plumbing is deferred to a later stage and is detected as future_phase without activating. HVAC is priced now and is the only active trade.  (spec 2.2, 2.8)

- **EN** — RC-03, RC-04
    - `act` expected [hvac] got [hvac,plumbing]
    - `disp` plumbing: future_phase -> included
    - `comp` plumbing.complete_trade_scope: future_phase -> included
- **AR** — RC-03, RC-09b, RC-04
    - `det` expected [hvac,plumbing] got [plumbing]
    - `act` expected [hvac] got [plumbing]
    - `disp` hvac: included -> NOT DETECTED
    - `disp` plumbing: future_phase -> included
    - `comp` hvac.complete_trade_scope: included -> (absent)
    - `comp` plumbing.complete_trade_scope: future_phase -> included

---

### F-003 — future_phase · EN/AR parity: yes

> EN: The HVAC installation is in this contract; maintenance will be awarded later under a separate operation and maintenance contract.
> AR: تركيب أنظمة التكييف ضمن هذا العقد، أما الصيانة فسيتم ترسيتها لاحقًا ضمن عقد تشغيل وصيانة منفصل.

*Sealed rationale:* The maintenance stage belongs to a later contract, so a component override carries future_phase while the trade stays active. Future phase does not clarify, so no clarification is required.  (spec 2.4, 2.7)

- **EN** — RC-04
    - `comp` hvac.maintenance: future_phase -> included
- **AR** — RC-04
    - `comp` hvac.maintenance: future_phase -> included

---

### F-004 — future_phase · EN/AR parity: yes

> EN: Electrical is required now. The fire fighting works are deferred to the second contract.
> AR: أعمال الكهرباء مطلوبة الآن، وأعمال مكافحة الحريق مؤجلة إلى العقد الثاني.

*Sealed rationale:* Fire is named directly and deferred to a later contract, which is future_phase and does not contribute. Electrical activates.  (spec 2.1, 2.2)

- **EN** — RC-03, RC-04
    - `act` expected [electrical] got [electrical,fire]
    - `disp` fire: future_phase -> included
    - `comp` fire.complete_trade_scope: future_phase -> included
- **AR** — RC-03, RC-04
    - `act` expected [electrical] got [electrical,fire]
    - `disp` fire: future_phase -> included
    - `comp` fire.complete_trade_scope: future_phase -> included

---

### G-001 — existing_only · EN/AR parity: no

> EN: Please survey the existing HVAC installation in the building and propose the modifications required.
> AR: نرجو معاينة أنظمة التكييف القائمة في المبنى واقتراح التعديلات المطلوبة.

*Sealed rationale:* An existing installation named together with a survey and a modification is existing_only, and the trade is active because there is work to do. No lifecycle split is stated, so a single complete_trade_scope row carries the trade disposition.  (spec 2.3, 2.4)

- **EN** — RC-01, RC-04
    - `disp` hvac: existing_only -> included
    - `comp` hvac.complete_trade_scope: existing_only -> included
- **AR** — matched the sealed expectation in full.

---

### G-003 — existing_only (adversarial) · EN/AR parity: no

> EN: The premises have an existing electrical installation left by the previous tenant.
> AR: يوجد في المحل تركيبات كهربائية قائمة تركها المستأجر السابق.

*Sealed rationale:* An existing installation mentioned with no action at all is unknown rather than existing_only, because nothing tells us whether any work is required. The unknown disposition clarifies and does not contribute.  (spec 2.2, 2.3)

- **EN** — RC-18, RC-04, RC-05
    - `act` expected [] got [electrical]
    - `disp` electrical: unknown -> included
    - `comp` electrical.complete_trade_scope: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending,no_active_trade] got []
- **AR** — RC-18, RC-04, RC-05
    - `act` expected [] got [electrical]
    - `disp` electrical: unknown -> included
    - `comp` electrical.complete_trade_scope: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending,no_active_trade] got []

---

### G-004 — existing_only · EN/AR parity: yes

> EN: We require the existing chilled water pumps to be maintained under an annual contract.
> AR: نطلب صيانة مضخات المياه المبردة القائمة بموجب عقد سنوي.

*Sealed rationale:* Maintenance of an existing installation is a service obligation and therefore existing_only, which contributes. The text addresses the maintenance stage only, so that single component row is stated and the rest inherit.  (spec 2.3, 2.4)

- **EN** — RC-13, RC-06
    - `det` expected [hvac] got []
    - `act` expected [hvac] got []
    - `disp` hvac: existing_only -> NOT DETECTED
    - `comp` hvac.maintenance: existing_only -> (absent)
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — RC-09b, RC-06
    - `det` expected [hvac] got []
    - `act` expected [hvac] got []
    - `disp` hvac: existing_only -> NOT DETECTED
    - `comp` hvac.maintenance: existing_only -> (absent)
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [] got [clarification_pending,no_active_trade]

---

### G-005 — existing_only · EN/AR parity: no

> EN: The existing water supply pipework is to be replaced throughout the block, and there is also an existing intercom system in the lobby.
> AR: يجب استبدال شبكة تغذية المياه القائمة في كامل العمارة، كما يوجد نظام اتصال داخلي قائم في المدخل.

*Sealed rationale:* Replacement is a work verb so plumbing is existing_only and active, while the intercom is mentioned with no action and is therefore unknown. The unknown disposition drives clarification with reason ambiguous_trade.  (spec 2.3, 2.7)

- **EN** — RC-18, RC-13, RC-05
    - `det` expected [elv,plumbing] got [elv]
    - `act` expected [plumbing] got [elv]
    - `disp` elv: unknown -> existing_only
    - `disp` plumbing: existing_only -> NOT DETECTED
    - `comp` elv.complete_trade_scope: unknown -> existing_only
    - `comp` plumbing.complete_trade_scope: existing_only -> (absent)
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-09b
    - `det` expected [elv,plumbing] got []
    - `act` expected [plumbing] got []
    - `disp` elv: unknown -> NOT DETECTED
    - `disp` plumbing: existing_only -> NOT DETECTED
    - `comp` elv.complete_trade_scope: unknown -> (absent)
    - `comp` plumbing.complete_trade_scope: existing_only -> (absent)
    - `rsn` expected ambiguous_trade got no_trade_detected
    - `blk` expected [clarification_pending] got [clarification_pending,no_active_trade]

---

### G-006 — existing_only (adversarial) · EN/AR parity: no

> EN: There is existing ELV containment installed in the ceiling void by the previous contractor, and no instruction has been issued about it.
> AR: توجد مسارات كابلات قائمة للتيار الخفيف داخل فراغ السقف نفذها المقاول السابق، ولم تصدر أي تعليمات بشأنها.

*Sealed rationale:* An existing installation with no work verb attached is unknown, and the absence of an instruction confirms that no action has been requested. The trade is detected but does not activate.  (spec 2.3, 2.8)

- **EN** — RC-18, RC-04, RC-05
    - `act` expected [] got [elv]
    - `disp` elv: unknown -> included
    - `comp` elv.complete_trade_scope: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending,no_active_trade] got []
- **AR** — RC-18, RC-04, RC-05
    - `act` expected [] got [elv]
    - `disp` elv: unknown -> included
    - `comp` elv.complete_trade_scope: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending,no_active_trade] got []

---

### H-001 — umbrella_exclusion_exception · EN/AR parity: yes

> EN: The MEP works are excluded from our scope, except the electrical works which we will carry out.
> AR: أعمال الميكانيكا والكهرباء والصحية مستثناة من نطاقنا، باستثناء أعمال الكهرباء التي سنقوم بتنفيذها.

*Sealed rationale:* An exception clause attached to an umbrella statement is more specific and defeats the umbrella for its own subject, so electrical is included while the other two core trades stay excluded. The umbrella never reaches fire or ELV.  (spec 2.1, 2.5)

- **EN** — RC-07, RC-06
    - `act` expected [electrical] got []
    - `disp` electrical: included -> excluded
    - `comp` electrical.complete_trade_scope: included -> excluded
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — RC-07, RC-06
    - `act` expected [electrical] got []
    - `disp` electrical: included -> excluded
    - `comp` electrical.complete_trade_scope: included -> excluded
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [] got [clarification_pending,no_active_trade]

---

### H-002 — umbrella_exclusion_exception · EN/AR parity: no

> EN: The MEP package is not with us; the only exception is the fire fighting works, which we will deliver.
> AR: حزمة الميكانيكا والكهرباء والصحية ليست معنا، والاستثناء الوحيد هو أعمال مكافحة الحريق التي سنقوم بتنفيذها.

*Sealed rationale:* Fire enters the case because it is named in an explicit exception attached to the umbrella statement, which is the permitted route. The three core trades are removed with no other party identified and are therefore excluded.  (spec 2.1, 2.3, 2.5)

- **EN** — RC-07, RC-04
    - `disp` electrical: excluded -> included
    - `disp` hvac: excluded -> included
    - `disp` plumbing: excluded -> included
    - `comp` electrical.complete_trade_scope: excluded -> included
    - `comp` hvac.complete_trade_scope: excluded -> included
    - `comp` plumbing.complete_trade_scope: excluded -> included
- **AR** — RC-07, RC-09a, RC-04
    - `act` expected [fire] got [electrical,fire,plumbing]
    - `disp` electrical: excluded -> included
    - `disp` hvac: excluded -> proposed
    - `disp` plumbing: excluded -> included
    - `comp` electrical.complete_trade_scope: excluded -> included
    - `comp` hvac.complete_trade_scope: excluded -> proposed
    - `comp` plumbing.complete_trade_scope: excluded -> included

---

### H-003 — umbrella_exclusion_exception · EN/AR parity: no

> EN: The MEP scope is with the main contractor's in-house teams, except the plumbing works which are ours.
> AR: نطاق أعمال الميكانيكا والكهرباء والصحية مع الفرق الداخلية للمقاول الرئيسي، باستثناء أعمال السباكة التي تخصنا.

*Sealed rationale:* The umbrella removal identifies a responsible party, so the two core trades it still governs are by_others rather than excluded. The exception defeats the umbrella for plumbing only.  (spec 2.3, 2.5)

- **EN** — RC-02, RC-07, RC-04, RC-06
    - `act` expected [plumbing] got []
    - `disp` electrical: by_others -> included
    - `disp` hvac: by_others -> included
    - `disp` plumbing: included -> excluded
    - `comp` electrical.complete_trade_scope: by_others -> included
    - `comp` hvac.complete_trade_scope: by_others -> included
    - `comp` plumbing.complete_trade_scope: included -> excluded
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — RC-02, RC-09a, RC-08, RC-04, RC-06
    - `act` expected [plumbing] got [electrical]
    - `disp` electrical: by_others -> included
    - `disp` hvac: by_others -> proposed
    - `disp` plumbing: included -> conflicted
    - `comp` electrical.complete_trade_scope: by_others -> included
    - `comp` hvac.complete_trade_scope: by_others -> proposed
    - `comp` plumbing.complete_trade_scope: included -> conflicted
    - `clar` expected false got true
    - `rsn` expected null got conflict
    - `blk` expected [] got [clarification_pending,scope_conflict_unresolved]

---

### H-005 — umbrella_exclusion_exception · EN/AR parity: yes

> EN: The MEP works are excluded, except the maintenance of the existing HVAC system which we will continue to provide.
> AR: أعمال الميكانيكا والكهرباء والصحية مستثناة، باستثناء صيانة نظام التكييف القائم التي سنستمر في تقديمها.

*Sealed rationale:* The exception names an existing installation with a maintenance obligation, so HVAC is existing_only and active while the umbrella exclusion still governs the other two core trades. The exception addresses the maintenance stage, which states a split for that trade.  (spec 2.3, 2.4, 2.5)

- **EN** — RC-07, RC-06
    - `act` expected [hvac] got []
    - `disp` hvac: existing_only -> excluded
    - `comp` hvac.maintenance: existing_only -> excluded
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — RC-07, RC-06
    - `act` expected [hvac] got []
    - `disp` hvac: existing_only -> excluded
    - `comp` hvac.maintenance: existing_only -> excluded
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [] got [clarification_pending,no_active_trade]

---

### H-006 — umbrella_exclusion_exception · EN/AR parity: no

> EN: All MEP works are excluded from this offer apart from the electrical works and the fire fighting works.
> AR: جميع أعمال الميكانيكا والكهرباء والصحية مستثناة من هذا العرض عدا أعمال الكهرباء وأعمال مكافحة الحريق.

*Sealed rationale:* Two subjects are carved out of the umbrella by the same exception clause, one core and one non-core, and both are included. ELV is never named and is not reached by the umbrella.  (spec 2.1, 2.5)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-07
    - `act` expected [electrical,fire] got [fire]
    - `disp` electrical: included -> excluded
    - `comp` electrical.complete_trade_scope: included -> excluded

---

### H-007 — umbrella_exclusion_exception (adversarial) · EN/AR parity: yes

> EN: The MEP works in their entirety are excluded from our proposal.
> AR: أعمال الميكانيكا والكهرباء والصحية بكاملها مستثناة من عرضنا.

*Sealed rationale:* A completeness modifier qualifying an umbrella services term widens it across the three core trades only and never reaches fire or ELV. With no exception and no other party identified, all three are excluded and no trade is active.  (spec 2.1, 2.3, 2.9)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### I-001 — umbrella_inclusion_exclusion · EN/AR parity: no

> EN: The complete MEP scope is included, except the plumbing works which are by the developer's own contractor.
> AR: نطاق أعمال الميكانيكا والكهرباء والصحية بالكامل مشمول، باستثناء أعمال السباكة التي ينفذها مقاول المطوّر.

*Sealed rationale:* The modifier qualifies the umbrella services term in the same clause and so widens it across the core three, and the exception then carves plumbing out to an identified party. Fire and ELV are not reached.  (spec 2.1, 2.3, 2.5)

- **EN** — RC-07
    - `disp` plumbing: by_others -> excluded
    - `comp` plumbing.complete_trade_scope: by_others -> excluded
- **AR** — RC-09a, RC-08, RC-06
    - `act` expected [electrical,hvac] got [electrical]
    - `disp` hvac: included -> proposed
    - `disp` plumbing: by_others -> conflicted
    - `comp` hvac.complete_trade_scope: included -> proposed
    - `comp` plumbing.complete_trade_scope: by_others -> conflicted
    - `clar` expected false got true
    - `rsn` expected null got conflict
    - `blk` expected [] got [clarification_pending,scope_conflict_unresolved]

---

### I-002 — umbrella_inclusion_exclusion · EN/AR parity: no

> EN: We will deliver the full MEP services for the tower, but the electrical works are not part of what we will deliver.
> AR: سنقوم بتنفيذ خدمات الميكانيكا والكهرباء والصحية كاملة للبرج، إلا أن أعمال الكهرباء ليست جزءًا مما سننفذه.

*Sealed rationale:* A trade-level statement about a named trade defeats the umbrella for that trade, so electrical is excluded while the other core trades stay included. No other party is identified for the carve-out.  (spec 2.3, 2.5)

- **EN** — RC-07, RC-04
    - `act` expected [hvac,plumbing] got [electrical,hvac,plumbing]
    - `disp` electrical: excluded -> included
    - `comp` electrical.complete_trade_scope: excluded -> included
- **AR** — RC-07, RC-09a, RC-04
    - `act` expected [hvac,plumbing] got [electrical,plumbing]
    - `disp` electrical: excluded -> included
    - `disp` hvac: included -> proposed
    - `comp` electrical.complete_trade_scope: excluded -> included
    - `comp` hvac.complete_trade_scope: included -> proposed

---

### I-003 — umbrella_inclusion_exclusion · EN/AR parity: no

> EN: The MEP scope is ours, except that the HVAC equipment itself will be provided by the client.
> AR: نطاق أعمال الميكانيكا والكهرباء والصحية لنا، باستثناء أن معدات التكييف نفسها سيوفرها العميل.

*Sealed rationale:* The exception concerns the equipment provided by the counterparty, which is client_supplied on the supply stage rather than a removal of the trade. HVAC therefore stays active with one non-contributing component.  (spec 2.3, 2.4, 2.5)

- **EN** — RC-04
    - `act` expected [electrical,hvac,plumbing] got [hvac]
- **AR** — RC-08, RC-06
    - `act` expected [electrical,hvac,plumbing] got [electrical,plumbing]
    - `disp` hvac: included -> conflicted
    - `comp` hvac.supply: client_supplied -> conflicted
    - `clar` expected false got true
    - `rsn` expected null got conflict
    - `blk` expected [] got [clarification_pending,scope_conflict_unresolved]

---

### I-004 — umbrella_inclusion_exclusion · EN/AR parity: no

> EN: Our scope covers the full MEP services and, in addition, the fire fighting works.
> AR: نطاقنا يشمل خدمات الميكانيكا والكهرباء والصحية كاملة، وبالإضافة إلى ذلك أعمال مكافحة الحريق.

*Sealed rationale:* The umbrella covers the three core trades and fire is added by being named directly, so four trades are included. ELV is neither named nor carved out and is not detected.  (spec 2.1, 2.8)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-09a
    - `act` expected [electrical,fire,hvac,plumbing] got [electrical,fire,plumbing]
    - `disp` hvac: included -> proposed
    - `comp` hvac.complete_trade_scope: included -> proposed

---

### I-005 — umbrella_inclusion_exclusion · EN/AR parity: no

> EN: The whole MEP package is with us for this building, except the plumbing works which start in the next phase.
> AR: حزمة الميكانيكا والكهرباء والصحية بأكملها معنا لهذا المبنى، باستثناء أعمال السباكة التي تبدأ في المرحلة القادمة.

*Sealed rationale:* The exception assigns plumbing to a later phase, which is future_phase and does not contribute, while the umbrella keeps the other two core trades included. Future phase is not a clarifying disposition.  (spec 2.2, 2.5)

- **EN** — RC-07
    - `disp` plumbing: future_phase -> excluded
    - `comp` plumbing.complete_trade_scope: future_phase -> excluded
- **AR** — RC-09a, RC-08, RC-06
    - `act` expected [electrical,hvac] got [electrical]
    - `disp` hvac: included -> proposed
    - `disp` plumbing: future_phase -> conflicted
    - `comp` hvac.complete_trade_scope: included -> proposed
    - `comp` plumbing.complete_trade_scope: future_phase -> conflicted
    - `clar` expected false got true
    - `rsn` expected null got conflict
    - `blk` expected [] got [clarification_pending,scope_conflict_unresolved]

---

### I-006 — umbrella_inclusion_exclusion · EN/AR parity: no

> EN: The complete MEP services are included in our price, with the electrical works offered as an option the client may take or leave.
> AR: خدمات الميكانيكا والكهرباء والصحية بالكامل مشمولة في سعرنا، مع عرض أعمال الكهرباء كخيار يمكن للعميل قبوله أو تركه.

*Sealed rationale:* The exception makes electrical an undecided option, which never activates and always clarifies, while the umbrella keeps the other core trades included and active. The open question decides whether a trade is delivered at all.  (spec 2.2, 2.5, 2.9)

- **EN** — RC-05
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-01, RC-09a, RC-04, RC-05
    - `act` expected [hvac,plumbing] got [electrical,plumbing]
    - `disp` electrical: optional -> included
    - `disp` hvac: included -> proposed
    - `comp` electrical.complete_trade_scope: optional -> included
    - `comp` hvac.complete_trade_scope: included -> proposed
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []

---

### I-007 — umbrella_inclusion_exclusion (adversarial) · EN/AR parity: no

> EN: The full MEP scope is ours, except the authority approvals, which the consultant will submit for all three services.
> AR: نطاق الميكانيكا والكهرباء والصحية بالكامل لنا، باستثناء موافقات الجهات التي سيقدمها الاستشاري للخدمات الثلاث.

*Sealed rationale:* The carve-out is a component-level statement and therefore overrides only the approvals stage of each core trade, leaving every other stage to inherit included. All three trades stay active because their trade-level dispositions contribute.  (spec 2.4, 2.5)

- **EN** — RC-04
    - `comp` electrical.authority_approvals: by_others -> included
    - `comp` hvac.authority_approvals: by_others -> included
    - `comp` plumbing.authority_approvals: by_others -> included
- **AR** — RC-09a, RC-04
    - `act` expected [electrical,hvac,plumbing] got [electrical,plumbing]
    - `disp` hvac: included -> proposed
    - `comp` electrical.authority_approvals: by_others -> included
    - `comp` hvac.authority_approvals: by_others -> proposed
    - `comp` plumbing.authority_approvals: by_others -> included

---

### J-001 — component_split · EN/AR parity: yes

> EN: The HVAC design is by the appointed consultant; we take the works forward from the shop drawings onward.
> AR: تصميم أنظمة التكييف يقوم به الاستشاري المعيّن، ونتولى نحن الأعمال بدءًا من المخططات التنفيذية.

*Sealed rationale:* A component-level statement assigns the design stage to an identified party, so that stage is by_others and every unstated stage inherits included. The trade remains active.  (spec 2.4, 2.5)

- **EN** — RC-04
    - `comp` hvac.design: by_others -> included
- **AR** — RC-04
    - `comp` hvac.design: by_others -> included

---

### J-002 — component_split · EN/AR parity: no

> EN: For the electrical works we will design, supply and install. Testing and commissioning are not part of our scope.
> AR: بالنسبة لأعمال الكهرباء سنقوم بالتصميم والتوريد والتركيب، أما الاختبار والتشغيل والتسليم فليسا ضمن نطاقنا.

*Sealed rationale:* Five lifecycle stages are addressed explicitly, so five component rows are stated and complete_trade_scope must not appear. The trade contributes and not every one of the nine components is stated, so it stays active.  (spec 2.4)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-04
    - `comp` electrical.commissioning: excluded -> included
    - `comp` electrical.testing: excluded -> included

---

### J-005 — component_split · EN/AR parity: yes

> EN: The fire fighting installation is in this package; maintenance starts only after the defects liability period under a later contract.
> AR: تركيب أنظمة مكافحة الحريق ضمن هذه الحزمة، ولا تبدأ الصيانة إلا بعد انتهاء فترة الضمان بموجب عقد لاحق.

*Sealed rationale:* Maintenance is placed under a later contract, so that component carries future_phase while installation stays included. Future phase does not clarify, so clarification is not required.  (spec 2.2, 2.4)

- **EN** — RC-04
    - `comp` fire.maintenance: future_phase -> included
- **AR** — RC-04
    - `comp` fire.maintenance: future_phase -> included

---

### J-007 — component_split · EN/AR parity: no

> EN: The electrical works are awarded to us. The documents do not state whether the detailed design is included in the award.
> AR: أعمال الكهرباء مُرسّاة علينا. ولم توضّح المستندات ما إذا كان التصميم التفصيلي مشمولًا في الترسية.

*Sealed rationale:* The design stage is named but its disposition cannot be determined from the text, which is unknown at component level and clarifies on its own. The trade itself is clean and active, and the answer changes the quoted component scope.  (spec 2.2, 2.4, 2.7)

- **EN** — RC-04, RC-05
    - `comp` electrical.design: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-04, RC-05
    - `comp` electrical.design: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending] got []

---

### J-008 — component_split · EN/AR parity: no

> EN: The existing drainage network is to be re-routed. Whether the re-routing design sits with us or with the consultant is not stated anywhere.
> AR: يجب إعادة توجيه شبكة الصرف القائمة. ولم يُذكر في أي موضع ما إذا كان تصميم إعادة التوجيه علينا أم على الاستشاري.

*Sealed rationale:* Re-routing an existing network is a work verb, so the trade is existing_only and active, while the design stage is named without a determinable disposition and is unknown. The component-level unknown drives clarification with reason ambiguous_trade.  (spec 2.3, 2.4, 2.7)

- **EN** — RC-18, RC-05
    - `comp` plumbing.design: unknown -> existing_only
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-01, RC-04, RC-05
    - `disp` plumbing: existing_only -> included
    - `comp` plumbing.design: unknown -> included
    - `comp` plumbing.installation: existing_only -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending] got []

---

### J-009 — component_split · EN/AR parity: yes

> EN: The ELV installation is included. The system design is offered as an option at your discretion.
> AR: تركيب أنظمة التيار الخفيف مشمول. وتصميم الأنظمة معروض كبند اختياري حسب رغبتكم.

*Sealed rationale:* The design stage carries an undecided option while the installation stage is included, so the trade is active and clarification is still required. The reason is optional_pending_decision because no earlier trigger in the precedence order applies.  (spec 2.4, 2.7)

- **EN** — RC-05
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-05
    - `clar` expected true got false
    - `rsn` expected optional_pending_decision got null
    - `blk` expected [clarification_pending] got []

---

### J-010 — component_split · EN/AR parity: yes

> EN: We will supply and install the fire fighting system; commissioning will be carried out by the approved third-party inspector.
> AR: سنقوم بتوريد وتركيب نظام مكافحة الحريق، على أن يتولى المفتش المعتمد من طرف ثالث أعمال التشغيل والتسليم.

*Sealed rationale:* The commissioning stage is assigned to an identified third party, so it is by_others while supply and installation stay included. The trade contributes and is active.  (spec 2.3, 2.4)

- **EN** — RC-04
    - `comp` fire.commissioning: by_others -> included
- **AR** — RC-04
    - `comp` fire.commissioning: by_others -> included

---

### J-012 — component_split · EN/AR parity: no

> EN: For the electrical works we supply the materials and coordinate on site; the DEWA submission is handled by the client's consultant.
> AR: بالنسبة لأعمال الكهرباء نقوم بتوريد المواد والتنسيق في الموقع، أما تقديم المعاملة إلى هيئة كهرباء ومياه دبي فيتولاه استشاري العميل.

*Sealed rationale:* The utility submission is a component-level statement assigning the approvals stage to an identified party, so it is by_others. Supply and coordination are ours and the remaining stages inherit included.  (spec 2.3, 2.4, 2.5)

- **EN** — RC-04
    - `comp` electrical.authority_approvals: by_others -> included
- **AR** — RC-04
    - `comp` electrical.authority_approvals: by_others -> included

---

### J-013 — component_split · EN/AR parity: yes

> EN: The HVAC works are with us. The enquiry does not say whether commissioning is inside this package or handled separately.
> AR: أعمال التكييف معنا. ولا يوضح طلب العرض ما إذا كان التشغيل والتسليم ضمن هذه الحزمة أم يُعالج بشكل منفصل.

*Sealed rationale:* The commissioning stage is named but undeterminable, which is unknown at component level and requires clarification even though the trade is clean and active. Resolving it changes what a supplier would be told to quote.  (spec 2.2, 2.4, 2.9)

- **EN** — RC-04, RC-05
    - `comp` hvac.commissioning: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-04, RC-05
    - `comp` hvac.commissioning: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending] got []

---

### J-014 — component_split · EN/AR parity: no

> EN: The plumbing works are ours, though the documents do not say whether the authority approvals are included. The ELV package is separately offered as an option the client may still decline.
> AR: أعمال السباكة تخصنا، غير أن المستندات لا توضح ما إذا كانت موافقات الجهات مشمولة. أما حزمة التيار الخفيف فمعروضة بشكل منفصل كخيار يمكن للعميل رفضه.

*Sealed rationale:* Two clarifying dispositions co-occur at different levels, and the precedence order is computed over trade and component dispositions together rather than by level, so the component-level unknown outranks the trade-level option. The reason is therefore ambiguous_trade and plumbing stays active.  (spec 2.4, 2.7)

- **EN** — RC-04, RC-05
    - `comp` plumbing.authority_approvals: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-01, RC-04, RC-05
    - `act` expected [plumbing] got [elv,plumbing]
    - `disp` elv: optional -> included
    - `comp` elv.complete_trade_scope: optional -> included
    - `comp` plumbing.authority_approvals: unknown -> included
    - `clar` expected true got false
    - `rsn` expected ambiguous_trade got null
    - `blk` expected [clarification_pending] got []

---

### K-001 — equal_specificity_conflict · EN/AR parity: no

> EN: Clause 3 of the enquiry states that the electrical works are included in our scope, and clause 9 states that the electrical works are not part of our scope.
> AR: ينص البند الثالث من طلب العرض على أن أعمال الكهرباء ضمن نطاقنا، بينما ينص البند التاسع على أن أعمال الكهرباء ليست جزءًا من نطاقنا.

*Sealed rationale:* Two trade-level statements about the same named trade cannot both hold, and neither is more specific, so the disposition is conflicted and no positional tie-break may be applied. The conflict raises its own blocker and clarification with reason conflict.  (spec 2.5, 2.7, 2.9)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-08, RC-05
    - `act` expected [] got [electrical]
    - `disp` electrical: conflicted -> included
    - `comp` electrical.complete_trade_scope: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,no_active_trade,scope_conflict_unresolved] got []

---

### K-002 — equal_specificity_conflict · EN/AR parity: yes

> EN: The covering letter says the plumbing works are ours, while the scope matrix assigns the plumbing works to the main contractor.
> AR: يذكر الخطاب المرفق أن أعمال السباكة تخصنا، بينما يسند جدول توزيع النطاق أعمال السباكة إلى المقاول الرئيسي.

*Sealed rationale:* An inclusion and an assignment to another party sit at the same trade level and contradict each other, which is conflicted rather than a choice between the two readings. The trade is detected and does not activate.  (spec 2.5, 2.8)

- **EN** — RC-08, RC-05
    - `act` expected [] got [plumbing]
    - `disp` plumbing: conflicted -> included
    - `comp` plumbing.complete_trade_scope: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,no_active_trade,scope_conflict_unresolved] got []
- **AR** — RC-08, RC-05
    - `act` expected [] got [plumbing]
    - `disp` plumbing: conflicted -> included
    - `comp` plumbing.complete_trade_scope: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,no_active_trade,scope_conflict_unresolved] got []

---

### K-003 — equal_specificity_conflict · EN/AR parity: yes

> EN: The electrical works are ours. For HVAC the enquiry states in one place that it is included and in another that it is excluded.
> AR: أعمال الكهرباء تخصنا. أما التكييف فيذكر طلب العرض في موضع أنه مشمول وفي موضع آخر أنه مستثنى.

*Sealed rationale:* The contradiction sits on HVAC at trade level and produces conflicted, while electrical is unaffected and remains active. The conflict blocker is raised even though a trade is active.  (spec 2.5, 2.9)

- **EN** — RC-08, RC-05
    - `disp` hvac: conflicted -> excluded
    - `comp` hvac.complete_trade_scope: conflicted -> excluded
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []
- **AR** — RC-08, RC-05
    - `disp` hvac: conflicted -> excluded
    - `comp` hvac.complete_trade_scope: conflicted -> excluded
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []

---

### K-004 — equal_specificity_conflict · EN/AR parity: no

> EN: The award letter states that the MEP works are in our scope; the same letter later states that the MEP works are not in our scope.
> AR: يذكر خطاب الترسية أن أعمال الميكانيكا والكهرباء والصحية ضمن نطاقنا، ثم يذكر الخطاب نفسه لاحقًا أنها ليست ضمن نطاقنا.

*Sealed rationale:* Two umbrella statements at the same level contradict each other, so all three core trades are conflicted and none activates. The umbrella never reaches fire or ELV even when contradicted.  (spec 2.1, 2.5)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-08, RC-05
    - `act` expected [] got [electrical,plumbing]
    - `disp` electrical: conflicted -> included
    - `disp` hvac: conflicted -> proposed
    - `disp` plumbing: conflicted -> included
    - `comp` electrical.complete_trade_scope: conflicted -> included
    - `comp` hvac.complete_trade_scope: conflicted -> proposed
    - `comp` plumbing.complete_trade_scope: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,no_active_trade,scope_conflict_unresolved] got []

---

### K-005 — equal_specificity_conflict · EN/AR parity: yes

> EN: The plumbing works are ours. The specification says the authority approvals for the plumbing are in our scope; the scope matrix says the same approvals are excluded.
> AR: أعمال السباكة تخصنا. تنص المواصفات على أن موافقات الجهات الخاصة بالسباكة ضمن نطاقنا، بينما يذكر جدول النطاق أن الموافقات نفسها مستثناة.

*Sealed rationale:* Two component-level statements about the same stage of the same trade contradict each other, so that component is conflicted while the trade stays clean and active. A conflict at component level raises the same blocker and the same clarification reason as one at trade level.  (spec 2.5, 2.7, 2.9)

- **EN** — RC-08, RC-05
    - `comp` plumbing.authority_approvals: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []
- **AR** — RC-08, RC-05
    - `comp` plumbing.authority_approvals: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []

---

### K-006 — equal_specificity_conflict · EN/AR parity: yes

> EN: The HVAC works are awarded to us. One clause makes site coordination our responsibility and another clause states that site coordination is not ours.
> AR: أعمال التكييف مُرسّاة علينا. أحد البنود يجعل التنسيق في الموقع من مسؤوليتنا وبند آخر ينص على أن التنسيق في الموقع ليس من مسؤوليتنا.

*Sealed rationale:* The contradiction sits entirely on the coordination stage at equal specificity, so that component is conflicted and the trade remains active. The unresolved contradiction still makes the supplier brief incomplete.  (spec 2.5, 2.9)

- **EN** — RC-08, RC-05
    - `comp` hvac.coordination: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []
- **AR** — RC-08, RC-05
    - `comp` hvac.coordination: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []

---

### K-007 — equal_specificity_conflict · EN/AR parity: yes

> EN: The fire fighting works are in our scope. The tender says maintenance is included for one year and the annexure says maintenance is not included at all.
> AR: أعمال مكافحة الحريق ضمن نطاقنا. تذكر المناقصة أن الصيانة مشمولة لمدة سنة، بينما يذكر الملحق أن الصيانة غير مشمولة إطلاقًا.

*Sealed rationale:* Both statements address the maintenance stage of a named trade at the same specificity and cannot both hold, so the component is conflicted. Fire is active while the conflict blocker and the conflict reason are both raised.  (spec 2.5, 2.7)

- **EN** — RC-08, RC-05
    - `comp` fire.maintenance: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []
- **AR** — RC-08, RC-05
    - `comp` fire.maintenance: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []

---

### K-008 — equal_specificity_conflict · EN/AR parity: no

> EN: The HVAC works are with us, but one clause makes the testing our responsibility and another states that the testing is not ours. The enquiry also mentions an existing intercom system with no instruction attached to it.
> AR: أعمال التكييف معنا، لكن أحد البنود يجعل الاختبار من مسؤوليتنا وبندًا آخر ينص على أن الاختبار ليس من مسؤوليتنا. كما يشير طلب العرض إلى نظام اتصال داخلي قائم دون أي تعليمات بشأنه.

*Sealed rationale:* A conflict sitting on a component outranks an unknown sitting on a trade, because the precedence order is applied across both levels at once, so the reason is conflict and the conflict blocker is raised. HVAC remains active while the contradiction inside its scope stays unresolved.  (spec 2.5, 2.7, 2.9)

- **EN** — RC-18, RC-08, RC-05
    - `act` expected [hvac] got [elv,hvac]
    - `disp` elv: unknown -> existing_only
    - `comp` elv.complete_trade_scope: unknown -> existing_only
    - `comp` hvac.testing: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []
- **AR** — RC-09b, RC-08, RC-05
    - `det` expected [elv,hvac] got [hvac]
    - `disp` elv: unknown -> NOT DETECTED
    - `comp` elv.complete_trade_scope: unknown -> (absent)
    - `comp` hvac.testing: conflicted -> included
    - `clar` expected true got false
    - `rsn` expected conflict got null
    - `blk` expected [clarification_pending,scope_conflict_unresolved] got []

---

### L-003 — clause_boundary (adversarial) · EN/AR parity: no

> EN: The entire MEP scope is ours on this tower.
> AR: نطاق الميكانيكا والكهرباء والصحية بأكمله لنا في هذا البرج.

*Sealed rationale:* The modifier qualifies an umbrella services term within the same clause and therefore widens it, but widening an umbrella still reaches the three core trades only. Fire and ELV are not named and must not be detected.  (spec 2.1, 2.3, 2.6)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-09a
    - `act` expected [electrical,hvac,plumbing] got [electrical,plumbing]
    - `disp` hvac: included -> proposed
    - `comp` hvac.complete_trade_scope: included -> proposed

---

### L-007 — clause_boundary · EN/AR parity: yes

> EN: Kindly quote the HVAC, electrical and plumbing works in full.
> AR: نرجو تسعير أعمال التكييف والكهرباء والسباكة بالكامل.

*Sealed rationale:* All three trades are named and included, but the trailing modifier sits inside one clause with a list and may bind to the final item or to the whole list. That binding is genuinely ambiguous, which requires clarification with reason ambiguous_scope_binding.  (spec 2.6, 2.7)

- **EN** — RC-11
    - `clar` expected true got false
    - `rsn` expected ambiguous_scope_binding got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-11
    - `clar` expected true got false
    - `rsn` expected ambiguous_scope_binding got null
    - `blk` expected [clarification_pending] got []

---

### M-005 — mixed_language · EN/AR parity: no

> EN: The وحدات المناولة will be supplied by the client; we will carry out the التركيب only.
> AR: سيتم توريد الـ FCUs و الـ AHUs من قبل العميل، وسنقوم نحن بالـ installation فقط.

*Sealed rationale:* The borrowed equipment terms are pluralised in the host language and still identify the HVAC trade, whose supply stage is client_supplied and whose installation stage is included. The trade contributes and stays active.  (spec 2.3, 2.4)

- **EN** — RC-14
    - `det` expected [hvac] got []
    - `act` expected [hvac] got []
    - `disp` hvac: included -> NOT DETECTED
    - `comp` hvac.installation: included -> (absent)
    - `comp` hvac.supply: client_supplied -> (absent)
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — matched the sealed expectation in full.

---

### N-001 — gulf_phrasing · EN/AR parity: no

> EN: Kindly revert with your best offer for the HVAC works for a villa G+1 in Al Warqa, including the municipality shop drawing submission.
> AR: نرجو الرد بأفضل عرض لأعمال التكييف لفيلا أرضي وأول في الورقاء، بما في ذلك تقديم المخططات التنفيذية إلى البلدية.

*Sealed rationale:* Local building-typology and correspondence register do not change the reading, so HVAC is included and the municipality submission states the approvals stage. That split replaces the complete_trade_scope row.  (spec 2.4)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-01
    - `det` expected [hvac] got [electrical,hvac]
    - `act` expected [hvac] got [electrical,hvac]
    - `disp` electrical: (not expected) -> included

---

### N-003 — gulf_phrasing · EN/AR parity: yes

> EN: The labour accommodation in Al Quoz needs the existing water tanks and pumps serviced before the summer.
> AR: سكن العمال في القوز يحتاج إلى صيانة خزانات المياه والمضخات القائمة قبل الصيف.

*Sealed rationale:* An existing installation named with a servicing obligation is existing_only and the trade is active because there is work to do. The text addresses the maintenance stage only.  (spec 2.3, 2.4)

- **EN** — RC-13, RC-06
    - `det` expected [plumbing] got []
    - `act` expected [plumbing] got []
    - `disp` plumbing: existing_only -> NOT DETECTED
    - `comp` plumbing.maintenance: existing_only -> (absent)
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — RC-09b, RC-06
    - `det` expected [plumbing] got []
    - `act` expected [plumbing] got []
    - `disp` plumbing: existing_only -> NOT DETECTED
    - `comp` plumbing.maintenance: existing_only -> (absent)
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [] got [clarification_pending,no_active_trade]

---

### N-004 — gulf_phrasing · EN/AR parity: no

> EN: Kindly advise your price for the fire fighting works and confirm you can obtain the Civil Defence no-objection certificate.
> AR: نرجو إفادتنا بسعركم لأعمال مكافحة الحريق وتأكيد قدرتكم على استخراج شهادة عدم ممانعة من الدفاع المدني.

*Sealed rationale:* Fire is named directly and the statutory certificate addresses the approvals stage of that trade. Both are in scope, so the trade is included and active.  (spec 2.1, 2.4)

- **EN** — RC-12, RC-06
    - `act` expected [fire] got []
    - `disp` fire: included -> excluded
    - `comp` fire.authority_approvals: included -> excluded
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — matched the sealed expectation in full.

---

### O-002 — arabic_morphology · EN/AR parity: no

> EN: For the villa we need the plumbing works, and for the electrical works a separate price.
> AR: للفيلا نحتاج أعمال السباكة، وللكهرباء سعر منفصل.

*Sealed rationale:* Both trade terms are carried by attached prepositional proclitics and both are requested, so both are included and active. Requesting a separate price is not a split across lifecycle stages.  (spec 2.2, 2.4)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-09b
    - `det` expected [electrical,plumbing] got [plumbing]
    - `act` expected [electrical,plumbing] got [plumbing]
    - `disp` electrical: included -> NOT DETECTED
    - `comp` electrical.complete_trade_scope: included -> (absent)

---

### O-003 — arabic_morphology · EN/AR parity: no

> EN: Kindly price the supply and installation of the air conditioners for the three apartments.
> AR: نرجو تسعير توريد وتركيب المكيفات للشقق الثلاث.

*Sealed rationale:* A broken plural of the equipment term identifies the HVAC trade, and the text addresses two lifecycle stages explicitly. Both stated components carry the trade disposition.  (spec 2.1, 2.4)

- **EN** — RC-13, RC-06
    - `det` expected [hvac] got []
    - `act` expected [hvac] got []
    - `disp` hvac: included -> NOT DETECTED
    - `comp` hvac.installation: included -> (absent)
    - `comp` hvac.supply: included -> (absent)
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — matched the sealed expectation in full.

---

### O-004 — arabic_morphology · EN/AR parity: yes

> EN: The electrical works for both buildings are excluded from our scope.
> AR: أعمال الكهرباء للمبنيين مستثناة من نطاقنا.

*Sealed rationale:* The dual form is a morphological variant of the building noun and does not affect the trade reading, which is a removal with no other party identified. No trade is active.  (spec 2.3, 2.9)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### O-005 — arabic_morphology · EN/AR parity: yes

> EN: Maintenance of the existing fire alarm system is required for one year.
> AR: مطلوب صيانه نظام إنذار الحريق القائم لمدة سنه واحده.

*Sealed rationale:* An existing installation with a maintenance obligation is existing_only and contributes, and the ha spelling of ta marbuta is a realistic variant that changes nothing. The text addresses the maintenance stage only.  (spec 2.3, 2.4)

- **EN** — RC-01
    - `disp` fire: existing_only -> included
- **AR** — RC-01
    - `disp` fire: existing_only -> included

---

### O-006 — arabic_morphology · EN/AR parity: no

> EN: The fire extinguishing works for the kitchen hood are in our scope.
> AR: اعمال الاطفاء لمظلة المطبخ ضمن نطاقنا.

*Sealed rationale:* The hamza is dropped from both the leading noun and the trade term, which is a common tender spelling and leaves the trade reading intact. Fire is named and included.  (spec 2.1, 2.2)

- **EN** — RC-13, RC-06
    - `det` expected [fire] got []
    - `act` expected [fire] got []
    - `disp` fire: included -> NOT DETECTED
    - `comp` fire.complete_trade_scope: included -> (absent)
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [] got [clarification_pending,no_active_trade]
- **AR** — matched the sealed expectation in full.

---

### O-007 — arabic_morphology · EN/AR parity: yes

> EN: The ELV works for the building are with another contractor.
> AR: أعمال التيار الخفيف للمبني مع مقاول آخر.

*Sealed rationale:* An identified other contractor makes the disposition by_others rather than excluded, and the yaa spelling of the final alef maqsura does not affect it. The trade is detected but does not activate.  (spec 2.3, 2.8)

- **EN** — RC-02, RC-04
    - `act` expected [] got [elv]
    - `disp` elv: by_others -> included
    - `comp` elv.complete_trade_scope: by_others -> included
    - `blk` expected [no_active_trade] got []
- **AR** — RC-02, RC-04
    - `act` expected [] got [elv]
    - `disp` elv: by_others -> included
    - `comp` elv.complete_trade_scope: by_others -> included
    - `blk` expected [no_active_trade] got []

---

### P-001 — ambiguous_non_trade (adversarial) · EN/AR parity: no

> EN: Kindly address the purchase order to Gulf MEP Contracting LLC, which is our registered trade name.
> AR: نرجو إصدار أمر الشراء باسم شركة الخليج إم إي بي للمقاولات ذ.م.م، وهو اسمنا التجاري المسجل.

*Sealed rationale:* An umbrella services abbreviation used inside an organisation name describes the party, not a scope, so it activates nothing and detects nothing. The message is an administrative instruction rather than a scope enquiry, so no clarification is required.  (spec 2.7, 2.8)

- **EN** — RC-01, RC-06
    - `det` expected [] got [electrical,hvac,plumbing]
    - `disp` electrical: (not expected) -> included
    - `disp` hvac: (not expected) -> included
    - `disp` plumbing: (not expected) -> included
    - `clar` expected false got true
    - `rsn` expected null got ambiguous_scope_binding
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### P-002 — ambiguous_non_trade (adversarial) · EN/AR parity: yes

> EN: We are recruiting an electrical engineer for our estimation department; please share any CVs you may have.
> AR: نقوم بتوظيف مهندس كهرباء لقسم التسعير لدينا، ونرجو مشاركة أي سير ذاتية متاحة.

*Sealed rationale:* An engineering discipline name used to describe a staff role is not evidence of a scope of works, so no trade is detected. The message is not a scope enquiry, so clarification is not required.  (spec 2.7, 2.8)

- **EN** — RC-01
    - `det` expected [] got [electrical]
    - `act` expected [] got [electrical]
    - `disp` electrical: (not expected) -> included
    - `blk` expected [no_active_trade] got []
- **AR** — RC-01
    - `det` expected [] got [electrical]
    - `act` expected [] got [electrical]
    - `disp` electrical: (not expected) -> included
    - `blk` expected [no_active_trade] got []

---

### P-003 — ambiguous_non_trade (adversarial) · EN/AR parity: yes

> EN: Please transfer the retention amount to our A/C number ending 4471 and send us the transfer advice.
> AR: نرجو تحويل مبلغ الاحتجاز إلى حسابنا (A/C) المنتهي بـ 4471 وإرسال إشعار التحويل.

*Sealed rationale:* The short form here carries its non-trade financial sense, which the surrounding text disambiguates completely, so it confirms no trade and nothing is detected. A payment instruction is not a scope enquiry.  (spec 2.3, 2.7)

- **EN** — RC-01, RC-06
    - `det` expected [] got [hvac]
    - `disp` hvac: (not expected) -> proposed
    - `clar` expected false got true
    - `rsn` expected null got unconfirmed_proposal
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-09a, RC-06
    - `det` expected [] got [hvac]
    - `disp` hvac: (not expected) -> proposed
    - `clar` expected false got true
    - `rsn` expected null got unconfirmed_proposal
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### P-004 — ambiguous_non_trade (adversarial) · EN/AR parity: no

> EN: The payment should be released to MEPCO Trading, which is our material supplier for this project.
> AR: يجب صرف الدفعة لشركة MEPCO للتجارة، وهي مورّد المواد لدينا في هذا المشروع.

*Sealed rationale:* The umbrella abbreviation occurs only as a substring of a longer supplier name and therefore belongs to that name with no independent force. Nothing is detected and the message is not a scope enquiry.  (spec 2.3, 2.8)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-01
    - `det` expected [] got [plumbing]
    - `act` expected [] got [plumbing]
    - `disp` plumbing: (not expected) -> included
    - `blk` expected [no_active_trade] got []

---

### P-005 — ambiguous_non_trade (adversarial) · EN/AR parity: yes

> EN: Kindly send the complete set of catalogues and material submittals for our records.
> AR: نرجو إرسال المجموعة الكاملة من الكتالوجات ومستندات اعتماد المواد لسجلاتنا.

*Sealed rationale:* A completeness modifier attached to a document set rather than to a trade or umbrella services term carries no trade meaning and must not activate anything. This holds in both languages independently.  (spec 2.3, 2.6)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### P-006 — ambiguous_non_trade (adversarial) · EN/AR parity: yes

> EN: The documents package will be couriered to your office tomorrow morning.
> AR: سيتم إرسال حزمة المستندات إلى مكتبكم صباح الغد بالبريد السريع.

*Sealed rationale:* A grouping noun applied to documents is not an umbrella services term and gives no trade evidence, so nothing is detected. The message is logistical rather than a scope enquiry.  (spec 2.3, 2.7)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### P-007 — ambiguous_non_trade · EN/AR parity: yes

> EN: Kindly confirm the FA position for this project before tomorrow's meeting.
> AR: نرجو تأكيد وضع الـ FA لهذا المشروع قبل اجتماع الغد.

*Sealed rationale:* The short form is ambiguous between a trade sense and a commercial sense and the surrounding text does not disambiguate it, so it cannot confirm the trade and the disposition is unknown. Clarification is required with reason ambiguous_trade.  (spec 2.3, 2.7)

- **EN** — RC-15
    - `det` expected [fire] got []
    - `disp` fire: unknown -> NOT DETECTED
    - `comp` fire.complete_trade_scope: unknown -> (absent)
    - `rsn` expected ambiguous_trade got no_trade_detected
- **AR** — RC-15
    - `det` expected [fire] got []
    - `disp` fire: unknown -> NOT DETECTED
    - `comp` fire.complete_trade_scope: unknown -> (absent)
    - `rsn` expected ambiguous_trade got no_trade_detected

---

### P-008 — ambiguous_non_trade · EN/AR parity: yes

> EN: Please advise your rate for the AC panels on the second floor.
> AR: نرجو إفادتنا بسعركم للوحات الـ AC في الطابق الثاني.

*Sealed rationale:* The short form is ambiguous between two trades and the surrounding text does not resolve which is meant, so neither trade is confirmed and both candidates carry unknown. Neither activates and clarification is required.  (spec 2.3, 2.7)

- **EN** — RC-15
    - `det` expected [electrical,hvac] got [hvac]
    - `disp` electrical: unknown -> NOT DETECTED
    - `disp` hvac: unknown -> proposed
    - `comp` electrical.complete_trade_scope: unknown -> (absent)
    - `comp` hvac.complete_trade_scope: unknown -> proposed
    - `rsn` expected ambiguous_trade got unconfirmed_proposal
- **AR** — RC-15
    - `det` expected [electrical,hvac] got [hvac]
    - `disp` electrical: unknown -> NOT DETECTED
    - `disp` hvac: unknown -> proposed
    - `comp` electrical.complete_trade_scope: unknown -> (absent)
    - `comp` hvac.complete_trade_scope: unknown -> proposed
    - `rsn` expected ambiguous_trade got unconfirmed_proposal

---

### P-009 — ambiguous_non_trade (adversarial) · EN/AR parity: yes

> EN: The ELV contractor will pull his own cables; nothing further is required from us on that package.
> AR: سيقوم مقاول الـ ELV بسحب كابلاته بنفسه، ولا يُطلب منا شيء إضافي في تلك الحزمة.

*Sealed rationale:* An identified other contractor holds the named trade, which is by_others and does not activate. The shorter abbreviation appears only as a substring of the longer trade abbreviation and therefore has no independent force.  (spec 2.3, 2.8)

- **EN** — RC-02, RC-04
    - `act` expected [] got [elv]
    - `disp` elv: by_others -> included
    - `comp` elv.complete_trade_scope: by_others -> included
    - `blk` expected [no_active_trade] got []
- **AR** — RC-02, RC-04
    - `act` expected [] got [elv]
    - `disp` elv: by_others -> included
    - `comp` elv.complete_trade_scope: by_others -> included
    - `blk` expected [no_active_trade] got []

---

### Q-001 — document_proposed (adversarial) · EN/AR parity: no

> EN: Kindly review the attached and let us know your position.
> AR: نرجو مراجعة المرفق وإفادتنا بموقفكم.

*Sealed rationale:* The only evidence for the trade is an attached document, so the disposition is proposed and never included, and it always carries clarification. Attachments never activate, so no trade is active.  (spec 2.8, 2.9)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-09b
    - `det` expected [hvac] got []
    - `disp` hvac: proposed -> NOT DETECTED
    - `comp` hvac.complete_trade_scope: proposed -> (absent)
    - `rsn` expected unconfirmed_proposal got no_trade_detected

---

### Q-002 — document_proposed · EN/AR parity: no

> EN: Please see the attached and advise.
> AR: نرجو الاطلاع علي المرفق والإفادة.

*Sealed rationale:* Attachment evidence alone yields proposed for the trade it evidences, which does not contribute and requires clarification. The covering text names no trade at all.  (spec 2.2, 2.8)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-09b
    - `det` expected [electrical] got []
    - `disp` electrical: proposed -> NOT DETECTED
    - `comp` electrical.complete_trade_scope: proposed -> (absent)
    - `rsn` expected unconfirmed_proposal got no_trade_detected

---

### Q-003 — document_proposed · EN/AR parity: no

> EN: We confirm the HVAC works are with us. The attached drawing set is shared for information.
> AR: نؤكد أن أعمال التكييف لدينا. وطقم المخططات المرفق مُرسل للاطلاع.

*Sealed rationale:* HVAC has text evidence and is included, while the second trade appears only in the attachment and is therefore proposed. The proposed disposition drives clarification with reason unconfirmed_proposal.  (spec 2.7, 2.8)

- **EN** — RC-01, RC-05
    - `det` expected [fire,hvac] got [fire,hvac,plumbing]
    - `disp` plumbing: (not expected) -> proposed
    - `clar` expected true got false
    - `rsn` expected unconfirmed_proposal got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-09a, RC-09b, RC-05
    - `det` expected [fire,hvac] got [hvac,plumbing]
    - `disp` fire: proposed -> NOT DETECTED
    - `disp` plumbing: (not expected) -> proposed
    - `comp` fire.complete_trade_scope: proposed -> (absent)
    - `clar` expected true got false
    - `rsn` expected unconfirmed_proposal got null
    - `blk` expected [clarification_pending] got []

---

### Q-004 — document_proposed · EN/AR parity: no

> EN: The fire fighting works are in our scope. The attached method statement also covers third-party testing, which has not been confirmed with us.
> AR: أعمال مكافحة الحريق ضمن نطاقنا. ويشمل بيان الطريقة المرفق أيضًا اختبارات الطرف الثالث التي لم تُؤكد معنا.

*Sealed rationale:* The trade is named in the text and included, while a stage that appears only in the attachment and is unconfirmed is proposed at component level. A clarifying component disposition demands clarification even though the trade is active and clean.  (spec 2.4, 2.7, 2.8)

- **EN** — RC-04, RC-05
    - `comp` fire.testing: proposed -> included
    - `clar` expected true got false
    - `rsn` expected unconfirmed_proposal got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-04, RC-05
    - `comp` fire.testing: proposed -> included
    - `clar` expected true got false
    - `rsn` expected unconfirmed_proposal got null
    - `blk` expected [clarification_pending] got []

---

### Q-005 — document_proposed (adversarial) · EN/AR parity: no

> EN: Attached is the pack we received from the consultant. Kindly advise.
> AR: مرفق الملف الذي استلمناه من الاستشاري. نرجو الإفادة.

*Sealed rationale:* The trade is evidenced only by the attachment, so it is proposed and does not activate, and clarification is always carried. No other trade has evidence in either the text or the attachment.  (spec 2.8, 2.9)

- **EN** — matched the sealed expectation in full.
- **AR** — RC-09b
    - `det` expected [elv] got []
    - `disp` elv: proposed -> NOT DETECTED
    - `comp` elv.complete_trade_scope: proposed -> (absent)
    - `rsn` expected unconfirmed_proposal got no_trade_detected

---

### Q-006 — document_proposed · EN/AR parity: yes

> EN: Plumbing is confirmed with us; the attached schedule is sent for your information only.
> AR: أعمال السباكة مؤكدة معنا؛ والجدول المرفق مُرسل للاطلاع فقط.

*Sealed rationale:* Text evidence yields a contributing disposition for the named trade, while the attachment-only trade is proposed. The proposed trade is detected but never activated by an attachment.  (spec 2.8)

- **EN** — RC-13, RC-05
    - `det` expected [elv,plumbing] got [plumbing]
    - `disp` elv: proposed -> NOT DETECTED
    - `comp` elv.complete_trade_scope: proposed -> (absent)
    - `clar` expected true got false
    - `rsn` expected unconfirmed_proposal got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-09b, RC-05
    - `det` expected [elv,plumbing] got [plumbing]
    - `disp` elv: proposed -> NOT DETECTED
    - `comp` elv.complete_trade_scope: proposed -> (absent)
    - `clar` expected true got false
    - `rsn` expected unconfirmed_proposal got null
    - `blk` expected [clarification_pending] got []

---

### Q-007 — document_proposed · EN/AR parity: yes

> EN: The electrical installation is with us. The attached consultant note also lists the detailed design, which we have not been asked to price.
> AR: التركيبات الكهربائية لدينا. كما تُدرج مذكرة الاستشاري المرفقة التصميم التفصيلي الذي لم يُطلب منا تسعيره.

*Sealed rationale:* A stage inferred from an attachment and not confirmed by the customer is proposed at component level, while the trade itself has text evidence and stays active. The unresolved proposal changes the quoted component scope.  (spec 2.4, 2.8, 2.9)

- **EN** — RC-04, RC-05
    - `comp` electrical.design: proposed -> included
    - `clar` expected true got false
    - `rsn` expected unconfirmed_proposal got null
    - `blk` expected [clarification_pending] got []
- **AR** — RC-04, RC-05
    - `comp` electrical.design: proposed -> included
    - `clar` expected true got false
    - `rsn` expected unconfirmed_proposal got null
    - `blk` expected [clarification_pending] got []

---

### R-001 — no_detection (adversarial) · EN/AR parity: yes

> EN: Kindly share your trade licence and VAT certificate so we can complete your vendor registration.
> AR: نرجو تزويدنا بالرخصة التجارية وشهادة ضريبة القيمة المضافة لاستكمال تسجيلكم كمورّد.

*Sealed rationale:* The message concerns vendor registration documents and gives no evidence of any trade, so nothing is detected and no trade is active. It is not a scope enquiry, so clarification is not required.  (spec 2.7, 2.9)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### R-002 — no_detection (adversarial) · EN/AR parity: yes

> EN: What are your standard payment terms and what retention percentage do you apply?
> AR: ما هي شروط الدفع المعتمدة لديكم وما نسبة الاحتجاز التي تطبقونها؟

*Sealed rationale:* A commercial terms question carries no trade evidence and is not a scope enquiry, so nothing is detected and clarification is false. The no_active_trade blocker is still raised.  (spec 2.7, 2.9)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### R-003 — no_detection (adversarial) · EN/AR parity: yes

> EN: Do you work in Ras Al Khaimah, or do you cover Dubai and Sharjah only?
> AR: هل تعملون في رأس الخيمة أم تغطون دبي والشارقة فقط؟

*Sealed rationale:* A question about geographic coverage is not a statement or enquiry about a scope of works, so no trade is detected and clarification is not required. The only blocker is the absence of an active trade.  (spec 2.7, 2.9)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### R-005 — no_detection (adversarial) · EN/AR parity: yes

> EN: When can your team visit the site? We are available on Tuesday morning.
> AR: متى يمكن لفريقكم زيارة الموقع؟ نحن متاحون صباح يوم الثلاثاء.

*Sealed rationale:* Scheduling a site visit is not a scope statement or a scope enquiry and gives no trade evidence. Nothing is detected and clarification is false.  (spec 2.7, 2.9)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]

---

### R-006 — no_detection (adversarial) · EN/AR parity: yes

> EN: Please confirm receipt of our earlier email and revert at your convenience.
> AR: نرجو تأكيد استلام بريدنا السابق والرد في الوقت المناسب لكم.

*Sealed rationale:* A correspondence acknowledgement carries no trade evidence and is not a scope enquiry, so nothing is detected and no clarification is required. The absence of an active trade is the only blocker.  (spec 2.7, 2.9)

- **EN** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
- **AR** — RC-06
    - `clar` expected false got true
    - `rsn` expected null got no_trade_detected
    - `blk` expected [no_active_trade] got [clarification_pending,no_active_trade]
