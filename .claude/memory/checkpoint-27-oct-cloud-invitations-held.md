---
name: checkpoint-27-oct-cloud-invitations-held
description: "27 Oct 2026: work runs in the cloud and the laptop holds no keys; supplier invitations are paused until GlockApps shows Outlook at 80% inbox or more; GlockApps 27 Oct FAILED (Microsoft 0/18), copy now variant A, re-test 4 Nov; warm-up plan; internal test email needs his yes; 16 open PRs by state"
metadata:
  node_type: memory
  type: project
  modified: 2026-10-27T06:00:00.000Z
---

**READ FIRST in the next session.** Founder instructions 1312–1315 (27 Oct 2026).

**Cloud only.** As of 27 Oct 2026 the laptop has been fully moved to the cloud and holds no keys.
Start every session with `bash scripts/cloud/setup.sh`. It installs node 24, deno, the supabase CLI
and gh, and checks the required variables. `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` come
from the environment. Never ask him for a laptop path or a laptop key.

**Invitations are HELD (1312).** `invite_enabled=false`, set at 09:52:42 Dubai on 27 Oct by
`fn_invite_campaign_pause('it_engineer', …)`, eight minutes before the 10:00 window. 0 rows were
queued. `supplier_outreach_golive` is still true, and so is his go. `invite_warmup` also holds
`window_start_hour=10`, `window_end_hour=10`, a zero-width window. Resume only when a GlockApps test
from supplier@quotesdone.com (M365 lane) shows **Outlook at 80% inbox or more**. Report inbox, spam
and promotions for each provider. Resume steps are in
`docs/reports/QuotesDone Campaign/SUPPLIER_WARMUP_PLAN_27_OCT.md`.
0 real `supplier_invite` rows have ever been sent.

**UPDATE, later 27 Oct: GlockApps RAN and FAILED.** Test `id:2026-10-27-09:33:53:634t` (founder-supplied): Microsoft
**0 of 18 inbox** (Outlook US 0/8, .fr 0/1, .de 0/1, Hotmail 0/6, Exchange/O365 0/2). Gmail was all Promotions,
Yahoo/AOL all spam, 39.6% inbox overall. SPF, DKIM (selector1, d=quotesdone.com) and DMARC pass, with no blocklist. The
"HELO to IP" fail is Microsoft's own host. Invitations stay held. It is recorded as a note on the 27 Oct
`invite_placement_check` row (that table is the daily seed and cannot hold per-provider rows) and on ledger 1312.
Diagnosis: the main cause is reputation, because supplier@'s whole history is 317 seed sends to strangers and no
conversation. Report: `docs/reports/QuotesDone Campaign/GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md`.
- **Copy is now variant A**, "one question, no offer": `app_secrets` and `m365_lane.ts`. The founder delegated the
  choice ("approved. dont ask me").
- The lane sends **quoted-printable** and at most **5 per run**.
- **The received copy (Gmail, raw) carries a `winmail.dat` TNEF attachment and has lost `List-Unsubscribe-Post`.**
  Fix: Exchange admin center → Remote domains → Default → rich-text **Never**. This needs the founder's M365 admin
  sign-in; Graph cannot set it.
- **Warm-up is COMPRESSED** (the founder: "we cant wait for a week"):
  - day 0 DONE Tue 27 Oct 15:16Z: supplier@ wrote to his 5 mailboxes, and he is replying;
  - Wed 28 / Thu 29 / Fri 30 Oct: ~10/15/20 person-to-person messages;
  - **re-test Fri 30 Oct, from 13:00 Dubai, with the LAST GlockApps credit** (balance 1), through
    `deliverability_test`. It moves to Mon 2 Nov if TNEF is still on or the replies are thin.
  - A pass is possible, not likely. If it fails, there is no credit left, and a top-up is his spend.
- **The internal management@ → supplier@ test email (1314) is DROPPED.** It is noted on ledger 1314 and is not a
  prerequisite.

**(Superseded by the update above.) GlockApps is NOT yet run.** The cloud network policy refuses app.glockapps.com and
api.glockapps.com (proxy 403), and no GlockApps API key is stored anywhere. Either he adds those
hosts under the environment's Network access (Allowed domains) and stores an API key as an
environment secret, or he creates the test in the dashboard and gives the seed list and test ID.
The seed send then goes as `kind='invite_m365_seed'` rows, as on 5 Oct (110 seeds;
`scripts/invitation_inbox_check.mjs` refuses gmail.com and similar seeds by design). Credits: 3
were bought (ledger 1120). Count what is left in the dashboard rather than assuming.

**The 27 Oct morning seed** reached the inbox of both test mailboxes, but:
- Gmail was in the **Promotions** tab.
- The Outlook mailbox is in our own tenant. The mail was unsigned and internal (`dkim=none`), so it
  proves nothing about external Outlook or Hotmail.

That gap is why GlockApps decides.

**Warm-up (1313).** The plan is in the report above: week 1 is two-way conversation only, week 2
is 10–15 invitations a day, week 3 is 20→40, then the 50 ceiling. Day 1 is the internal test email.
He said yes on 27 Oct, but it is not sent yet: there is no path that sends as management@. See
[[ask-before-the-internal-test-email]].

**16 open PRs on 27 Oct:**
- Waiting on fixes: #1182, #1193, #1369, #1370, #1574.
- Need review: #1434, #1436, #1549, #1551, #1571.
- On hold, do not merge: #1392, #1482.
- Dependency bumps: #1201, #1224, #1421, #1595.

That grouping is the founder's, given at the start of the session. **Later on 27 Oct**, agents fixed #1182, #1193,
#1369 and #1574, and the independent reviewer called them ready to merge. #1370 still has one blocker: its intake uses a
fixture, not the AI interview. Before quoting any PR state, read the PR's latest review, and read the open-PR count
again rather than copying this one.

Related: [[checkpoint-19-oct-campaign-on-pr-drain]], [[supplier-campaign-sends-from-supplier-at-quotesdone-com]], [[a-status-column-is-not-a-delivery-record]]
