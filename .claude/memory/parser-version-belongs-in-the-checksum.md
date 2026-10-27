---
name: parser-version-belongs-in-the-checksum
description: "An idempotent importer keyed on the file digest can never deliver a parser fix — the file did not change, so \"unchanged\" is correct and the better data is silently never written."
metadata: 
  node_type: memory
  type: project
  originSessionId: b8f9a77d-66be-4ac4-aff5-ec6af2024801
  modified: 2026-08-14T08:58:11.104Z
---

14 Aug 2026, V3 knowledge import. Whole-document records were checksummed with the sha256 of
the source file. The YAML reader then improved from "top-level scalars only" to a block
parser, which turned 3,605 category question banks and competency graphs from prose into
queryable structured data — and the importer reported every one of them **unchanged**, because
the file had not moved. The idempotency that protects the corpus also blocks every improvement
to how it is read.

Fix: `checksum = sha256(fileDigest + ':' + PARSER_VERSION)`, bumped on any change to the
parser. The fix then landed as 3,605 updates and 0 inserts, which is exactly right.

**Why:** the checksum has to cover everything that determines the stored row, and for a derived
record that includes the code that derived it — not just the bytes it derived it from.

**How to apply:** any importer that transforms a source into a row should mix its transform
version into the row's change key. Ask: *if I fix the parser and re-run, does the fix reach the
database?* If the answer is no, the key is wrong. Same shape as [[instruments-report-on-the-wrong-subject]] —
the digest was measuring the file, not the record.
