# Recurrence guards for the fixes merged on 21 Sep 2026

Founder, 21 Sep 2026 (instruction 573): *"are you making sure all these bugs are being solved permanently? i dont want things to pop up again for the same reasons"*.

Seat: it_engineer. For every defect fixed by a PR merged to main on 21 Sep (#760–#776), the question is: **which check FAILS if that exact cause returns?** "Verified" means the check was read and run in this session, not taken from the PR text. The new mirror guards were also mutated (the old body put back into `supabase/schema/full_schema.sql`) and all three failed, then the file was restored. The rule itself is in `.claude/skills/quotesdone-apply-discipline/SKILL.md` §9.

PRs with no defect fix are left out of the table: #762 (skill text), #763 (doctrine docs), #764 and #765 (features, with their own tests), #770 (knowledge authoring), #772 and #774 (purge rule changes, covered by the #769 rows).

| # | PR | Defect | Cause | Guard: fails if it returns | Verified |
|---|---|---|---|---|---|
| 1 | #760 | ops_knowledge fully copied every night | the incremental rule was keyed to one table name | `scripts/checks/a_restore_rebuilds_from_base_plus_increments.test.mjs` (by SIZE) | yes, ran |
| 2 | #760 | a deleted row came back on restore | the change trigger did not log DELETE | same file (DELETE logged and exported) | yes, ran |
| 3 | #760 | a TRUNCATE left no trace | no statement trigger for TRUNCATE | **NEW** `scripts/checks/the_live_schema_keeps_the_fixes_of_21_september.test.mjs` | yes, ran |
| 4 | #760 | incremental page hit the 524 on kb_chunks | `t.id::text in (…)` made the index unusable | **NEW** same file (no cast on the table key) | yes, mutated |
| 5 | #760 | restore never replayed; `lost_rows` excused any logged key | the drill skipped increments | the live half of the restore test (needs the management token, so it skips in the CI checks job) plus monthly IT duty 19 | partly: runs only with a token |
| 6 | #761 | every star press returned HTTP 500 | the handler sent a stars-only rating to a CHECK that required a comment | `supabase/functions/customer_api/rating_input.test.ts` (stars only, short comment, bad rating) | yes, ran (deno) |
| 7 | #761 | same (database side) | `reviews_reason_required` demanded a comment | **NEW** live-schema test (every CHECK on reviews allows `comment IS NULL` and is validated) | yes, mutated |
| 8 | #761 | Arabic dates read backwards at 11 sites | a hard `dir="ltr"` around `fmtDate(…,'ar')`, and 5 copies of `Ltr` | `scripts/checks/ltr_is_never_forced_onto_a_localised_date.test.mjs` | yes, ran |
| 9 | #761 | the footer date stayed backwards | CSS `direction:ltr` overrode the `dir` attribute | same file (`:not([dir])`) | yes, ran |
| 10 | #761 | Arabic-Indic digits would scramble | U+0660–0669 were treated as RTL | `src/lib/ltrDirection.test.mjs` | yes, ran |
| 11 | #761 | "Reveal" greyed out after paying to reveal | the step was read from `rfqStageIdx` (hired only) | **NEW** `scripts/checks/the_customer_portal_fixes_of_21_september_stay_fixed.test.mjs` | yes, ran |
| 12 | #761 | empty-state flash after "Request sent" | stale `data` shown during the refresh | **NEW** nightly journey a, step "no empty-state flash after "Request sent"" (`scripts/e2e/journeys.mjs`: a MutationObserver in the page, 6 s from "Request sent") | see the addendum |
| 13 | #766 | negotiation_assistant deleted in the repo but still live | the repo and the live project drifted | `scripts/gen_supabase_config.mjs --check` (run by `deploy_functions.mjs` before every deploy) and `every_deployed_function_has_an_owner.mjs` | yes, ran: OK, 67 functions |
| 14–19 | #767 | six IT causes that paged the founder | see `docs/it/IT_FAILURES_18_21_SEP_2026.md` | `scripts/checks/it_failures_of_18_to_21_september_do_not_recur.test.mjs` | yes, ran. It **found #20**. The `fn_it_detect < 6 s` timing assertion failed once (10.1 s, with the census running) and passed on the rerun |
| 20 | #767 | **fn_it_backup_recheck raises 42702 on every call** (the backup refile loop and the CEO's coverage decider are dead) | the UPDATE's alias `d` has the same name as the record `d public.doc_backups`. The file's probe read source text and never ran the routine | **NEW** `scripts/checks/no_routine_names_a_table_alias_after_its_own_record.test.mjs` (every plpgsql routine in the mirror). Fix: `scripts/sql/the_backup_recheck_names_its_table_alias_apart_from_its_record.sql` | yes. The check fails today, and on exactly this one routine. The fix ran rolled back on production and returned `closed 3, orphaned_abandoned 1` |
| 21 | #769 | the purge census went wrong: 524, and non-standard kinds at 1,178,961 in the census vs 589,199 live, with 2 SIZE rows | census INSERTs were retried on any 5xx (a 524 can commit behind the error), one unsliced request, and nothing compared the census with the table | **NEW** `scripts/kb/purge_census.test.mjs`. The driver now refuses unless each source_kind sums to its live count and there is 1 SIZE row. Census writes are never retried on 5xx. Every kind goes in id slices of 100k | yes, ran |
| 22 | #769 | the foreign bulk comes back | re-import | `scripts/checks/the_knowledge_library_holds_no_foreign_bulk.mjs` | read. It stays red until the purge has run |
| 23 | #771 | Account Name dropped keystrokes | `Row` was declared inside the component's render | **NEW** portal test (no component declared inside another; 3 pre-existing sites named) | yes, ran |
| 24 | #771 | "Open this request" unreadable | the secondary button mixed a navy background with theme text | **NEW** portal test | yes, ran |
| 25 | #771 | a wrong URL showed the bare English 404 | no `[locale]/not-found.tsx` | **NEW** portal test | yes, ran |
| 26 | #771 | "rising" shown for a single month; Arabic chart months | trend and month-label logic | `src/components/portal/intelligence/spread.test.mjs` | yes, ran |
| 27 | #771 | reserved sign-up domains accepted | no refusal | `src/lib/signupEmail.test.mjs` | yes, ran |
| 28 | #771 | items 15, 16, 20, 22, 24, 25, 27 (theme, copy, layout) | copy and presentation | **NEW** nightly journey h (`scripts/e2e/journey_audit_buttons.mjs`): 15 theme switches on the first press; 16 an absurd project budget is refused; 22 and 24 no developer text on any customer destination; 25 a reload stays on its section. **Still unguarded: 20 and 27** (need a supplier-count and a one-quote fixture) | see the addendum |
| 29 | #773 | findings 1, 2, 4, 12, 13, 14, 15, 28 (quotation review) | reading and matching rules | `supabase/functions/supplier_api/quote_review.test.ts` and `_shared/line_specs/derive.test.ts` | yes, ran (deno, 64 passed with #6 and #30) |
| 30 | #775 | the customer got Stripe's invoice PDF | reveal_invoice handed out Stripe's copy | `scripts/checks/every_pdf_we_issue_is_on_our_template.test.mjs` and `reveal_invoice/resolve.test.ts` | yes, ran |
| 31 | #773/#775 | findings 29, 33, 35 and the in-app invoice button opening an empty tab | UI state | **NEW** nightly journey h: the "Invoice (PDF)" button's tab must end on our PDF (accountant); 35 a submitted quote is served back with its VAT basis. **Still unguarded: 29 and 33** (alias across the review thread and the PDF; the submit confirmation) | see the addendum |
| 32 | #776 | 5 npm advisories | dependency age | weekly IT duty (`scripts/it/report_dependency_audit.mjs`), the same one that found them | detection, not prevention |
| 33 | #776 | knowledge_gap tasks re-asked for ever; no decider for supplier_registered / sales_rating | no terminal state | **NEW** live-schema test | yes, ran |
| 34 | #776 | the first v2 tick scanned 0 of 8 rows | a back-off earned under v1 bound v2 | **NEW** live-schema test (the picker's version must equal the version the consumer writes) | yes, mutated |
| 35 | #776 | PITR-off re-filed as a defect | no founder-decision path | **NEW** live-schema test | yes, ran |
| 36 | merge | a MANIFEST line lost in a merge | conflict resolution dropped the line | `scripts/checks/canonical_routine_manifest.mjs` (MANIFEST GAP, in `project-parity.yml` on every PR) | yes, ran: gaps 0 |
| 37 | CI | the edge-log gate reported "unreadable" after one miss | a single request decided the verdict | `scripts/lib/retry.test.mjs`. 3 attempts; still exit 2 if the log stays unreadable | yes, ran; live run exit 0 |
| 38 | CI | main deploy run 35619142770 went red at 62/63 on a jsr.io timeout | no retry for a registry blip | `scripts/lib/retry.test.mjs` (the classifier: the verbatim jsr timeout is transient; TS, bundle and module-not-found errors are not) | yes, ran |

**Counts.** 38 rows (grouped where one guard covers several items). Before today: 19 guarded, 1 partly guarded (row 5, token-only), 1 detection only (row 32), 17 unguarded. Added: 14 guarded by the new checks (rows 3, 4, 7, 11, 20, 21, 23–25, 33–35, 37, 38). Still unguarded: 3 rows (12, 28, 31). All are browser-only UI, and they need a nightly journey step from the owning seat.
