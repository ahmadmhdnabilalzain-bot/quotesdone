# Code organisation, before and after (founder row 1556)

Measured 19 Nov 2026 by it_engineer / agent org-report, read-only against git objects.
Before = `5d20a57` (last commit on origin/main up to 10 Nov 23:59, committed 11 Nov 03:32 +0400).
After  = `2801b05` (origin/main head, 19 Nov 18:49 +0400).
Skills used: quotesdone-organised-like-an-auditor-will-read-it, quotesdone-skills-and-plugins-first (rules read).

## What was counted
Files ending .ts .tsx .mjs .cjs .js, line count = `git show <rev>:<path> | wc -l`.
Excluded: node_modules, .claude/, docs/, knowledge/, `*.test.*`, `*.spec.*`, tests/ and e2e/ dirs, scripts/e2e,
scripts/archive, scripts/checks/retired and `*RETIRED*`, imagescript, and everything under any `/vendor/` (the 28,228-line
`sheetjs xlsx.mjs` and its 1,065-line `types/index.d.ts`). SQL not counted. Generated files ARE counted (flagged below).
Counted: 1,382 files before, 1,439 after.

## Headline
| measure | before | after |
|---|---|---|
| source files over 1,000 lines | 5 | 3 |
| source files over 600 lines | 35 | 33 |
| `@ts-nocheck` files (ts/tsx/mjs/js, excl .claude, docs) | 46 | 48 |
| files defining `J` (`const/let/function J` in supabase/functions + src) | 99 | 118 |
| files importing `J` | 71 | 73 |
| files that build a service-role client (SERVICE_ROLE + createClient in supabase/functions + src) | 79 | 79 |
| edge function directories | 79 | 80 |

Read honestly: the 1,000-line count fell from 5 to 3 and the 600-line count only from 35 to 33. Two of the three left are
not small: `demo_factory.mjs` grew 1,953 to 2,023 and `inquiry_intake/handle.ts` GREW 1,187 to 1,418 (it was
"moved verbatim from index.ts" on 9 Nov, then kept receiving code). The two other 1,000+ files before were
`scripts/staging/os2_blueprint/sections_21_40.mjs` (1,187) and `scripts/staging/os_blueprint/components_1_9.mjs` (1,056);
neither is in the after list (they no longer exist in the top 15; scripts/staging no longer holds them).
`@ts-nocheck` and `J` copies went UP, not down: duplicated `J` definitions are the open duplication problem.
The `J` regex counts definitions anywhere in functions and src; the same 79-file service-role figure shows the admin
client was not consolidated. 9 files in `_shared` export an admin/service helper both days.

## Top 15 source files by lines
| # | before (5d20a57) | lines | after (2801b05) | lines |
|---|---|---|---|---|
| 1 | scripts/lib/demo_factory.mjs | 1953 | scripts/lib/demo_factory.mjs | 2023 |
| 2 | _shared/brand_facts.generated.ts (generated) | 1767 | _shared/brand_facts.generated.ts (generated) | 1767 |
| 3 | inquiry_intake/handle.ts | 1187 | inquiry_intake/handle.ts | 1418 |
| 4 | scripts/staging/os2_blueprint/sections_21_40.mjs | 1187 | src/components/portal/supplier/ServicesTab.tsx | 964 |
| 5 | scripts/staging/os_blueprint/components_1_9.mjs | 1056 | ai_gateway/handle.ts | 944 |
| 6 | scripts/staging/os2_blueprint/screens_1_9.mjs | 962 | drawing_redact/index.ts | 841 |
| 7 | ai_gateway/handle.ts | 898 | src/components/me/NewRequest.tsx | 839 |
| 8 | scripts/staging/os_blueprint/components_14_17.mjs | 852 | src/components/portal/supplier/serverCopy.ts | 833 |
| 9 | scripts/staging/os_blueprint/components_11_13.mjs | 833 | _shared/request_fit.ts | 814 |
| 10 | scripts/staging/os_blueprint/cross_os.mjs | 826 | src/components/me/portalText.ts | 712 |
| 11 | src/components/portal/supplier/serverCopy.ts | 794 | _shared/line_specs/workflow.ts | 711 |
| 12 | scripts/staging/journey_test.mjs | 746 | _shared/supplier_services.ts | 708 |
| 13 | src/components/me/NewRequest.tsx | 718 | _shared/quote_generalise.ts | 707 |
| 14 | src/components/portal/supplier/ServicesTab.tsx | 694 | login_otp/index.ts | 686 |
| 15 | scripts/staging/os2_blueprint/layers_1_8.mjs | 692 | inquiry_intake/slots.ts | 686 |
(Paths under supabase/functions/ unless shown. Before: 9 of the top 15 were staging blueprint scripts; after: none.
The top 15 now is production code only apart from demo_factory.)

## Where each kind of thing lives (ARCHITECTURE.md section 1, README "The repository")
A database change is one file in `scripts/sql/`, named as a lowercase sentence, with a line at the END of
`scripts/sql/MANIFEST.txt` (the manifest order decides which file is canonical). The backend is
`supabase/functions/<surface>/index.ts`, one directory per surface (80 now), with code shared between functions in
`supabase/functions/_shared/`. The website and both portals (customer `/me`, supplier `/portal`) are `src/`
(`src/app`, `src/components`, `src/lib`, `src/content`). Checks are `scripts/checks/*.mjs` run by `scripts/checks/run.mjs`
(`npm run gate` is the release gate; a check retires with its subject into `scripts/checks/retired/`). Scripts other
scripts import are `scripts/lib/`; things a person runs live in the other `scripts/` folders; finished one-shots go to
`scripts/archive/`. The founder's words are `public.founder_instruction`, settled policy is
`public.company_policy_decision` plus its guard, conduct rules are `.claude/skills/*/SKILL.md`, narrative is `docs/`
(never the source of truth), and to find a routine, table or cron job by subject open
`docs/architecture/database/README.md` (generated, drift-checked).

## The 5 next splits, in priority order
1. `supabase/functions/inquiry_intake/handle.ts` (1,418, up 231 from 1,187): the only big file that is both the
   customer's front door and growing; its first import line pulls ~40 names from `slots.ts`, so the turn, held-answer
   and requirements paths are mixed. Split by turn stage next to the existing `slots.ts`/`interview.ts`.
2. `scripts/lib/demo_factory.mjs` (2,023, up 70): largest hand-written file, 70 importers, so every fixture change
   touches one blast radius. Split by subject (customer, supplier, request, teardown) behind the same export.
3. `src/components/portal/supplier/ServicesTab.tsx` (964, was 694, up 270): fastest growth of any file; a component
   file of one tab that has become several screens. Extract the sections into siblings.
4. `supabase/functions/ai_gateway/handle.ts` (944, was 898): every model call goes through it, so the cost of a
   mistake is the highest; split provider routing, budget/hold gate and response shaping.
5. `supabase/functions/drawing_redact/index.ts` (841): an index.ts that holds the logic; move into `handle.ts`
   plus modules the way `inquiry_intake` and `ai_gateway` already are. (`brand_facts.generated.ts`, 1,767, is generated
   and should be left alone; `J`, `@ts-nocheck` and the 79 service-role clients are a separate clean-up: one shared
   `J` and one admin-client helper would cut the 118 and 79 figures.)
Reasons here are size, growth between the two dates and the importer count measured above; none was read for defects.
