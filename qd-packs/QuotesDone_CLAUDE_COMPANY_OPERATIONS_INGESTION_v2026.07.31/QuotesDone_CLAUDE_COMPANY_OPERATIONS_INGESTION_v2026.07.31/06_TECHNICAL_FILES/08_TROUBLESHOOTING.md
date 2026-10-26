# Troubleshooting

## Claude tries to read the master file into context

Stop and redirect it to the manifest, schema and streaming importer. The master file is for human audit only.

## Import creates duplicate records

Use `record_id` as the upsert key and record the package/file SHA-256. Do not key by title.

## Supabase REST cannot access the staging schema

Use a direct database migration or configure the client/schema intentionally. Do not expose the staging schema publicly merely to simplify import.

## Existing schema differs from the template

Expected. Use `mapping_decisions`; reuse or extend current objects instead of blindly applying the template.

## A live binding does not exist

Mark unresolved and disable it. Do not substitute a guessed table or field.

## Scenario fails because the frontend is missing

Record a frontend blocker and add the test to the current repository. Do not mark the workflow complete.

## Embedding cost is high

Embed only narrative records whose content hash changed. Do not embed rules, SOP steps, KPI formulas, IDs or exact workflow state unless a proven retrieval use exists.

## Legal or tax record seems incomplete

Retrieve the current official source and route it to the designated professional reviewer. Do not fill gaps from model memory.

## Import takes too long

Use 250–1,000 row batches, resumable file checkpoints and concurrency within database/provider limits. Avoid one API request per record.
