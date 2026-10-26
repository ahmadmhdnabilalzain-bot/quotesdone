---
name: specs-are-upgrades-not-repairs
description: "The 8 QuotesDone spec files are UPGRADES to build, not defect lists to repair — MISSING means build it, never \"make the existing thing cover it\""
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 6e7fe490-cc78-4ea2-a2ad-9b9b12c85e76
  modified: 2026-08-06T17:00:02.282Z
---

The founder's 8 spec files (architecture, OS.txt, OS 2.txt, customer portal, supplier portal,
categories, agents+knowledge, openrouter) are **specifications for capabilities to BUILD**, not
audits of a broken system. When a requirement scores MISSING, the correct response is to **build
the missing capability**. It is NOT to:

- argue the requirement is "already covered" by an existing routine,
- wire an existing asset to a new reader and call the requirement satisfied,
- mark it blocked because a neighbouring feature already does something adjacent,
- recommend against a tool the founder supplied on the grounds that current code overlaps it.

**Why:** stated 6 Aug 2026 after I evaluated PaddleOCR, MinerU and cad-viewer — repos the founder
had just supplied for the customer/supplier portal rows — and recommended AGAINST adopting them
because `doc_extract` "already covers" document extraction and adopting them was a "regression
risk". That reasoning is correct for a repair and wrong for an upgrade: the spec asks for a
Document Intelligence Vault and 3D Project Visualization, which `doc_extract` does not provide.
The founder is buying new capability, not defending existing behaviour.

**How to apply:**
- Read a MISSING verdict as a build order. Estimate and build it.
- "Already covered" is only a valid answer when the existing thing genuinely satisfies the
  requirement AS WRITTEN — verify against the spec's own words, not against a paraphrase.
- Tools the founder supplies are a signal of intended direction. Default to adopting them for the
  row they serve, not to justifying why current code suffices.
- Still never fabricate data to turn a gate green, and still measure honestly — the scepticism
  applies to EVIDENCE, not to ambition. See [[quotesdone-definition-of-done]].
- The "built but never read" defect remains real and worth wiring, but wiring a reader is the
  FLOOR, not the deliverable, when the spec asks for something larger.

Related: [[quotesdone-autonomy-and-staging-rules]], [[quotesdone-work-without-checkins]].
