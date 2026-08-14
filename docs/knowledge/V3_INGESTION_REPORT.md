# V3 ingestion report

14 August 2026. Package `QuotesDone_AGENT_KNOWLEDGE_V3_RUNTIME_TRAINING_ONLY_v2026.08.14`,
version `2026.08.14`.

## Package verification

| check | result |
|---|---|
| outer ZIP SHA-256 | `e165bceaacc65d8d58d8611796d477341d4e67567d01dc0d4e46aa43fa3c2854` — matches, 37,381,742 bytes |
| internal `SHA256SUMS.txt` | 11 of 11 present files verified OK |
| embedded V2 complete delivery | `fc4dc95727560ec8012d26e58764b549e072cfd7d405f92f462bc12cbf2e4674` — matches |
| V2 inner `SHA256SUMS.txt` | 11 of 11 verified OK |
| files listed but absent | `COMPLETE_DELIVERY_SUMMARY_V3.json`, `V3_BUNDLE_SEAL.json`, and **both certification ZIPs** — intentional for a runtime-only bundle |
| path traversal | 0 |
| secret-shaped strings | 0 (scanned every text record for API-key, JWT and private-key patterns) |
| parse failures | 0 |
| conflicting stable ids | 0 |

Verify with `node scripts/kb/v3_inventory.mjs <extracted-root>`.

## Declared counts, verified

| entity | declared | measured |
|---|---|---|
| departments | 24 | 24 |
| operational roles | 96 | 96 |
| category specialists | 86 | 86 |
| V3 role adversarial | 2,304 | 2,304 |
| V3 role tool-use | 1,152 | 1,152 |
| V3 role uncertainty | 1,152 | 1,152 |
| V3 role cross-department | 768 | 768 |
| V3 department management/system | 672 | 672 |
| V3 category specialist | 2,924 | 2,924 |
| **V3 training total** | **8,972** | **8,972** |

## Two counting decisions

**Re-delivery is not duplication.** 3,528 company-operations records ship twice: once in the
baseline corpus and once in the department assignment file, which adds a `v2_assignment`
block. Both copies agree on every shared key. The importer merges them on the stable id
rather than inserting twice or rejecting the second, and the source path of both copies is
kept in `source_ids`. A further 168 records are byte-identical re-deliveries.

**A parser version is part of a document's checksum.** The first parser read only top-level
YAML scalars, so the category question banks and competency graphs arrived as prose. Fixing
it changed no file, so an idempotent importer correctly reported "unchanged" and the better
structured data would never have been written. `PARSER_VERSION` is mixed into the checksum of
every whole-document record; the fix landed as 3,605 updates and 0 inserts.

## What was imported

| store | rows | what |
|---|---|---|
| `ops_knowledge` | 8,256 total — 7,825 from the delivery | runtime-retrievable knowledge |
| `agent_training_case` | 17,890 — 8,972 V3, 8,918 V2 | training material, reachable only through the remediation loop |
| `cert.*` | 0 | created empty; see below |

`ops_knowledge` by layer (production, identical on staging):

| layer | rows | of which deterministic |
|---|---|---|
| department_shared | 2,024 | 0 |
| source_reference | 1,031 | 1,031 |
| failure_mode | 980 | 288 |
| authority | 806 | 806 |
| policy | 743 | 646 |
| role_specific | 576 | 0 |
| decision_playbook | 552 | 0 |
| category_specialist | 516 | 0 |
| kpi | 360 | 360 |
| remediation | 183 | 183 |
| company_core | 54 | 0 |

3,314 records are marked deterministic: they are looked up as structured rows and are never
the output of a similarity search. 96 of 96 roles and 86 of 86 categories have their own
knowledge.

## Certification material was NOT imported

The V2 delivery ships **4,550 certification and evaluation records with their expected
answers**, across 389 files. They were counted, listed and left on disk. A builder session
must not hold an answer key, and a runtime agent must not be able to reach one.

- `ops_knowledge` rows with layer `certification`: **0** on both projects
- `ops_knowledge` rows whose source path names a certification file: **0**
- `agent_training_case` rows from certification files: **0**
- `cert.certification_answer_key`: **0**

The V3 certification questions and the evaluator answer key were never in this package and
were never searched for.

## Idempotency

Run the importer twice; the second run must insert nothing.

| run | project | inserted | updated | unchanged | rejected | errors |
|---|---|---|---|---|---|---|
| first | staging | 25,715 | 0 | 0 | 0 | 0 |
| second | staging | **0** | **0** | 25,715 | 0 | 0 |
| first | production | 11,890 (+13,825 already written before a 429) | 0 | 13,825 | 0 | 0 |
| parser upgrade | both | 0 | 3,605 | 22,110 | 0 | 0 |
| final | staging | **0** | **0** | **25,715** | **0** | **0** |
| final | production | **0** | **0** | **25,715** | **0** | **0** |

The production first run was interrupted by a management-API 429 after writing 13,825 rows.
That run is recorded as `failed` in `knowledge_ingestion_run` with the reason; the importer
now backs off on 429 and the next run re-asserted every row. Nothing was lost and nothing was
written twice — which is what an idempotent importer is for.

## Rollback

`knowledge_ingestion_undo` stores the row about to be overwritten before each upsert, so a
run can be reversed exactly rather than approximately. `fn_knowledge_rollback(run_id)` deletes
rows the run created and restores rows it changed.

Rehearsed in staging inside an aborted transaction: **300 damaged rows restored, 1 created row
deleted, transaction rolled back, nothing persisted.**

## Reproducing

```
node scripts/kb/v3_inventory.mjs <extracted-root>
node scripts/kb/v3_crosswalk.mjs <extracted-root>
node scripts/kb/v3_identity_load.mjs --ref=<project>
node scripts/kb/v3_import.mjs <extracted-root> --ref=<project> --apply
node scripts/kb/v3_report.mjs
```
