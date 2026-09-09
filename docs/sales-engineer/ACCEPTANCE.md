# Sales Engineer — acceptance checklist

Source: `QuotesDone_Sales_Engineer_Build_Prompt_v1.txt` §18, plus the integration document's §F.
This file is the scoreboard. A row is only ticked when it was proved BY EXECUTION and the evidence
is named. "Reads correctly" is not a pass.

Status vocabulary, kept deliberately separate because the spec demands it:
**populated** · **imported/staged** · **runtime-connected** · **tested** · **deployed** · **verified-live**

---

## A. Scenario tests the spec names explicitly (§18)

Each must be exercised against the real application, not a unit-test double.

| # | Scenario | Status | Evidence |
|---|---|---|---|
| 1 | Whole fit-out rejected for a CCTV-only supplier | — | |
| 2 | Separate lot matched correctly | — | |
| 3 | Supplier missing optional catalogue is NOT auto-rejected (services) | — | |
| 4 | Supplier false approval claim is caught | — | |
| 5 | Expired licence at the moment of dispatch blocks it | — | |
| 6 | Wrong-account clarification reply is refused | — | |
| 7 | Contradictory BOQ vs drawing is surfaced, not silently resolved | — | |
| 8 | Missing CAD XREF detected and reported | — | |
| 9 | Scan-only PDF handled (OCR as fallback, not first step) | — | |
| 10 | Repeated views / duplicate assemblies not double-counted | — | |
| 11 | Unit conversion correct | — | |
| 12 | Native-file metadata leakage prevented | — | |
| 13 | Unknown specialty handled without nearest-keyword misroute | — | |
| 14 | F&B excluded vs restaurant fit-out permitted | — | |
| 15 | No eligible supplier → supply gap + CEO-supervised recovery, no founder ask | — | |
| 16 | Prohibited cold outreach refused | — | |
| 17 | Atomic last quota slot under concurrency | — | |
| 18 | Unsubscribe / registration race resolved correctly | — | |
| 19 | Ambiguous provider timeout reconciled before retry | — | |
| 20 | Restart recovery | — | |
| 21 | Prompt injection confers no authority | — | |
| 22 | CEO outage → routine work continues inside unexpired grants | — | |
| 23 | End-of-day digest with founder endpoints disabled | — | |

## B. Integration compatibility tests (integration doc §F)

| # | Scenario | Status | Evidence |
|---|---|---|---|
| 24 | onboarding-document → Sales verification → Support notification | — | |
| 25 | Sales clarification → Support reply → Sales record | — | |
| 26 | CEO decision → Sales execution → verified report | — | |
| 27 | Expired-licence match invalidation | — | |
| 28 | Founder endpoints disabled, company still runs | — | |
| 29 | Duplicate / out-of-order events | — | |
| 30 | Missing agent service (do not fabricate acceptance) | — | |
| 31 | Exactly ONE daily CEO digest | — | |
| 32 | Customer external-human-contact rule preserved without case abandonment | — | |

---

## C. Invariants that must never be violated

These are not tests to pass once; they are properties that must hold at all times.

1. **No founder approval anywhere.** No workflow may depend on Ahmad's availability. The digest is an
   informational subscription, never a queue. Sales never emails the founder directly — only the CEO
   does, and only when a recipient is configured.
2. **A delivered envelope is not acceptance; an accepted task is not completed work; a completed
   subtask is not a resolved external case.** Four distinct states, never collapsed.
3. **Unknown mandatory evidence is not a pass.** Absence never scores as satisfied.
4. **One authoritative writer per record type.** Sales writes technical capability and verification;
   Support writes channel/conversation state.
5. **Do not create a second CEO or Support** to route around an unfinished dependency, and do not
   fabricate task acceptance by an agent that is not running.
6. **Never claim full extraction when only a subset worked.** Per-format capability status is
   published and honest; unsupported DWG is not advertised as done.
7. **A cold list is not sent through a provider that prohibits it** — not even at low volume, not by
   rotating senders or domains.
8. **99% quoteability is an aspiration to measure, not a result to claim.** Report matured cohorts,
   denominators and sample counts, or report nothing.
9. **Model access is verified, not assumed.** A catalog entry is not account access; no silent
   substitution of a cheaper similarly-named model.
10. **Existing data is preserved.** No customer, supplier, valid knowledge, licence, target or history
    is deleted, and no deleted department is revived to own a reused function.

---

## D. Delivery artefacts the spec requires (§18 final paragraph)

- [ ] Code and migrations
- [ ] Knowledge counts (populated vs staged vs connected)
- [ ] Current taxonomy and field mappings
- [ ] Integration contracts
- [ ] Application test evidence
- [ ] Model evaluation results
- [ ] Capability matrix (per format, per sector, honest about gaps)
- [ ] Secure setup requirements
- [ ] Recovery runbooks
