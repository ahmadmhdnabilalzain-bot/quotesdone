---
name: checkpoint-3-nov-handover-week-of-4-nov
description: "READ FIRST 4 Nov onward: what went live 3 Nov, the open PR queue with each one's next step, invitations exclude Yahoo/Microsoft, the founder's week (invitations + registrations, replies must work)"
metadata:
  type: project
---

Written 3 Nov 2026, 17:30 UTC, by the session that ran 2–3 Nov. The founder had 9% of his plan left; he asked that
"nothing need to stop", everything we have be merged, and a note left so next week carries on.

## The founder's week (founder_instruction 1537, 3 Nov)
- Supplier **invitations are sent this week** and suppliers register. **Email replies must work perfectly.**
- **Invitations exclude Yahoo and Microsoft.** Measured 3 Nov: `fn_invite_placement_judge` holds `microsoft` and
  `yahoo_aol` (GlockApps test 2026-10-27, max_age 30 days, so it holds until ~26 Nov; the auto re-test PR #1649 is
  NOT merged). 0 invitations went to those providers in the 8 days to 3 Nov; all 92 went to company domains.
  **First job next week:** make the exclusion explicit and permanent (it must not depend on a test verdict):
  in `fn_supplier_invite_candidates`, skip a lead whose `fn_mail_provider_class(domain, null)` is `microsoft` or
  `yahoo_aol`. Domain only, so a company that runs on Microsoft 365 is still invited; that reading of "Microsoft" is
  ours, so confirm it in the report. 2,390 not-yet-invited leads are on those domains, against 17,823 on others.
- Replies: 3 inbound replies sent from supplier@ in the 7 days to 3 Nov (the Hindco path, #1834); 35 support_reply
  rows `skipped` (reason not inspected, likely demo: check first thing).

## Live on 3 Nov (merged, applied, read back, deployed)
- #1846: account active (customer and supplier) and the reveal invoice on email and WhatsApp. Four WhatsApp templates
  (`customer_account_active`, `customer_reveal_invoice`, en and ar) were submitted to Meta 3 Nov ~16:40Z, status
  `received`. Check `messaging_template` for approval; until then the WhatsApp copies wait up to 24 h and the emails go.
- #1848: model waste fixed in code (tagged tests, CEO duty on the easy tier, no paid re-ask for our own work,
  postmortem templates, the public_site exact-prompt cache, every billed call on the ledger, the unattributed-spend
  finding). **No spend cap**: the founder's 24 Sep ruling. A cap was briefly in the PR and was removed.
- #1849: every chat reply carries a ~21k core plus one trade pack (brief cap 40k) instead of the ~140k brief. The
  savings are estimated, not measured: **measure prompt_tokens per surface from ai_cost_log on the first real days.**
- #1843, #1847, #1850: schema mirror regenerations. Every apply that adds a routine or a cron job makes the mirror
  stale and turns `export_from_either_source_is_identical` red on every open PR. Regenerate with
  `regen-schema-mirror.yml` on a branch cut from main, then add an empty commit so the checks run.

## Open PRs and each one's next step (3 Nov 17:30Z)
| PR | What | State | Next step |
|---|---|---|---|
| 1851 | mirror after the openrouter_unattributed cron | auto-merge armed | none, unless it failed |
| 1844 | WhatsApp inquiry reads own requests and every loop closes | 2 DB reviews clean, all findings fixed | auto-merge armed; if not merged, merge main and merge when green |
| 1830 | chat-quality eval and language/brief fixes | merged with main; brief worst case 39,864/40,000; review 3 Nov found 3 issues | **do not merge as is.** (1) `.github/workflows/conversation-quality.yml` push trigger would start paid 9-job runs (~USD 19.5) on any branch that merges main: delete the `push:` block, dispatch only. (2) `chat_answers.ts` `langOf`: a message with no letters (`14`, a phone, `OK`) flips an Arabic chat to English, and `replyLanguageProblems` then forces English; keep the established language unless the message has letters in one script only, and add `turnLang('14','en',arabicHistory)==='ar'`. (3) the per-sentence language check refuses the published contact line and English specs inside Arabic replies (`site_assistant/reply_check.ts`, `sales_engineer/index.ts`); run `replyLanguageProblems` on the whole reply only. Minor: CITES_BRIEF matches "the brief does not mention a street address"; the portal reads language from the browser's history, not the stored turns; `wa_inbound` ~1483 held notice uses the old any-Arabic rule |
| 1838 | identity never leaks before reveal | 2nd review: loosening REOPENED leaks (sign-off without comma, hyphenated or capital names, CN- 6 digits, ذ.م.م names, (+971)) | fix agent was running; **do not merge f175775c**; merge only after an adversarial re-review |
| 1837 | CAD dispatch, drawings model-first, quote review | review: model output can overwrite the code count, weaker identity terms, unbounded re-dispatch, a narrowed guard test | fix agent was running; github_token's Actions-write scope unverified |
| 1833 | 300-page profile and real-profile document eval | CLEAN, green | needs an independent code review (supplier_trade_choice, supplier_api catalogue hook) before merge |
| 1832 | prompt-injection corpus | CLEAN, green | needs a review before merge |
| 1795 | browser journey reveal notifies both | green-ish | review, then merge |
| 1792, 1784 | M365 delivery evidence; stage 2 re-measure | DIRTY | merge main, resolve, review |
| 1840–1842, 1845, 1703, 1636 | cloud-session PRs (`claude/*`) | not reviewed by this session | read each, review, merge or close |
| 1802–1805, 1824 | dependabot | | review the majors; setup-node/checkout v7 may need workflow edits |
| older (1392, 1482, 1643, 1649, 1710, 1718–1724, 1778, 1780) | | stale | decide each: rebase via merge, or close with a reason |

## Lessons from this session
- **Prove a rehearsal with the real file.** An agent rehearsed a trimmed copy and missed a jsonb LIKE error that CI
  caught (#1844).
- **`--write` on the Arabic register deletes other PRs' entries.** Merge it as a union.
- **Source-match tests break on harmless refactors.** Fix the code or teach the test; never loosen the guard.
- **Never build a spend cap** (24 Sep ruling), even when asked to save money. Fix the code that spends.
- OpenRouter: test volume was the bill (WhatsApp exchange looped 48 times untagged; the document load test ran 12.7k
  calls). Run each harness once per change.

Related: [[checkpoint-2-nov-10-hour-push]], [[idle-llm-spend-max-two-dollars]], [[supplier-campaign-sends-from-supplier-at-quotesdone-com]].
