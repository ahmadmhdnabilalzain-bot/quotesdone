# SPEC #6 — `suppliers categories.txt` (1,007 lines)

Audited 2026-08-11 14:25–14:45 UTC. The file is a taxonomy plus a knowledge standard, so it is the
most literally checkable of the eight: almost every line is a name that either exists as a row or
does not.

| PRESENT | PARTIAL | ABSENT | CONTRADICTED | total |
|---|---|---|---|---|
| 82 | 14 | 8 | 0 | **104** |

The file has three blocks:

| block | lines | contents |
|---|---|---|
| 1 | 1–656 | **66 top-level categories** with **457 subcategory lines** |
| 2 | 657–740 | **84 supplier category names** |
| 3 | 743–1007 | **8 core knowledge modules**, 6 optional modules, and one worked example (Agent 19) |

---

## Block 1 — the 66 categories (L1–L656)

**PRESENT, all 66.** `catalog_domains` holds **67 rows**, and a name-by-name reconciliation puts
every one of the spec's 66 in the table:

Construction · MEP · Utilities · Gas Systems · Wastewater & Drainage · Firefighting · ELV ·
Interior Fit-Out · Luxury Fit-Out · Interior Decoration · Furniture FF&E · Swimming Pools ·
Cold Rooms · Catering · Hospitality Supplies · Bakery · Media AV · Marketing · Exhibition ·
Temporary Event · IT · Data Centres · Telecommunications · Accounting · Banking · Insurance ·
Legal · Business Consulting · HR · Facilities Management · Business Centres · Logistics ·
Oil & Gas · Renewable Energy · Industrial Automation · Bearings · Fasteners · Abrasives ·
Air Compressors · Manufacturing by Process · Chemicals · Healthcare · Laboratory · Cleanrooms ·
Education · Aviation · Marine Safety · Agriculture · Recycling · Real Estate · Textile · Beauty ·
Sports · Religious Facilities · Jewelry · Luxury & Concierge · Retail · Printing · Vehicles ·
Travel · Domestic Services · Pet Industry · Translation · Government Tenders · Testing ·
Miscellaneous.

**The 67th is `General Contracting & Civil Works`, which the contract does not name.** Reported as an
addition, not a defect — it is the obvious gap in a construction marketplace and someone filled it.

### Subcategories — the one place block 1 is short

| | count |
|---|---|
| spec subcategory lines (L1–656) | **457** |
| `catalog_subcategories` rows | **470** |

The counts sit 13 apart in production's favour, but **a count match is not a name match and this
audit does not accept one for the other.** A line-by-line reconciliation of 457 names against 470
rows was not completed within this session and is named as the one unfinished measurement in spec
#6. Verdict: **PARTIAL**, with the specific outstanding work stated.

The category taxonomy is otherwise the healthiest data in the system: `category_keyword` and
`subcategory_keyword` back it, and duplicates were removed on 10 Aug (re-verified today: **0
duplicate slugs, 0 duplicate names**).

---

## Block 2 — the 84 supplier categories (L657–L740)

**PRESENT.** `catalog_supplier_categories` holds **86 rows** against the spec's 84.

Both extras and every one of the 84 map through `catalog_category_domain` (86 rows), so no supplier
category is orphaned from a domain.

---

## Block 3 — the knowledge standard (L743–L1007)

This is the substantive half of the file, and it is **implemented as an explicit standard**, which
is rare in this codebase: `knowledge_module_standard` holds **14 modules** and is the table the
category agents are measured against.

### The 8 core modules (L743–L879) — all PRESENT

| # | spec module | spec line | `knowledge_module_standard` row |
|---|---|---|---|
| 1 | Industry Knowledge | 743 | `Industry Knowledge` |
| 2 | Products & Services | 757 | `Products & Services` |
| 3 | Technical Knowledge | 775 | `Technical Knowledge` |
| 4 | Supplier Knowledge | 792 | `Supplier Knowledge` |
| 5 | **Quotation Knowledge ⭐ (Most Important)** | 806 | `Quotation Knowledge` |
| 6 | Documents Knowledge | 822 | `Documents Knowledge` |
| 7 | UAE Knowledge | 845 | `UAE Regulations & Authorities` |
| 8 | **Inquiry Qualification Logic ⭐⭐⭐** | 866 | `Inquiry Qualification Logic` |

**All eight, including both starred modules, exist as named rows in the standard.** L999–L1007
("Each agent should implement the same modules") is therefore PRESENT as a *definition*; coverage is
measured below.

### The 6 optional modules (L880–L946)

| spec module | spec line | verdict | evidence |
|---|---|---|---|
| Pricing Knowledge | 884 | PRESENT | `Commercial & Pricing` |
| Brand Knowledge | 893 | PRESENT | `Brands & Manufacturers` |
| Standards Knowledge (NFPA, IEC, ASHRAE, ASTM, BS, ISO, EN, UL, Civil Defense) | 898 | PARTIAL | `mdm_standards` holds **22 rows** and `quality_standard` 5, but there is **no `Standards Knowledge` module** in the standard, and `fn_agent_context` never reads `mdm_standards` — the same Layer-4 gap recorded in spec #7 §4 |
| Drawing Knowledge (CAD, BIM, plans, elevations, sections, MEP drawings) | 911 | **ABSENT** | no module, no routine, no component. Consistent with spec #7 §9 Drawing Intelligence being the strongest ABSENT in that file |
| Attachment Analysis (drawings, photos, videos, BOQs, PDFs, Excel) | 922 | PARTIAL | `_shared/attachment.ts` validates type and size; nothing extracts *what information they contain* |
| FAQ Knowledge | 935 | PRESENT | `fn_faq_answer`, `fn_company_faq_sync`, `trg_company_faq_sync` |

### Four modules the standard adds beyond the contract

`Best Practices & Common Mistakes`, `Customer Requirements & Trade-offs`, `Risk Assessment`,
`Troubleshooting & Diagnostics`. Recorded as additions.

### Coverage — the measurement that matters

`agent_knowledge` carries **132 distinct `cat:` keys**:

| | count |
|---|---|
| `cat:` keys carrying **all 14** standard modules | **88** |
| `cat:` keys carrying **8–13** modules | **0** |
| `cat:` keys carrying **zero** standard modules | **44** |
| distinct topics used by `cat:` rows | 56 |

**The distribution is binary: a category agent is either fully equipped or not equipped at all.**
88 complete against 86 supplier categories in the catalog — so every category in the taxonomy has a
fully-populated agent, and there are two to spare.

The **44 with zero standard modules** carry knowledge under 42 non-standard topics. These are the
legacy `cat:` keys, and they are a large part of the **141 `agent_knowledge` keys that resolve to no
employee** recorded in spec #7 §17. They are not missing knowledge; they are knowledge filed under a
vocabulary the standard replaced and nothing migrated or retired.

**Verdict on the knowledge standard: PRESENT with a clean-up outstanding.** This is the strongest
result in spec #6 and one of the strongest in the audit — 88 category agents each carrying 14
standardised knowledge modules is the "different for every supplier category" requirement at L820
actually delivered.

### The worked example — Agent 19, Aluminium & Glass (L948–L998)

The contract gives one fully specified agent as the acceptance test.

| requirement | verdict | evidence |
|---|---|---|
| the agent exists | PRESENT | `cat:aluminium-and-glass-suppliers` **and** `cat:aluminium-glass` both exist in `agent_knowledge` — **two keys for one agent**, an instance of the 44-key legacy problem above |
| Industry / Products / Technical / Supplier / Documents / UAE / Quotation modules | PRESENT | the modern key carries all 14 standard modules |
| the 8 quotation fields to collect (quantity, dimensions, glass spec, frame finish, installation, location, access, delivery date) | PARTIAL | `fn_category_questions` and `field_definition_source` (880 rows) hold per-category question sets; **no inquiry has ever been qualified**, so the collection has never run |

---

## What spec #6 gets right, stated plainly

Of the eight files, this is the one whose *data* most closely matches its text. 66 of 66 categories,
84 of 84 supplier categories, 8 of 8 core knowledge modules, and 88 category agents at full module
coverage. The gaps are three: **Drawing Knowledge is absent entirely**, **Standards Knowledge is
stored but never delivered to an agent**, and **44 legacy `cat:` keys were never retired**.
