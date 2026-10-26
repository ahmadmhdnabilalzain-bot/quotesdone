---
name: upgrade-backlog-after-queue-zero
description: "Ledger 1019: the agent upgrade backlog as the founder trimmed it on 29 Sep — build once open PRs = 0; order T1, T3, T2, then the rest by audit"
metadata:
  node_type: memory
  type: project
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-30T10:50:59.217Z
---

Founder, 29 Sep 2026, trimmed the backlog; "keep them in the ledger for later". Build only when `gh pr list --state open` = 0, after round 3 (ledger 1018, gated at < 20). Order: T1, then T3, then T2; T4–T7 adjusted by the post-merge audit. Max 10 agents; apply at merge, never before.

**T1 revenue core:**
- stalled-inquiry rescue (round 3)
- quote QC before the customer sees it (round 3)
- project splitting: ASK THE CUSTOMER FIRST whether they want one contractor for the whole job or separate trade packages. The default is one contractor. Never split a renovation automatically into many suppliers.
- supplier clarification Q&A shared with every bidder
- reveal-conversion follow-up
- repeat requests in one click

**T2 customer:**
- first-request concierge (round 3)
- live request tracker
- spec helper in plain questions
- post-job review with photos

**T3 supplier:**
- capacity and availability (round 3)
- profile score
- quote templates and BOQ upload (NO reusable price lists)
- verified badges
- win/loss feedback to suppliers

**T4 seat intelligence:**
- fraud and risk screening (round 3)
- quarterly knowledge refresh
- 30/90-day demand forecast
- contact deduplication
- monthly Arabic quality review

**T5 growth:**
- monthly UAE market report, INTERNAL ONLY, for us, never published to customers
- getting cited in AI answers about QuotesDone and how it works only; NEVER name suppliers

**T6 finance and ops:**
- invoice capture and matching
- founder budget-owner view per seat
- investor data room
- legal and compliance calendar

**T7 platform:**
- disaster recovery drill twice a year
- quarterly security testing
- portal usage analytics
- mobile / installable web app

**REMOVED by the founder:**
- negotiation / best-and-final rounds
- enterprise account plans
- reusable price lists
- trade association partnerships (using associations as recruitment SOURCES in #1070 is different, and stays)
- website page per category
- customer case studies (the learning loop covers this)

**DEFERRED:** customer referral programme, not before Jan 2028.

**Why "never name suppliers":** revealing which suppliers can do a job gives away the reveal fee, which is the revenue model.

**The post-queue plan, approved 29 Sep 2026 (ledger 1057), runs in this order:**
1. Verify, and re-run the senior-hire audit.
2. Build this backlog.
3. Run the full end-to-end sandbox test. It must prove go-live readiness, because right after it he lifts the hold and starts the campaign.

If the proper test needs the AI hold lifted, tell him BEFORE the test; he decides. My recommendation to him: lift the hold only for sandbox (ZZ DEMO) traffic, with a spend ceiling, and quote the measured cost first.

**FROZEN until the week of 5 Oct 2026** (founder, 29 Sep): his weekly usage was at 70% and the launch comes first. Finish the PRs in flight, then run steps 1 and 3 (the audit + the sandbox E2E). Build nothing new beyond those fixes. Step 1 also includes ledger 1063: no task, duty, cron job or routine is left without an owning agent, and none sits under the wrong agent according to [[seat-ownership-map-24-sep]]. Fix every case found.

**Week of 5 Oct, knowledge and exams (ledger 1084 and the knowledge-restructure row):**
- **One knowledge library:** merge kb_chunks, support/ceo/sales knowledge and the seat packs; trim the 8 GB bulk; switch to a bilingual Arabic+English search model (gte-small is English-only); tag every entry by trade, seat, language and source.
- **The AI-on answer exam:** fresh wordings every run; a cross-family grader against the source key; every miss becomes a fix loop run by the owning seat; real mistakes become exam questions. Retire the retrieval-only daily exam, and keep only a free daily index-health check.
- **The "no source, no answer" audit** for every customer-facing AI reply.

**Dependency upgrades, week of 5 Oct.** PRs #1120, #1121 and #1122 were closed on 30 Sep with their reasons. They were held by my own technical call, not the founder's.
- Tailwind v4, together with tailwind-merge 3.
- recharts 3, with a visual check of the charts.
- @types/node 24.x, to match the runtime.

Related: [[round-3-upgrades-wait-for-queue-below-20]], [[the-only-hard-rules-and-operating-doctrine]].
