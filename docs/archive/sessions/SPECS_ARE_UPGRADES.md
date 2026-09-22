# THE SPEC FILES ARE UPGRADES, NOT REPAIR TICKETS

**Founder, 6 August 2026.** Read this before scoring or building against any of the eight spec
files (architecture, `OS.txt`, `OS 2.txt`, customer portal, supplier portal, categories,
agents+knowledge, openrouter).

## The rule

> **A MISSING verdict is a BUILD ORDER.**

These files specify capabilities the founder is buying. They are not an audit of a broken system.
When a requirement scores MISSING, build the capability. Do **not**:

- argue the requirement is "already covered" by an existing routine;
- wire an existing asset to a new reader and declare the requirement satisfied;
- mark it blocked because a neighbouring feature does something adjacent;
- recommend against a tool the founder supplied because current code overlaps it.

## What triggered it

On 6 Aug 2026 the founder supplied PaddleOCR, MinerU, cad-viewer, OpenConstructionERP and
cad2data — explicitly "for row 3 and other rows". The evaluation that came back recommended
**against** adopting any of them, on the grounds that `doc_extract` already turns page images into
structured JSON, that adopting them was a "regression risk" against a green 7/7 gate, and that the
capability was "already covered".

That reasoning is correct for a repair and **wrong for an upgrade**. The customer portal spec asks
for a *Document Intelligence Vault* (§14) and *3D Project Visualization* (§6, §19). `doc_extract`
provides neither. The founder was buying new capability; the evaluation defended existing
behaviour.

## How this changes the work

| Old posture (wrong) | Correct posture |
|---|---|
| "asset exists, no reader → wire a reader, done" | wiring a reader is the FLOOR; if the spec asks for more, build the rest |
| "already covered by X" | only valid if X satisfies the requirement **as written** — check the spec's own words |
| "blocked, needs traffic/capacity" | build the mechanism AND the surface; state the traffic dependency separately |
| "founder's tool overlaps our code, skip it" | founder-supplied tools signal direction — default to adopting for the row they serve |

## What does NOT change

The scepticism applies to **evidence**, never to ambition:

- Never fabricate, back-date or mass-close data to turn a gate green.
- Never report a percentage not measured symmetrically.
- Never weaken a check to make it pass — build the system so it passes honestly.
- Deploy to **both** projects and verify by executing, in the same turn.

The "built but never read" defect is still real and still worth fixing — it has appeared nine
times. But finding a reader for an orphaned table is the minimum, not the deliverable, whenever
the spec asks for something larger.
