# Token-efficient ingestion method

## The important rule

Claude should understand the importer and the schema. Claude should not consume the corpus text as conversation tokens.

## Correct method

1. Read the compact package manifest, schema, QA and crosswalk.
2. Write or adapt one local importer.
3. Stream each JSONL file from disk.
4. Validate in code.
5. Upload in batches.
6. Store file hashes and resume checkpoints.
7. Return only counts, errors and test results.
8. Generate embeddings asynchronously for changed narrative records only.

## Do not do this

- Do not paste master markdown files into chat.
- Do not ask Claude to summarize every department before import.
- Do not embed SOPs, decision rules, KPIs or exact workflow state unless semantic retrieval is genuinely needed.
- Do not regenerate records that already have stable IDs.
- Do not create embeddings for unchanged records.
- Do not send live customer or supplier data to a model merely to decide a deterministic state transition.

## Runtime cost control

Priority order:

1. SQL, deterministic rules and templates
2. Internal lexical/vector retrieval
3. Approved small or self-hosted model for natural-language extraction
4. Premium text model for material ambiguity or complex synthesis
5. Multimodal model for drawings/images
6. Licensed professional for binding regulated decisions

Measure model cost per completed business outcome, not only per call.
