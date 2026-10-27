---
name: the-packs-are-unopened-zips-in-downloads
description: "pack_scorecard.mjs --packs wants the founder's knowledge packs EXTRACTED; they are unopened .zip files in C:\\Users\\Opera\\Downloads, which is why several sessions recorded the scorecard as \"not run, directory recorded nowhere\""
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-04T09:23:56.895Z
---

`node scripts/kb/pack_scorecard.mjs --ref=htdblwldjkcgjvmqkbeh --packs=<dir>` needs a directory
holding one folder per pack, each named exactly like its zip, with the pack's own folder inside it:

```
<dir>/QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31/QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31/...
<dir>/QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31/QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31/...
<dir>/QuotesDone_AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS_PACK_v2026.07.31/QuotesDone_AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS_PACK_v2026.07.31/...
<dir>/QuotesDone_COMPLETE_OS_PORTALS_AUTONOMY_UPDATE_PACKAGE_v2026.07.31/QuotesDone_Autonomous_Company_Upgrade_v2026.07.31/...
```

The sources are `C:\Users\Opera\Downloads\QuotesDone_*_v2026.07.31.zip` — never extracted, which is
the whole reason earlier sessions wrote "the extracted packs directory is recorded nowhere".
`unzip -o "<name>.zip" -d <dir>/<name>` per pack reproduces the layout above in seconds.

**Why:** the scorecard is §9 sweep step 3 and it measures something no other check does — whether
each pack artefact was ingested AND is read by a live routine, probed rather than asserted. First
run, 4 Sep 2026: **99.8% ingested across 37 of 37 artefacts, 36 of 37 in use**; the single
NOT-READ artefact was the 86-category route tests, whose hourly cron 222 was off
([[the-route-tests-were-a-capability-with-no-entry-point]]). It also states the honest retrieval
number: 95,323 of 2,686,026 kb_chunks carry an embedding (3.5%) — company kinds are 100%,
third-party reference kinds (standard, cert, textbook, guide, book...) are 0% by scope, keyword only.
