---
name: checkpoint-2-nov-10-hour-push
description: "2 Nov 2026 night: founder's 10-hour push. READ FIRST: rulings 1437-1458, what is live, the PR queue and its order, what is unproven"
metadata:
  node_type: memory
  type: project
  modified: 2026-11-02T02:00:00.000Z
---

**READ FIRST.** The ledger (`public.founder_instruction`, ids 1416+) is the checkbox list: a row closes only with proof and the check that stops a repeat (1439, 1451). The audit is `docs/reports/WHOLE_PICTURE_AUDIT_2_NOV.md` (branch `it_engineer/whole-picture-audit-2-nov`); the placement plan is #1742.

**Standing rulings from this night.** The founder is an investor: he sets targets, the CEO seat owns the plan and acts, and only missing access goes back to him (1438). Target: 300-400 registered suppliers by 31 Dec. All company mail reaches the agents, on the server, never through a session or the laptop (1437, 1452). At most 5 agents, Sonnet for simple work (1417). All browser work in his Edge (1422). The cap is the CEO seat's call on measured health, brakes always win (1455). No ads or boosted content until suppliers exist (1456). GitHub Actions rehearses and applies reviewed SQL, no asking (1458). He does not want to open a new session or repeat himself (1454). Never fabricate engagement: no fake mailboxes.

**Live and verified.** #1713 (no second ask after a reply), #1740 (no guessed trade; mailed bounces recorded), #1741 (server reads every company mailbox; strangers stay off until `app_secrets.m365_tenant_strangers_from` is set, by decision, after watching first runs), #1744 (checked mailboxes only, brake restart rules; applied through `apply-sql.yml`, read back). `fn_mail_sender_known` reads claimed_by. 7 dead addresses suppressed by hand.

**How to apply.** `gh workflow run apply-sql.yml --ref <branch> -f file=... -f probe=... -f seat=... -f apply=false` to rehearse the whole file on production, rolled back. After review and merge, run the same with `--ref main` and `apply=true`. Dispatch it alone in one command: bundling it with other steps was refused by the permission layer. Never pass --skip-release-guard; it is refused too. Probes must raise CHK<<...PROBE OK...>>. The long `checks` job is red on main (14-16 failures, stale pins): compare a PR's failures with main's by `gh run view --log-failed` and merge when nothing is new. Those failures still need fixing. After applies the schema mirror needs regenerating (`export_from_either_source_is_identical.mjs --write`, needs a token, so run it in Actions).

**Queue, in order.** (1) #1746 queue owners and the Al Gouri rescue: review fixes done, rehearsal under way; needs merge, apply in the order in its report, deploy. (2) #1745 sign-up rules plus `supplier-document-walk.yml`: rehearsals pass, final re-review running; after apply, dispatch the walk (approved, ledger 1457): the first real proof of document reading. (3) #1743 CEO powers, rebuild on merged #1744, re-review, apply, then switch `ceo_daily_number_golive` and `ceo_growth_act_golive` on. (4) #1742 report merge, then its actions. (5) Audit report merge. Close the ledger with proof.

**Al Gouri (lead 19398, info@algouri.com, claimed_by sales@algouri.com).** Real supplier, verified email and phone 30 Oct, stopped before the licence. Replied to our answer: wants to register subsidiary TECH AXIS FZE LLC. inbound_messages 1615 has a good draft but the worker died in answer(); #1746 re-opens it. True answer: a separate licensed company registers with its own licence and a different e-mail. A registration reminder is due Monday 09:00+ Dubai on its own. Close 1444 and 1434 only after seeing the sent row.

**Deadlines.** GlockApps result expires 3 Nov ~22:50Z, then all invitations hold: run one test before it (3 credits, plan in #1742). Mail to Microsoft and Yahoo stays closed; first contact by opt-in. First real send Monday 2 Nov from 10:00 Dubai: check it. Reminder wording is generic; v17 terms needed to remove the founder's mobile from signed terms.

**Honest numbers.** 52 real invitations, 7 bounced, 1 reply, 1 started, 0 submitted, 0 approved. Cold email maximum about 39 starts by 31 Dec. Do not tell him the sign-up is valid until the walk passes.
