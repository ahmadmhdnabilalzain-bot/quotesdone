---
name: role-certification-map-exists
description: The 180-role→certification map and web-validated source registry live in docs/expertise/ — pipeline Step 1 is done
metadata: 
  node_type: memory
  type: project
  originSessionId: 95f8dff2-f1de-4ffd-b43c-3c5d91878414
  modified: 2026-08-27T21:34:35.300Z
---

Agent-expertise knowledge pipeline **Step 1 is complete** (28 Aug 2026, PR #476 on branch
`launch-readiness-plan-2026-08-27`). Three committed artifacts under `docs/expertise/`:

- `ROLE_CERTIFICATION_MAP.csv` — one row per canonical role, **verified to match `public.org_role`
  exactly (180/180, 0 missing, 0 extra)**. Columns: `role_id, department, primary_track,
  primary_credential, certifying_body, secondary_tracks, uae_overlays, notes`. `primary_track` /
  `secondary_tracks` key into the registry below, so ingestion (steps 2–4) and the exam loop (step 6)
  iterate over role × track deterministically. `cfo`/`financial_controller` → CPA (2024 CPA Evolution),
  honouring the founder's accountant-passes-the-CPA bar.
- `CERTIFICATION_SOURCE_REGISTRY.md` — web-validated registry of every cert/standard/regulation with
  the certifying body's OWN syllabus URL + top domains + an honest `fetched`/`located`/`derived`
  validation flag. Four blocks: A professional certs, B UAE regulatory anchors, C trade standards,
  D fields with no single license (body named, marked derived).
- `README.md` — the 7-step pipeline and its zero-cost/holds boundary.

**Why:** the whole expertise workstream (steps 2–7: collect → extract → skill → embed/semantic →
exam → refresh) reads this map as its work-list. Do not re-derive it — extend it.

**How to apply:** when starting steps 2–4, ingest the registry's sources (start with the CPA exemplar
and the UAE anchors FTA VAT/CT + PDPL). 86 of the 180 roles are `category_overlay_*` supplier-domain
specialists mapped to trade standards; the rest are functional roles on professional-cert tracks. The
real retrieval gap (step 5) is semantic vs keyword — see [[retrieval-is-keyword-not-vector]]. Toolbox
is fenced under `tools/` ([[drive-the-knowledge-road-alone]]). Roles table is `public.org_role`
(180 rows, 10 departments; marketplace holds 103).
