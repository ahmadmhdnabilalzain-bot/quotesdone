# NEXT SESSION — FINISH THE CUSTOMER PORTAL, COMPLETELY, WITHOUT STOPPING

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Don't report the
OpenRouter balance, but DO tell me if it's refusing calls.

---

## HOW THIS SESSION RUNS — READ THIS FIRST, IT IS NOT BOILERPLATE

**Do not stop. Do not ask me a technical question. Do not report progress mid-session.**

The rule is in `.claude/skills/quotesdone-session/SKILL.md` §3 and it was added on 13 Aug because
the session before it asked me three times whether to release a work queue. In my words:

> "I'm not the expert. You are the one. You know my vision, my target, the plan. And still you're
> asking me technical questions… If it's something operational and it goes against my vision, then
> definitely ask me and stop whatever you're doing. But if it's something technical, what do you
> expect from me?"

**The test before you escalate anything:** would answering it require me to know something technical
about this codebase? If yes, I'm the wrong person — decide it, do it, and put the reasoning in the
commit. Escalate only: Stripe refunds, spending money, the three go-live switches, and anything
that contradicts my stated commercial intent.

**A line in an old brief saying "ask me first" is not a veto.** It's context about what I was
thinking that week. The skill wins on conduct.

**You are my partner and developer.** If something doesn't make sense, tell me what's actually going
on — don't route it back to me as a question.

End with one line — `all verified and fixed and merged and deployed 100%` — or an honest hand-over
naming exactly what is unfinished and why. Nothing in between.

---

## THE JOB: THE CUSTOMER PORTAL, FINISHED

I went back into `/me` after the last session and found things that should not have survived a
session that claimed to have clicked everything. Two of them below are mine, measured; the rest of
the surface is yours to walk.

### 1. There is a "Company profile" in the CUSTOMER portal. Why?

A customer is a person buying a service. A company profile is a supplier concept — trade licence,
products, services, catalogues. On a customer's screen it is at best noise and at worst asking for
personal or business data we have no reason to hold. **Work out what it is doing there, and either
justify it in a comment or take it out.** My instinct is: take it out.

### 2. The account screen showed the wrong e-mail — and it is an identity bug, not a display bug

I registered with one e-mail. `/me` → Account showed `management@quotesdone.com`. Phone was right.

Already measured on production, 13 Aug:

```
customers — no unique index on email, no unique index on phone. Only customers_pkey on id.

70f15bc3  ahmad test    djzaino@outlook.com            +971509319355   13 Aug
a6d900ab  ahmad test 2  management@quotesdone.com      +971509319355   13 Aug   <- same phone
```

Two rows, one phone number. The session resolved to the wrong one. So:

- **Find every place customer identity is resolved** (`customer_api` `action='me'` returns
  `{customer: cust}` — start there, then every sibling that looks a customer up) and establish what
  it keys on. If any path keys on phone, that path can return another person's account.
- **Decide the identity rule and enforce it in the schema**, not just in code. Unique on
  `lower(email)` at minimum. Phone is shared by families and colleagues in the UAE — decide
  deliberately whether it may repeat, and write the reason down.
- **The two rows above are mine and both are test registrations.** Merging or retiring one is a
  technical call — make it. Do not ask me which.
- Then walk registration again end to end and prove the account screen shows what was registered.

### 3. Walk the whole customer surface the way the supplier side was walked

Signed in as a real customer, in a browser, at **375 and 1280**, English and Arabic. Every tab,
every button, type in every field. On each screen ask the customer's question: **"why would I use
this?"** Screenshot before and after every change.

`djzaino@outlook.com` is fully open: phone and e-mail verified, terms accepted, `can_post_request`
true. The door is open — do not report it as closed.

**The chat widget is much better now** — it knows who it is talking to. Leave it alone unless it
breaks.

---

## AND THE PART I ASKED FOR AND DIDN'T GET: UPGRADES

Be honest with yourself about the split. The 13 Aug session merged **13 PRs and they were almost
entirely repairs** — real ones, but repairs. The only things that added capability were the
invitation landing banner, the sticky confirm bar, the market panel's competitive line and the
calendar guard on the invite ramp.

**This session: fix what's broken AND ship at least three upgrades to the customer portal.** Not
polish. Things that make a customer want to come back. You choose them — you know the vision. If
you want a starting point, the gap is that the portal tells a customer what happened but never
helps them decide:

- the comparison exists but nothing tells them *which quote to take and why*, in their own terms
- nothing shows them what a job like theirs normally costs in the UAE before they get quotes
- nothing follows up: a request goes quiet and the portal never says what to do about it

Decide, build, verify, merge.

---

## PENDING — EVERYTHING STILL OPEN, ACROSS ALL SESSIONS

### From 13 Aug (13 PRs merged, #328–#339)

| item | state |
|---|---|
| Supplier confirmation funnel | 5 defects fixed and live. **81 invited, still 0 registered.** The fixed door went live 13 Aug ~15:00; nobody has walked it yet. Re-measure. |
| Held handoffs | **Released** — 32 through the gate, 3 refused. Those 3 (ids 2571, 2787, 2891) need a human to do the work, not a decision from me. |
| s36 seven fields | Mechanism fixed — the filler trigger had never fired. Every NEW recommendation now carries all seven. The check is a rolling 30-day window, so it goes green around **13 Sept** on its own. Verify, don't rebuild. |
| `explain-alternatives-considered` (Row #3) | May now flip green as a side effect of the s36 fix. Check it. |
| Knowledge provenance | Fixed forward. **1,084 of 2,049 `agent_knowledge` rows still say `unattributed`** and `dropbox_asset:` citations are 0. A backfill re-deriving them from the topic patterns is worth doing — only where the pattern genuinely matches. Do not invent a citation. |
| Embedding backfill | ~27,000 unembedded, moving ~500/hr, ~2 days. Healthy. `kb_embed`'s `agent_runs` rows are a throttled 1-per-hour sample — do not read "embedded 0" as a stall. |
| Invite ramp | Cap raised 10 → 20; `fn_invite_ramp` governs it daily. Calendar guard now pauses invites on UAE public holidays — **the first is Mawlid, 25 Aug**. |
| `mdm_cities` | 18 rows, no reader. Decided: leave it. Not a finding. |
| Redaction retry | Still unexercised. The pack's own `redaction_detection` policy was tried and **measured harmful** — it made the verifier report identifiers off a solid black rectangle. Recorded at the call site. Do not re-adopt it without opening the JPG. |
| Vercel | Connector is back. `get_runtime_errors` works; the raw log query times out. 0 runtime errors over 7 days. |

### Older, still open

- **The 39 "cannot execute" executors are edge functions** and need one HTTP invoker. The executor
  table already has idempotency/timeout/retry/compensation columns and implements none.
- **Two queues, two vocabularies** — pending `agent_actions` cannot be drained by the executor path,
  and `org_tasks` is hundreds deep at ~3/hour.
- **WhatsApp is my command channel.** I want to run the company by texting my registered number —
  any request, not a fixed command list.
- **The OS dashboard is still basic.** I said so on 10 Aug and it hasn't changed. My judgement of
  that screen outranks its score.
- **Apify is paused until ~Feb 2027.** Supplier scraping is deliberately off. Work the existing
  20,470 leads. `s26-discover-suppliers` must NOT be "fixed".
- **Row #3: 130/152.** Still NOT MET: employee-knowledge-used, exec-meeting-priorities-agreed,
  time-machine-scrub, time-machine-restores-six-dimensions, personalization-learns-founder-habits,
  explain-alternatives-considered, intel-customer-behavior, company-map-entities,
  what-if-projected-deltas, what-if-confidence-score, employee-current-thoughts,
  employee-performance, employee-learning-progress, s22-graph-navigation,
  s23-reallocation-three-classes, s24-board-before-major-decisions, s26-discover-suppliers,
  s29-scan-five-questions, s30-marketplace-eight-inputs, s32-reputation-six-dimensions,
  s34-stress-six-scenarios, s36-recommendation-seven-fields.
- **Row #4: 146/147.** The one red is §21's `ui-not-sidebar-pages-tables` and the single hit is the
  docked assistant's `<aside>`. **The sidebar is approved. Do not remove it and do not rename that
  element.**
- **3 go-live switches still false.** Mine to flip.

---

## STATE (13 Aug ~20:00 UTC)

Row #3 130/152 · Row #4 146/147 · portal gates **23/23 on BOTH** · `project_parity` **BOTH PROJECTS
IN SYNC** · main CI green including `deploy edge functions` · **165/165** tests · 199 edge functions
ACTIVE · 3 customers · **0 inquiries** · 0 quotes · 1 confirmed supplier capability · 81 leads
invited, 0 registered · 3 handoffs held · AI spend 13 Aug AED 18.71 · knowledge corpus 115,148
records reconciled against disk, 0 missing.

**Do not fabricate an inquiries row.** Drive fixture rows by patching `window.fetch` in the browser.

---

## RULE ZERO, EARNED FIVE TIMES NOW

A grep of a component is evidence about a file, not about a screen. Before you say one word about a
surface I will look at: **render it, screenshot at 375 and 1280, signed in as the actual role.**
Then again after every change.

**And on 13 Aug this earned a sixth corollary: open the artefact.** Three separate "findings" that
day inverted the moment the actual thing was opened — a vision verifier listed eight identifiers it
"could still read" off a solid black rectangle; an auditor reported a 16,608-record hole that was
two id shapes summing to exactly the disk count; a backfill "embedding 0" was a throttled log
sample. On this codebase **the instrument is wrong about as often as the thing it measures.** Open
the image, sum the keys, read the header.

---

## SIGNING IN WITHOUT E-MAILING ME A CODE

Insert into `email_verifications` with
`token_hash = encode(hmac('<code>', (select value from app_secrets where key='otp_hmac_key'),'sha256'),'hex')`,
`purpose='login'`, then POST `login_otp {action:'verify',user_kind:'<customer|supplier>',identifier:'<email>',code:'<code>'}`.
Put `access_token` in `localStorage['qd-cust-token']` (customer) or `qd-sup-token` (supplier) **and
the refresh token beside it** in `qd-cust-refresh` / `qd-sup-refresh` — without it you get signed
out after an hour and will waste time thinking that is a bug. For `/os`, set the Supabase client's
own key: `sb-htdblwldjkcgjvmqkbeh-auth-token` with a full session JSON.

---

## TRAPS

`apply_sql --promote` carries the DEFINITION not the GRANTS — use `--promote --ddl`, and a file
whose only change is inside a DO block promotes 0 routines; assert md5 on both yourself · a new
table gets RLS on production by event trigger and NOT on staging · an LLM error string is written by
our own catch block — check `latency_ms` first · `least()`/`greatest()` ignore NULLs · `_` is a word
character in Postgres regex · **BEFORE triggers fire in NAME order** — this cost two separate
features that had never once executed · a cron reporting succeeded for a `net.http_post` only means
QUEUED · HTTP 546 kills the isolate · `net.http_post` in a DO block never fires · `onClick={fn}`
passes the MouseEvent as the first argument · a count reached by subtracting the reasons you thought
of is a count of the reasons you did not · **ask whether a condition can ever NOT fire, and whether
it can ever fire at all** · a CI failure reading `Failed caching npm package` is infrastructure;
re-run it · **a scorer whose input vanished reports perfection — assert the population is non-empty
before believing a zero** · NEVER push to main.

---

## THE BAR

Deploy to BOTH Supabase projects (htdblwldjkcgjvmqkbeh production, pglpqrhvozwepymcuunn staging),
merge via PR, verify by execution in the same turn, aborted-transaction probes for writes, never
fabricate or back-date data to turn a gate green, never weaken a check, never rename an element to
dodge one.

Run the end-of-session sweep — Actions · Vercel · both Supabase · Row #3 · Row #4 · pack scorecard
both · `fn_os_portals_gates` both · `project_parity` → BOTH PROJECTS IN SYNC — and only then the one
line.
