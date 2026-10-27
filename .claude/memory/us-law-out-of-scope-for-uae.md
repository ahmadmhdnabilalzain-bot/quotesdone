---
name: us-law-out-of-scope-for-uae
description: HR/legal/procurement corpus must be UAE/GCC/international only — no US (or other foreign) domestic law
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 20379a52-970f-4c8e-a53c-f852a8ab92f2
  modified: 2026-08-28T14:21:19.387Z
---

Founder ruling (28 Aug 2026): QuotesDone is a UAE company, so for the **legal, hr (labour), and
procurement/compliance** knowledge categories, ingest ONLY UAE + GCC + genuinely-international/UN
instruments (UAE/DIFC/ADGM/CBUAE, GCC codes, UNCITRAL/WIPO/UNIDROIT/Hague/WTO/FATF/ILO/OECD/ISO/World Bank).
NEVER ingest US (or any single foreign jurisdiction's) statutes/regulations — US Code, CFR, FAR/DFARS,
state law. His words: "US laws are irrelevant to UAE… when it comes to HR or legal stuff… make sure you
don't mix things up as it may cause confusion."

**Why:** a UAE HR agent citing US FLSA, or a legal agent citing the US Bankruptcy Code, is simply wrong for
the jurisdiction and confuses the answer. 44 US-law sources / 16,572 chunks were removed from
legal/hr/procurement on 28 Aug 2026.

**How to apply:** brief every legal/hr/procurement ingestion agent to exclude foreign domestic law and stay
on UAE/GCC/international. BUT — **US-origin TECHNICAL standards the UAE adopts are NOT "law" and DO stay**
(NFPA — Dubai Civil Defence mandates it; NIST, ASHRAE, USACE/UFC, IETF RFCs, FDA/WHO, IEEE) — those live in
engineering/it/construction/mep/fire/health categories. See [[agent-knowledge-loads-into-ops-knowledge]] and
the playbook docs/expertise/CORPUS_INGESTION.md JURISDICTIONAL SCOPE section.
