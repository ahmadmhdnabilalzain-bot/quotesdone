---
name: absent-input-scores-as-satisfied
description: "A missing input file or row can score as a MET requirement — pct(got, 0) returns 100 — so check what a scorer does when its source is absent, not only when it disagrees."
metadata: 
  node_type: memory
  type: project
  originSessionId: e5b298f0-12e8-4cda-8c29-f9b16960b3bd
  modified: 2026-08-12T21:11:33.677Z
---

`scripts/kb/pack_scorecard.mjs` read `lines(p) -> 0` for a file that is not on disk, and
`pct(got, want)` returned **100 when want === 0**. Three of the four v2026.07.31 pack directories are
absent from the working tree, so every artefact in them scored a perfect 100% INGESTED. The headline
number was mostly a statement about files the scorer could not see (13 Aug 2026).

**Why:** the "no data" case and the "requirement fully met" case both collapse to zero-versus-zero,
and a denominator of zero is the usual place they meet. It is the mirror of
[[least-ignores-nulls-in-postgres]] — there a NULL made a score perfect, here an absent file does.

**How to apply:** when reading any scorer, ask what it prints if its INPUT vanishes. If the answer is
"full marks", that is a defect even when every current number is right. Fix it by making absence its
own verdict (`null` → `NO SOURCE`, excluded from averages and counted separately), never by
defaulting it to 0 or 100. Related: [[instruments-report-on-the-wrong-subject]] and
[[checks-can-measure-row-age-not-mechanism]].
