# Ledger reconciliation, 27 Oct 2026 (ceo seat)

Source: public.founder_instruction, the 40 rows that were open at 07:20 UTC on 27 Oct 2026. Each row was measured against
production (project htdblwldjkcgjvmqkbeh), GitHub (PR state, integration PR bodies, scripts/sql/MANIFEST.txt on main
679bf9ef), the deployed edge-function bundles (Supabase management API, function body searched for the fix's own
identifiers) and the Vercel production deployment (dpl_D7RHjtaACDMaMd6nF1psqNEVMUYw = main 679bf9ef). Statuses were
written to the ledger in the same pass, each by `where id = <exact id>`. Rows still open carry a `RECON 27 Oct (ceo)` note.

## How "waits on PR #N" was settled

Most PRs named in the 19 Oct notes were **closed unmerged** and carried to main by the it_engineer integration PRs:
#1496 (merged 19 Oct 03:59Z: #1438, #1435, #1432, #1180), #1566 (round 4, 19 Oct: #1509, #1519, #1526, #1544, #1546,
#1547, #1552, #1553, #1565) and #1578 (round 5, 19 Oct 17:30Z: #1191, #1180, #1210, #1365, #1366, #1367, #1451, #1459,
#1506, #1516, #1523). Their SQL then received MANIFEST lines (2084-2117) and the routines were read live. Merged was not
taken as done: each closure below names the live object or the run that proves the acceptance.

## Counts

| outcome | rows |
|---|---|
| done | 9 |
| superseded | 6 |
| real gap (still open) | 21 |
| not touched (1312, 1313, 1314, 1315, as instructed) | 4 |
| total | 40 |

## Every row

| id | ask | verdict | evidence |
|---|---|---|---|
| 31 | Sales engineer reads every drawing format and understands its elements | real gap | Bench #1523 (via #1578): CAD/DXF/vector PDF/BOQ counts exact, 0 leaks; raster 4/7, scanned PDF 3/7, phone photo 1/7. Missing: native DWG entities, element F1 >= 0.95 on every format. sales_engineer. |
| 580 | Drawing test: count, redact, BOQ PDF, inquiry to suppliers | real gap | Bench proves per-file counts and 0 leaks only. Missing: one end-to-end ZZ DEMO run through to a routed inquiry and cleanup 0. sales_engineer. |
| 889 | Every agent's knowledge accessible and helpful | real gap | #1210 applied: knowledge_library live but 56 rows, read flag off (phase 1). Missing: phase 2 cutover. it_engineer. |
| 893 | Per-trade product distinctions to professional standard | real gap | Batches #1520-#1545 in; trade-tagged entries for all 223 trades. Missing: a measured exam result (seat_exam_asked 0 rows). sales_engineer. |
| 894 | Professional knowledge for every seat | real gap | Packs and #1565 checklist in. Missing: measured model-on exam per seat. ceo. |
| 899 | UAE market depth for every category | real gap | #1552, #1553, #1604 in (sales_engineer v308 carries the briefs). Missing: measured completeness for 223 trades. sales_engineer. |
| 900 | Find missing trades first, then build knowledge for the full list | done | taxonomy_trade 213 -> 223 (#1509 via #1566), services 1047 -> 1103; trade_spec_checklist 223 trades; trade-tagged sales_knowledge for 223 trades. |
| 1003 | Two-stage senior audit of every seat | real gap | Senior duties for ceo/it/sales/accountant in via #1566; #1549 (customer_support) and #1551 (marketing) OPEN; ceo_seat_audit 10 rows, newest 1 Oct. ceo. |
| 1005 | Build the sales engineer knowledge | done | trade_spec_checklist 223 distinct trades (19 Oct: 20); knowledge/seats/sales_engineer.json 121 entries = 121 EN + 121 AR rows in sales_knowledge. |
| 1013 | Upgrade round 2 (remaining: seat handover notes) | real gap | #1516 live; 570/570 handoffs in 7 days carry the four fields. fn_handoff_citation_gaps: 469 cited, 104 closed uncited. ceo. |
| 1027 | Reveal-conversion nudge | done | fn_sales_engineer_reveal_followup_tick live (MANIFEST l.2100); duty enabled every 6 h, last ok 27 Oct 04:20Z, 0 failures; cron run 07:30Z succeeded. |
| 1028 | Repeat a past request in one click | done | inquiries.repeat_of live (MANIFEST l.2109); customer_api v350 (27 Oct 02:40Z) bundle has repeat_inquiry; web prod on main carries "Request again". 0 uses so far. |
| 1084 | Model-on, reworded knowledge exam; every miss fixed | real gap | #1548 merged 27 Oct, but it runs on GitHub Actions (off, ledger 1279) and CLAUDE_CODE_OAUTH_TOKEN is unset. seat_exam_asked 0, seat_exam_fix 0; knowledge_exam duty disabled since 24 Sep. it_engineer. |
| 1092 | Finish all pending work | real gap | 17 PRs open (19 Oct: about 90); 78 probe notes in scripts/sql/pending. it_engineer. |
| 1113 | Campaign mail lands in the inbox | superseded | By 1312 (GlockApps from supplier@, Outlook >= 80% inbox). The placement gate reads pass on 6 two-seed rows, which is not that bar. |
| 1115 | Send invitations from the supplier@ M365 mailbox | done | invite_m365_mailbox = supplier@quotesdone.com, invite_m365_enabled = true since 19 Oct 14:18Z; 122 seed sends through m365 in 10 days, last 27 Oct 04:31Z. |
| 1121 | 10 + 10 ZZ DEMO stage-2 run, then clean | real gap | Run 0a717394 (26 Oct): 455 PASS, 33 FAIL, cleanup kept. it_engineer. |
| 1143 | Deep security audit | real gap | #1459 and #1506 in via #1578; #1505 and #1507 closed unmerged and absent from every integration PR; #1482 open. it_engineer. |
| 1152 | Who reviews an automated decision | done | review_route 14 routes over 5 seats (the founder is refused by a CHECK); fn_review_request_open live and wired into site_assistant, wa_inbound, email_triage, supplier_api, ceo_agent. |
| 1184 | Non-email supplier channels | real gap | WhatsApp invitation #1511 closed unmerged and absent from every integration PR. marketing. |
| 1199 | Purge all test data | real gap | Tests still running; demo tag 0a717394 kept 26 Oct. it_engineer. |
| 1200 | Adaptive expert conversations | real gap | Playbooks live; a 12-turn ZZ DEMO kept context. Missing: a scored scenario exam and a gap audit that runs (seat_exam_asked 0). customer_support. |
| 1209 | Knowledge pack + five daily/monthly tasks | real gap | Live: five numbers, licence 30/7, 24h quote promise (seatClocks ok 07:31Z), knowledge pack #1604. Missing: mystery shopper (#1370 open, no routine) and the monthly Claude gap fill. it_engineer. |
| 1214 | Named test folders and aliases in the purge | real gap | Waits on 1199. it_engineer. |
| 1230 | Campaign go-live with registration 100% | real gap | Sending half collapses into 1312/1313. Registration journey on ZZ DEMO is still a separate requirement, and stage-2 had 33 FAIL. it_engineer. |
| 1248 | Chat forgets the conversation | done | site_assistant v329 has chat_history/fitHistory/conv_id. ZZ DEMO widget conv v-192a94d6 (27 Oct 07:29-07:31Z): turn 12 restates "2 m high, 1.2 m wide, matte white, JLT" from turn 1. |
| 1250 | Inquiry box hidden | real gap | Fix merged and on web prod, but stage-2 26 Oct S26 inquiry_box FAIL ("could not open New request"). sales_engineer. |
| 1251 | Outlook seed and first send day | superseded | By 1312 and 1313. |
| 1252 | OTP cost too high | real gap | kyc v308 has sendWhatsAppFirst; 0 phone codes sent in 9 days, so cost is unmeasured; the WhatsApp auth template is not approved. it_engineer. |
| 1261 | Full three-person browser test, AI on | real gap | Stage-2 26 Oct: 33 FAIL. it_engineer. |
| 1273 | Turn the campaign on | superseded | By 1312 (paused 27 Oct; invite_enabled = false). |
| 1276 | Use the lane proven to land in the inbox | superseded | By 1312. |
| 1277 | Base the lane on the GlockApps trial | superseded | By 1312. |
| 1281 | Laptop-only memory, reports and evidence into the repository | done | #1598, #1625, #1626 merged; evidence bucket private, 2,918 objects / 2.23 GB; registry SQL live (MANIFEST l.2116). Covers what those PRs inventoried. |
| 1297 | Hold the batch pending a GlockApps re-test | superseded | By 1312. |
| 1298 | New invitation email approved | done | #1614 merged; SQL live (MANIFEST l.2117, trigger z52_invite_reply_reaches_sales_engineer); send_outbox v345 has m365Subject. |
| 1312 | GlockApps gate before invitations resume | not touched | As instructed. |
| 1313 | supplier@ warm-up | not touched | As instructed. |
| 1314 | No internal test email without his yes | not touched | As instructed. |
| 1315 | 27 Oct points saved to memory by PR | not touched | As instructed. |

## Seen in passing, not acted on

- In the last 10 days, notifications holds no supplier invitation of any type except `supplier_invite_seed` (124 rows),
  although ledger 1273 records the campaign as on from 20 Oct. The app_secrets row invite_enabled reads false with
  updated_at 19 Oct 14:05Z. This pass did not establish why. Owner: it_engineer, as part of 1312.
