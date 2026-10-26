# Founder ledger reconciliation — 12 Oct 2026 (ledger 1069)

Scope: the 79 rows of `public.founder_instruction` with status `open` on 12 Oct 2026. Each row was updated by its exact id.
Evidence sources: production DB `htdblwldjkcgjvmqkbeh` (routines, `seat_duty`, `model_policy`, `llm_route_health`, `legal_documents`, `notifications`, `app_secrets`, `cron.job`), `origin/main` at 25c8078, and `gh pr list`.
Result: 23 done, 9 standing, 11 superseded, 36 still open. Counts after the update: open 36, done 314, standing 51, superseded 26.

| id | verdict | evidence, or what is missing | launch-critical? |
|---|---|---|---|
| 13 | open | No measured senior-standard score per seat (ceo) | no |
| 30 | open | Drawing workflow built (#1008, #1056, #1111, #1000). No measured accuracy run on a ZZ DEMO set (sales_engineer) | no |
| 31 | open | DWG, DXF and PDF readers merged (#829, #983). No measured element-understanding score (sales_engineer) | no |
| 580 | open | Count, redaction and benchmark merged. No measured end-to-end run covering count, zero contact details, BOQ PDF and ingestion (sales_engineer) | no |
| 640 | superseded | by 1141 | – |
| 701 | done | #983 and #829 merged; cad_convert is bound to sales_engineer | – |
| 709 | superseded | by 1069 | – |
| 760 | superseded | by 1092 and 1119 | – |
| 781 | open | 124-scenario suite merged (#1006). No full run with the LLM on (customer_support) | YES |
| 887 | done | #879, #910, #990, #1004 merged; trg_outcome_learning and fn_lesson_* are live | – |
| 888 | open | No measured senior pass per seat (ceo) | no |
| 889 | open | Knowledge library #1210 and Arabic ranking #1259 are still open (it_engineer) | no |
| 892 | standing | Items 886-892 are recorded in the ledger and were reconciled again today | – |
| 893 | open | Per-trade knowledge not measured complete (sales_engineer) | no |
| 894 | open | Packs exist (#1042-#1046, #988, #1005). Professional standard not measured (ceo) | no |
| 899 | open | UAE market depth not measured complete (sales_engineer) | no |
| 900 | open | No completed missing-trade taxonomy pass found (sales_engineer) | no |
| 903 | open | `it_engineer.knowledge_exam` is DISABLED; last ok 23 Sep | no |
| 917 | superseded | by the 15-agent limit and 1092. The knowledge work itself stays open in other rows | – |
| 960 | superseded | by 1092 and 1119 | – |
| 993 | open | The evening list email is live, but it says "would invite 30" while invite_daily_cap=50 and invite_schedule plans 50. Safe volume is unproven: `fn_invite_placement_gate()` = `fail:no_check` (marketing, it_engineer) | YES |
| 1003 | open | No two-stage senior verdict per seat (ceo) | no |
| 1005 | open | SE knowledge build not measured complete | no |
| 1008 | standing | #1065, #1209, #1195 merged. 0 of 200 supplier notifications since 29 Sep are Arabic | – |
| 1009 | done | self_review duties, outcome learning, price benchmarks, CEO weekly review, root-cause loop, close pack, game day, fn_challenge, marketing scorecard | – |
| 1013 | open | Most items are live. Seat handover notes and plain-language customer answers have no routine | no |
| 1018 | done | stalled rescue, quote_quality_hold, concierge, supplier_availability and fraud/risk duties all ok 12 Oct; trade_words.ts is gone from main | – |
| 1019 | open | 34 PRs open, including backlog items | no |
| 1026 | done | #1195 merged; rfq_clarification is live | – |
| 1027 | open | PR #1191 not merged (sales_engineer) | no |
| 1028 | open | PR #1180 not merged (sales_engineer) | no |
| 1056 | superseded | by 1107 and 1108 | – |
| 1057 | superseded | by 1119 and 1121 | – |
| 1058 | done | #1114 merged; blog review and publish routines are live | – |
| 1059 | done | #1128 merged; fn_marketing_blog_revise_due is live | – |
| 1063 | done | #1136 and #1143 merged; all 84 seat_duty rows have an owner_seat | – |
| 1068 | done | 0 GLM in routines, model tables, supabase/functions, src and checks. Only historical applied SQL and MANIFEST lines remain | – |
| 1069 | done | this file | – |
| 1084 | open | Knowledge exam duty disabled; no LLM-on reworded exam (it_engineer) | no |
| 1089 | done | #1169 merged. 0 enterprise tables, columns, routines, kb chunks or duties | – |
| 1091 | done | #1171 merged | – |
| 1092 | open | 34 PRs open; backlog T1-T7 not finished | no |
| 1094 | done | #1220 merged; kb_chunks = 351 MB | – |
| 1096 | superseded | by 1119 | – |
| 1105 | superseded | by 1119 | – |
| 1107 | done | #1217 merged. 0 active DeepSeek routes | – |
| 1108 | done | #1217 merged. Primary is gpt-6-luna on 57 rows; fallback is gemini-3.8-flash on 58 | – |
| 1113 | open | `fn_invite_placement_gate()` = `fail:no_check`. No inbox-placement test (it_engineer, marketing) | YES |
| 1115 | open | M365 lane built (#1225, #1264) but `invite_m365_enabled=false` | YES |
| 1118 | done | #1226 merged (Serper) | – |
| 1119 | open | Stage-2 E2E is dry-run only (#1230); #1270 and #1285 are open | YES |
| 1120 | open | GlockApps test not run | YES |
| 1121 | open | No completed 10+10 ZZ DEMO run with cleanup | YES |
| 1122 | open | Terms are done. Privacy 1.6 (#1234) is not merged; 1.5 is live (ceo) | YES |
| 1123 | superseded | by 1126 | – |
| 1126 | done | Retention plan uses 5 years; cron is daily; mode=remove | – |
| 1127 | done | Retention only touches conversation tables; the summary routine and its cron are live | – |
| 1135 | standing | 18/18 runs-on lines use ubicloud | – |
| 1141 | standing | Rule; honoured here | – |
| 1142 | standing | Rule; campaign held (invite_enabled=false) | – |
| 1143 | open | Security audit not run; the pre-launch subset is not evidenced (it_engineer) | pre-launch subset: YES |
| 1146 | open | Founder's own 2FA and password-off list; cannot be measured from code | final checklist |
| 1149 | standing | Founder decision; the link is kept | – |
| 1150 | standing | Trademark deferred | – |
| 1152 | open | No routine routes a human-review request to the owning seat (ceo) | no |
| 1155 | done | supplier-agreement v15 is live (6 Oct) with the no-liability and introducer clauses | – |
| 1156 | done | customer-terms v10 clause 8 is live (6 Oct): intermediary, not a party; cites Art. 252/265 of Decree-Law 50/2022 | – |
| 1159 | standing | Working rule | – |
| 1160 | open | Browser walk #1270 not merged | YES |
| 1161 | done | #1269 merged | – |
| 1164 | open | Intake accuracy suite #1285 not merged; accuracy not measured | YES |
| 1167 | done | #1283 merged and applied 11 Oct | – |
| 1172 | done | Agents continued: #1283 and #1277 merged; 4,518 agent_runs in the last 24h | – |
| 1173 | superseded | duplicate of 1172 | – |
| 1175 | standing | All 19 routes are closed-circuit with reason founder:1175 | – |
| 1176 | open | Code holds mismatched licences (#1268, #1275); the name is not auto-filled from the licence (sales_engineer) | YES |
| 1177 | open | #1289 not merged | YES |
| 1180 | open | #1284 and #1280 not merged | no |
| 1181 | open | #1292 not merged; no 30-minute purge of unfinished sign-ups in production | YES |

## Still-open launch-critical items (block the supplier campaign)
1. **Deliverability not proven** (1113, 1120, 993-2, 1115): `fn_invite_placement_gate()` returns `fail:no_check`. No GlockApps test has run, and the M365 lane is switched off.
2. **The daily list email shows the wrong number** (993-1): it says 30 a day while the cap and the schedule are 50.
3. **Stage-2 sandbox E2E not run** (1119, 1121): only the dry run exists (#1230).
4. **Browser walk** (1160, #1270), **document intake accuracy** (1164, #1285) and **read every attachment** (1177, #1289) are all open PRs.
5. **Licence name auto-fill** (1176): not built. The code holds the supplier instead.
6. **Unfinished sign-up purge** (1181): #1292 is open.
7. **Privacy policy 1.6** (1122, #1234): not live. It is the disclosure the invitation link relies on (1149).
8. **Support suite run with the LLM on** (781): never run.
9. **Pre-launch security subset** (1143), plus the founder's own 2FA list (1146).

Side observations (not ledger rows): a "SCHEDULER DOWN — automation stalled" alert reached the founder in the last 7 days. Only 3 pg_cron jobs exist, because scheduling runs through `seat_duty` (84 duties, most ok today).
