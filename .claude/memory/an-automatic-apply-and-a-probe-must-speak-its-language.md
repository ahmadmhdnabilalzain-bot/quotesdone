---
name: an-automatic-apply-and-a-probe-must-speak-its-language
description: 2 Nov 2026. apply-on-merge.yml facts learned on its first runs.
metadata:
  type: reference
---
A line added to scripts/sql/MANIFEST.txt applies on merge (ledger 1463). A probe must raise a message with PROBE OK or PROBE FAILED or the rehearsal refuses the file; a bare CHK<<...>> is refused. The seat comes from the file's "-- Seat:" header, then the merge title. To resume after a stop: dispatch with from=<commit>. The database check stays red on the PR for its own unapplied routines (read the finding list, not the colour), and on every branch until the schema mirror is regenerated; a workflow's own push starts no checks, so push an empty commit after regen-schema-mirror.yml. Paid or live workflows must not trigger on push to main.
