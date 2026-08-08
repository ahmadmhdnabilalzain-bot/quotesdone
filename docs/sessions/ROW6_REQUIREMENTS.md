# ROW #6 — SUPPLIER CATEGORIES AND THEIR AI AGENTS: THE ENUMERATION

Source: `docs/specs_row6_supplier_categories_and_agents.txt`, 1,008 lines.
Enumerated 2026-08-09. **283 requirements.** This number is asserted as `TOTAL` in
`scripts/staging/verify_category_agents.mjs`; a run that registers a different count prints
`!! N checks ran, the spec has 283` and the percentage is not trustworthy.

The count is not row #5's 234 and was not derived from it. Row #5 scored a *screen*; row #6 scores a
*corpus*. The spec has no UI mock in it at all — it is a taxonomy plus a knowledge contract — so the
grain rule is inherited but the evidence is different: no check in this row looks at a `.tsx` file.

Grain rule, identical to rows #4 and #5: **one enumerated line of the spec = one requirement.**
Where the spec names a list (66 domain groups, 84 realistic categories, 14 document types, 15 UAE
authorities, 9 standards bodies), every member is a requirement. Each knowledge domain additionally
carries the coverage requirement the spec implies — *every* agent implements it, not the corpus on
average.

---

## THE TWO BARS, STATED BEFORE SCORING

Two different kinds of requirement need two different bars, and mixing them is how a scorer lies.

**BAR A — the eight domains: 84 of 84.** The spec says "Every AI Agent Needs These Knowledge
Domains" and closes with "Each agent should implement the same modules". That is a universal claim
about every agent, so its check is universal: a domain is MET only when **all 84** mapped category
agents carry it. One agent short is MISSING. This is the founder's "score per domain per agent,
never a total" — these eight checks are per-agent counts, and the count prints.

**BAR B — the sub-bullets: 21 of 84 (25%).** The spec introduces every sub-list with the word
*"Example:"*. `BOQ`, `Shop Drawings`, `DEWA` and `Civil Defense` are examples of what a domain holds,
not universal mandates — a BOQ is genuinely irrelevant to a translation agency, and requiring it on
all 84 would manufacture a false MISSING and then a build order to fabricate it. So a sub-bullet is
MET when the concept appears in the relevant domain's content on **at least 21 of the 84** mapped
agents: enough to be a pattern rather than one lucky paragraph.

**The exact agent count prints beside every verdict either way.** A bullet at 84/84 and a bullet at
22/84 are both visible as exactly what they are; nothing is hidden behind a threshold.

---

## §1 Domain Taxonomy — 66

The spec's 66 numbered group headings, one requirement each. Each must exist as a `catalog_domains`
row at its spec number. Scored as a per-item coverage count over ONE table (row #5's defect class
#3), not 66 independent greps.

`dom-01` Construction, Civil & Building Materials … `dom-66` Miscellaneous / Catch-All.

## §2 Realistic Supplier Categories — 84

The spec's "Realistic Suppliers Categories List (UAE)", 1–84, one requirement each. A category is
MET when it exists in `catalog_supplier_categories` at its spec number **and** carries an agent —
the section is about categories that have an agent behind them, so a catalogue row alone does not
satisfy it.

`cat-01` Construction Materials Suppliers … `cat-84` Wastewater & Drainage Contractors.

## §3 Industry Knowledge — 9

| id | requirement |
|---|---|
| `ind-coverage` | **BAR A** — all 84 mapped agents carry an Industry Knowledge module |
| `ind-overview` | industry overview |
| `ind-scope-of-work` | scope of work |
| `ind-terminology` | common terminology |
| `ind-market-segments` | market segments |
| `ind-uae-practices` | local UAE practices |
| `ind-supplier-ecosystem` | supplier ecosystem |
| `ind-customer-types` | customer types |
| `ind-workflows` | typical workflows |

## §4 Products & Services — 13

| id | requirement |
|---|---|
| `prod-coverage` | **BAR A** — all 84 carry a Products & Services module |
| `prod-categories` | product categories |
| `prod-hierarchy` | product hierarchy |
| `prod-materials` | materials |
| `prod-models` | models |
| `prod-variants` | variants |
| `prod-sizes` | sizes |
| `prod-specifications` | specifications |
| `prod-accessories` | accessories |
| `prod-services-offered` | services offered |
| `prod-installation` | installation services |
| `prod-maintenance` | maintenance services |
| `prod-warranties` | warranties |

## §5 Technical Knowledge — 10

| id | requirement |
|---|---|
| `tech-coverage` | **BAR A** — all 84 carry a Technical Knowledge module |
| `tech-materials` | materials |
| `tech-components` | components |
| `tech-performance` | performance |
| `tech-standards` | standards |
| `tech-compatibility` | compatibility |
| `tech-installation-methods` | installation methods |
| `tech-design-considerations` | design considerations |
| `tech-limitations` | limitations |
| `tech-common-problems` | common problems |

## §6 Supplier Knowledge — 9

| id | requirement |
|---|---|
| `sup-coverage` | **BAR A** — all 84 carry a Supplier Knowledge module |
| `sup-types` | supplier types |
| `sup-manufacturers` | manufacturers |
| `sup-distributors` | distributors |
| `sup-importers` | importers |
| `sup-contractors` | contractors |
| `sup-installers` | installers |
| `sup-maintenance-companies` | maintenance companies |
| `sup-service-providers` | service providers |

## §7 Quotation Knowledge ⭐ — 8

The spec marks this "the most important" and "your platform's core".

| id | requirement |
|---|---|
| `quo-coverage` | **BAR A** — all 84 carry a Quotation Knowledge module |
| `quo-mandatory-info` | mandatory information |
| `quo-optional-info` | optional information |
| `quo-affects-price` | what affects price |
| `quo-affects-delivery` | what affects delivery |
| `quo-affects-installation` | what affects installation |
| `quo-rejection-causes` | what causes suppliers to reject quotations |
| `quo-required-documents` | what documents are required |

## §8 Documents Knowledge — 16

| id | requirement |
|---|---|
| `doc-coverage` | **BAR A** — all 84 carry a Documents Knowledge module |
| `doc-boq` | BOQ |
| `doc-shop-drawings` | Shop Drawings |
| `doc-ifc-drawings` | IFC Drawings |
| `doc-as-built` | As Built Drawings |
| `doc-datasheets` | Datasheets |
| `doc-material-submittals` | Material Submittals |
| `doc-rfq` | RFQs |
| `doc-rfi` | RFIs |
| `doc-method-statements` | Method Statements |
| `doc-technical-specs` | Technical Specifications |
| `doc-photos` | Photos |
| `doc-site-videos` | Site Videos |
| `doc-purchase-orders` | Purchase Orders |
| `doc-contracts` | Contracts |
| `doc-when-needed` | "the AI should know when each document is needed" — timing, not just the list |

## §9 UAE Regulations & Authorities — 16

| id | requirement |
|---|---|
| `uae-coverage` | **BAR A** — all 84 carry a UAE Regulations module |
| `uae-municipality` | Municipality requirements |
| `uae-civil-defense` | Civil Defense |
| `uae-dewa` | DEWA |
| `uae-addc` | ADDC |
| `uae-etihad-we` | Etihad Water & Electricity |
| `uae-trakhees` | Trakhees |
| `uae-dda` | DDA |
| `uae-rta` | RTA |
| `uae-dm` | DM |
| `uae-dubai-municipality` | Dubai Municipality |
| `uae-abudhabi-municipality` | Abu Dhabi Municipality |
| `uae-local-standards` | local standards |
| `uae-regulations` | UAE regulations |
| `uae-local-approvals` | local approvals |
| `uae-local-terminology` | local terminology |

## §10 Inquiry Qualification Logic ⭐⭐⭐ — 9

The spec marks this "probably the most important module".

| id | requirement |
|---|---|
| `iql-coverage` | **BAR A** — all 84 carry an Inquiry Qualification module |
| `iql-question-order` | which questions to ask first |
| `iql-dependent-questions` | which questions depend on previous answers |
| `iql-mandatory-info` | which information is mandatory |
| `iql-skippable-info` | which information can be skipped |
| `iql-enough-collected` | when enough information has been collected |
| `iql-confidence-score` | confidence score |
| `iql-missing-info` | missing information |
| `iql-validation-rules` | validation rules |

## §11 Optional Knowledge Modules — 35

The spec: "Some agents will also need these." Scored at BAR B throughout — these are explicitly
optional, so a count is the honest verdict and the count prints.

**Pricing Knowledge (3):** `opt-pricing-factors`, `opt-pricing-market-ranges`, `opt-pricing-cost-drivers`

**Brand Knowledge (4):** `opt-brand-major-manufacturers`, `opt-brand-local`, `opt-brand-international`,
`opt-brand-alternatives`

**Standards Knowledge (9):** `opt-std-nfpa`, `opt-std-iec`, `opt-std-ashrae`, `opt-std-astm`,
`opt-std-bs`, `opt-std-iso`, `opt-std-en`, `opt-std-ul`, `opt-std-civil-defense`

**Drawing Knowledge (7):** `opt-draw-cad`, `opt-draw-bim`, `opt-draw-pdf`, `opt-draw-plans`,
`opt-draw-elevations`, `opt-draw-sections`, `opt-draw-mep`

**Attachment Analysis (7):** `opt-att-drawings`, `opt-att-photos`, `opt-att-videos`, `opt-att-boq`,
`opt-att-pdf`, `opt-att-excel`, `opt-att-understands-content`

**FAQ Knowledge (5):** `opt-faq-difference`, `opt-faq-which-choose`, `opt-faq-how-long`,
`opt-faq-whats-included`, `opt-faq-maintenance`

## §12 Agent Mechanism — 8

The spec's closing line, "Each agent should implement the same modules", is a claim about a *system*,
not a corpus. These eight are the mechanism requirements it implies: knowledge nobody can reach is
not knowledge the platform has.

| id | requirement |
|---|---|
| `mech-agent-per-category` | every one of the 84 realistic categories has an agent |
| `mech-agent-registry-row` | the agent is a registered object, not only a bare knowledge key |
| `mech-resolve-by-slug` | a routine resolves a catalogue slug to its agent |
| `mech-resolve-legacy-vocab` | resolution also accepts the live intake vocabulary, not only catalogue slugs |
| `mech-knowledge-one-call` | one routine returns an agent's modules |
| `mech-modules-together` | that call returns all eight mandatory modules in one payload |
| `mech-per-category-not-generic` | the content differs per category — not one template with the name swapped |
| `mech-graph-edge` | the category → agent relationship is present in the knowledge graph |

---

## TOTAL

| § | n | § | n |
|---|---|---|---|
| 1 Domain taxonomy | 66 | 7 Quotation ⭐ | 8 |
| 2 Realistic categories | 84 | 8 Documents | 16 |
| 3 Industry | 9 | 9 UAE Regulations | 16 |
| 4 Products & Services | 13 | 10 Inquiry Qualification ⭐⭐⭐ | 9 |
| 5 Technical | 10 | 11 Optional modules | 35 |
| 6 Supplier | 9 | 12 Agent mechanism | 8 |

**283**

---

## KNOWN OVERLAP RISKS — resolved before the first run

Row #5 lost a day to four pairs of checks sharing one piece of evidence. Four pairs here describe
adjacent things and must not share evidence:

1. `tech-materials` (§5) / `prod-materials` (§4) — the same word, two domains. Each is scored
   **inside its own domain's content**, never across the whole corpus, so one paragraph about
   materials cannot satisfy both.
2. `tech-standards` (§5) / `uae-local-standards` (§9) / `opt-std-*` (§11) — three different claims
   about standards. §5 is scored in Technical content, §9 in UAE content, §11 across the corpus.
3. `quo-required-documents` (§7) / the fourteen `doc-*` types (§8) — "which documents are required
   to quote" is a Quotation claim; the document vocabulary is a Documents claim. Different topics.
4. `iql-mandatory-info` (§10) / `quo-mandatory-info` (§7) — the spec lists "mandatory information"
   under both. §7's is scored in Quotation content, §10's in Inquiry Qualification content.

## THE TRAP THIS ROW IS MOST EXPOSED TO — AND IT IS NOT ROW #5'S TRAP

Row #5's seven false MISSINGs came from a scan whose **population** excluded where the fact lived —
the rpc hop. Row #6's equivalent is the **column**: the opening brief states "none of the eight
domains is a layer", which is true, and concludes the schema cannot answer "does agent X cover
Technical Knowledge?", which is false. The eight domains are `agent_knowledge.topic` values, spelled
exactly as the spec spells them. A scorer that looked only at `layer` would have reported all eight
domains MISSING on all 84 agents and issued a build order to regenerate 672 rows that already exist.

Every check in this row therefore names the column it reads in its evidence string.
