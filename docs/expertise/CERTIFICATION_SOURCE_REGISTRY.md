# QuotesDone — certification source registry

**Written 28 August 2026. Agent-expertise workstream, Stage 1 of the knowledge pipeline.**

This is the authoritative, web-validated registry of the real certifications / standards / regulations
that define expert-level knowledge for QuotesDone's agent roles. It is the fixed reference the rest of
the pipeline draws on: **step 1 (map roles → certs) reads this; steps 2–4 (collect → extract → skill)
ingest these exact sources; step 6 (exam loop) tests against these blueprints.**

Every row was derived by me and **validated against the certifying body's OWN published page** off the
public web (WebFetch/WebSearch, zero cost, no customer/supplier/money/automation touched). The
`validation` column is honest about the boundary the session's rules demand:

- **fetched** — the certifying body's own syllabus/blueprint/law page was actually loaded and confirmed on-topic.
- **located** — the official page is on the body's own domain and named in search, but the specific
  document is a paywalled standard (ISO), a bot-blocked domain (DIFC, DEWA, iso.org, CEN/EN, BICSI),
  or a `?rev=`-gated CDN PDF (PMI) that could not be fetch-confirmed in this session. The URL is the
  official one; the *content* behind it is not re-verified here.

Where a cert was recently restructured, the current edition is named so the pipeline ingests the live
blueprint, not a retired one.

---

## A. Professional certifications (functional roles)

| track | cert (edition) | body | official syllabus / blueprint URL | top domains | validation |
|---|---|---|---|---|---|
| **acct-cpa** | Uniform CPA Exam — 2024 CPA Evolution | AICPA / NASBA | https://www.aicpa-cima.com/resources/landing/exam-blueprints | Core: AUD, FAR, REG + 1 Discipline (BAR/ISC/TCP) | fetched |
| **acct-cma** | CMA (2024 CSO, eff. 1 Sep 2024) | IMA / ICMA | https://www.imanet.org/ima-certifications/cma-certification/cma-handbook | Part 1 Financial Planning/Performance/Analytics; Part 2 Strategic Financial Management | located |
| **acct-acca** | ACCA Qualification | ACCA | https://www.accaglobal.com/gb/en/student/exam-support-resources.html | Applied Knowledge (BT/MA/FA); Applied Skills (LW/PM/TX/FR/AA/FM); Strategic Professional (SBL/SBR+2) | located |
| **fin-cfa** | CFA Program — Candidate Body of Knowledge | CFA Institute | https://www.cfainstitute.org/programs/cfa-program/candidate-resources/cbok | Ethics, Quant, Econ, FSA, Corp Issuers, Equity, Fixed Income, Derivatives, Alts, Portfolio Mgmt | fetched (weights not on CBOK page) |
| **audit-cia** | CIA — 2025 syllabus (IPPF-aligned) | The IIA | https://www.theiia.org/en/certifications/cia/exam-prep-resources/exam-syllabus/ | P1 Fundamentals; P2 Engagement; P3 Function | fetched |
| **fraud-cfe** | CFE — 3-section (from 2 Jun 2026) | ACFE | https://www.acfe.com/cfe-credential/about-the-cfe-exam/exam-blueprint | Fraud Schemes & Financial Crimes; Investigations & Legal Issues; Prevention & Deterrence | fetched |
| **proc-cips** | CIPS Diploma L4 / Adv L5 / Prof L6 (→ MCIPS) | CIPS | https://www.cips.org/qualifications/diploma-in-procurement-supply | L4: Scope & Influence, Business Needs, Commercial Contracting, Ethical Sourcing, Negotiation… | located (page timed out) |
| **pm-pmp** | PMP — 2021 Exam Content Outline | PMI | https://www.pmi.org/-/media/pmi/documents/public/pdf/certifications/pmp-examination-content-outline.pdf | People 42%, Process 50%, Business Environment 8% | located (CDN `?rev=` gate) |
| **pm-prince2** | PRINCE2 7 Practitioner (7th ed., 2023) | PeopleCert / AXELOS | https://www.axelos.com/resource-hub/syllabus/prince2-practitioner-syllabus | 7 Principles, 7 Practices, 7 Processes, People, Sustainability | located |
| **sec-cissp** | CISSP — exam outline eff. 15 Apr 2024 | ISC2 | https://www.isc2.org/certifications/cissp/cissp-certification-exam-outline | 8 domains: SRM 16%, Asset 10%, Arch/Eng 13%, Net 13%, IAM 13%, Assess/Test 12%, Ops 13%, SW Dev 10% | fetched |
| **sec-iso27001** | ISO/IEC 27001:2022 (Annex A) | ISO/IEC | https://www.iso.org/standard/27001 | 93 controls / 4 themes: Organizational 37, People 8, Physical 14, Technological 34 | located (paywalled) |
| **priv-cippe** | CIPP/E | IAPP | https://iapp.org/certify/cippe/ | EU DP intro; Regulatory institutions; GDPR; Compliance | located |
| **priv-cipm** | CIPM | IAPP | https://iapp.org/certify/cipm/ | Developing a Privacy Program; Program Operational Life Cycle (Assess/Protect/Sustain/Respond) | fetched |
| **hr-shrm** | SHRM-CP / SHRM-SCP (SHRM BASK) | SHRM | https://www.shrm.org/credentials/certification/exam-preparation/bask | People, Organization, Workplace + 3 behavioral clusters; 14 functional areas | located |
| **qa-istqb** | ISTQB Certified Tester Foundation v4.0 | ISTQB | https://istqb.org/certifications/certified-tester-foundation-level-ctfl-v4-0/ | Fundamentals; Testing in SDLC; Static Testing; Analysis & Design; Managing Test; Tools | fetched |
| **scm-ascm** | CPIM v9 (eff. 1 Jun 2026) / CSCP | ASCM (APICS) | https://www.ascm.org/globalassets/ascm_website_assets/docs/ecm/ecm-cpim9.pdf | Strategy align, S&OP, Demand, Internal/External Supply, Inventory, Distribution, Quality, Tech | fetched |
| **log-cilt** | CILT International L2–L6 | CILT International | https://ciltinternational.org/education-training/international-qualifications/ | Logistics & Transport qualifications by level | located |
| **fm-ifma** | CFM / FMP | IFMA | https://www.ifma.org/credentials/certified-facility-manager-cfm/ | 11 Core Competencies (O&M, Project, Finance, Leadership, Real Estate, Sustainability, Risk, Tech…) | located |
| **data-cdmp** | CDMP (DAMA-DMBOK2) | DAMA International | https://cdmp.info/about/ | Governance, Modelling, Quality, Metadata, MDM, DW/BI, Architecture, Security, Integration… (14 topics) | fetched |
| **qual-lss** | Lean Six Sigma / ISO 9001 QMS | ASQ / ISO | https://asq.org/cert/six-sigma-black-belt | DMAIC, process capability, SPC; ISO 9001:2015 QMS clauses | located |
| **acct-ifrs** | IFRS Accounting Standards + ISA (auditing) | IFRS Foundation / IAASB | https://www.ifrs.org/issued-standards/ · https://www.iaasb.org/standards-pronouncements | IFRS standards; International Standards on Auditing | fetched |

## B. UAE regulatory anchors (apply on top of any UAE-facing role)

| track | instrument | authority | official URL | validation |
|---|---|---|---|---|
| **uae-vat** | VAT law + Executive Regulation + guides | Federal Tax Authority | https://tax.gov.ae/en/taxes/Vat.aspx | fetched |
| **uae-ct** | Corporate Tax — Federal Decree-Law No. 47 of 2022 | Federal Tax Authority | https://tax.gov.ae/en/content/federal.decreelaw.no.47.of.2022.on.taxation.of.corporations.and.businesses.home.new.aspx | fetched |
| **uae-taxagent** | FTA Tax Agent registration programme | Federal Tax Authority | https://tax.gov.ae/en/tax.support/tax.agents/registration.requirements.aspx | fetched |
| **uae-pdpl** | Personal Data Protection Law — Federal Decree-Law No. 45 of 2021 | UAE Data Office / TDRA | https://u.ae/en/about-the-uae/digital-uae/data/data-protection-laws | fetched |
| **uae-aml** | AML/CFT for DNFBPs — goAML; Fed. Decree-Law 20/2018 | Ministry of Economy / FIU | https://www.moet.gov.ae/en/registering-companies-in-goaml | fetched |
| **uae-fire** | UAE Fire & Life Safety Code of Practice (2018) | UAE Civil Defence | https://www.dcd.gov.ae/portal/preventive-safety/uae-fire-and-life-safety-code-of-practice.jsp | fetched |
| **uae-ccl** | Commercial Companies Law — Federal Decree-Law No. 32 of 2021 | Ministry of Economy | https://www.moet.gov.ae/documents/20121/376326/Commercial+Companies.pdf | fetched (binary) |
| **uae-difc** | DIFC Companies Law No. 5 of 2018 | DIFC | (difc.com legal database) | located (403) |
| **uae-adgm** | ADGM Companies Regulations 2020 | ADGM | https://www.adgm.com/legal-framework/rules-and-regulations | fetched |
| **uae-esr-ubo** | ESR (Cabinet 57/2020); UBO (Cabinet 58/2020); Consumer Protection 15/2020 | MoF / MoE | https://mof.gov.ae/en/public-finance/international-relations/economic-substance-regulations-esr/ | fetched |
| **uae-gold** | DMCC UAE Good Delivery; DCL hallmarking (CIBJO); UAE.S/GSO fineness | DMCC / Dubai Central Laboratory | https://dmcc.ae/ecosystems/gold | fetched |
| **uae-legal-lic** | Advocate licensing (mainland MOJ) / DIFC Register of Legal Practitioners | MOJ / DIFC Courts | https://www.difccourts.ae/difc-courts/registration-of-practitioners | fetched (MOJ page 404) |

## C. Trade / technical standards (supplier-category specialists)

| track | trade family | flagship standard(s) | body | UAE adoption | validation |
|---|---|---|---|---|---|
| **trade-concrete** | construction, cement, concrete | ACI CODE-318; BS EN 206 | ACI / CEN | DM/MoIAT specs reference ACI 318 & EN 206 | fetched (ACI) |
| **trade-steel** | steel, reinforcement, welding | ASTM A615; BS 4449; AWS D1.1 | ASTM / AWS | ESMA/ECAS conformity; AWS D1.1 in specs | fetched |
| **trade-hvac** | MEP, HVAC, energy | ASHRAE 90.1 / 62.1 / 55 | ASHRAE | Al Sa'fat / Estidama reference | fetched |
| **trade-electrical** | electrical, ELV, smart-home | IEC 60364; ISO/IEC 11801 | IEC | DEWA/ADDC regs based on IEC 60364/BS 7671 | fetched (IEC); DEWA 403 |
| **trade-plumbing** | plumbing, sanitaryware, gas, drainage | IAPMO UPC; IPC | IAPMO / ICC | UPC/IPC in UAE practice | fetched |
| **trade-fire** | fire fighting, fire alarm, life safety | NFPA 13/72/101 + UAE Fire Code 2018 | NFPA / Civil Defence | UAE Fire Code references NFPA | fetched |
| **trade-envelope** | waterproofing, insulation, roofing | ASHRAE 90.1 envelope; Estidama | ASHRAE / DMT | Estidama Pearl; Al Sa'fat | fetched (ASHRAE) |
| **trade-fitout** | gypsum, flooring, aluminium/glass, joinery, paints | ASTM C1396; BS EN 13830; EN 14351 | ASTM / CEN | DM/Trakhees specs | fetched (ASTM C1396) |
| **trade-tic** | testing, inspection & certification | ISO/IEC 17020; ISO/IEC 17025:2017 | ISO/IEC + ILAC | EIAC (ILAC MRA signatory) | fetched (ILAC); iso.org 403 |
| **trade-lifts** | lifts & escalators | EN 81-20/50:2020; ASME A17.1 | CEN / ASME | DM/Civil Defence apply EN 81 | located (CEN 403) |
| **trade-oilgas** | oil & gas, industrial equipment | API 6A / 610 / 650 | API | ADNOC uses API as-is | fetched (API 650) |
| **trade-automation** | industrial automation, functional safety | ANSI/ISA-61511 (IEC 61511); IEC 61508 | ISA / IEC | adopted as international | fetched (ISA-84) |
| **trade-logistics** | logistics, freight, warehousing/3PL | IATA Cargo Agency; FIATA Model Rules 2019 | IATA / FIATA | applied directly | fetched |
| **trade-medical** | medical equipment, pharma (GMP/GDP), lab | ISO 13485:2016; GMP/GDP; ISO/IEC 17025 | ISO / MOHAP-EDE | EDE + MOHAP GSDP licensing | fetched (MOHAP); iso 403 |
| **trade-prof-acct** | accounting/audit firm suppliers | IFRS + ISA; ACCA/CPA/ICAEW | IFRS/IAASB | IFRS mandated; MoE auditor licence | fetched |
| **trade-prof-tax** | tax-consultant suppliers | FTA Tax Agent programme; CTA | FTA | UAE-specific credential | fetched |
| **trade-prof-legal** | law-firm suppliers | Advocate licence; DIFC Register | MOJ / DIFC | UAE-specific licensing | fetched (DIFC) |
| **trade-prof-consult** | management-consulting suppliers | CMC® (ICMCI); ISO 20700 | CMC-Global | via national IMCs | fetched |

## D. Fields with no single licensing exam (derived — body named, not a single cert)

These roles have no one certification that "you pass or fail." The bar is still real expertise, so each
maps to the recognized professional body-of-knowledge for its field. Marked **derived**: I did not
validate a single licensing syllabus this session because none governs the field; the pipeline should
ingest the named body's published body-of-knowledge and build a composite exam.

| track | field | recognized body-of-knowledge / body | validation |
|---|---|---|---|
| **mkt-cim** | marketing, brand, content, social, creative | CIM Professional Marketing (Chartered Institute of Marketing); DMI; Google/Meta platform certs | derived |
| **sales-revops** | sales, BD, account mgmt, CRM/RevOps, partnerships | professional selling + RevOps body of practice (no license); CIM for demand-gen | derived |
| **cs-iso18295** | customer success, support, onboarding, retention, comms | ISO 18295 (customer contact centres) + customer-success practice | derived |
| **swe-swebok** | backend/frontend/optimization engineering | IEEE SWEBOK v3 + OWASP ASVS (security) | derived |
| **aieng-iso42001** | AI architect/director, prompt/agent eng, solution arch, CTO | ISO/IEC 42001 (AI management system) + ISO/IEC 23894 (AI risk) | derived |
| **prod-pm** | product management | product-management body of practice (Pragmatic / SVPG); SAFe POPM | derived |
| **ux-nng** | product/UX design, visual design | Nielsen Norman Group UX body of knowledge | derived |
| **td-atd** | learning & development, capability, culture | ATD CPTD (talent development) + SHRM | derived |
| **exec-strategy** | CEO, CoS, performance/strategy directors | CMI Level 7 strategic management + Balanced Scorecard; composite finance/ops literacy | derived |
| **km-iso30401** | knowledge/taxonomy/category curation | ISO 30401 (knowledge management) + ISO 25964 (thesauri) on top of **data-cdmp** | derived |

---

**Trade families without a single global standard** (event mgmt, catering/hospitality supplies, cleaning,
security guarding [Dubai SIRA], travel [IATA], real estate [RERA/DLD], HR/recruitment agencies,
translation, printing/signage, beauty/gym, pet/vet, marketing agencies): the governing UAE licence or
sector regulator is the authority (SIRA, RERA/DLD, KHDA, MOHRE, IATA/TCA). These are mapped per-overlay
in `ROLE_CERTIFICATION_MAP.csv` under track `trade-uae-licensed` with the specific regulator named.
