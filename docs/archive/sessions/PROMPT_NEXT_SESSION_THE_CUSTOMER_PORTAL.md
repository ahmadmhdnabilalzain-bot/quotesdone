# Next session prompt — finish the customer portal

Copy everything below the line into a new session.

---

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Don't report the
OpenRouter balance, but DO tell me if it's refusing calls.

**THE JOB THIS SESSION: FINISH THE CUSTOMER PORTAL, FULLY, FROM ALL ASPECTS.** I registered as a
customer on 13 Aug and opened it, and it is not what we are claiming to be. We say we are the
smartest procurement company in the world. **Think of yourself doing an upgrade for a company like
Oracle — that is the standard, at least.** Visuals AND functionality. I want to open the customer
portal and be amazed.

**You may use v0 by Vercel — I am subscribed** and the v0 MCP tools are available to you
(`createChat`, `sendChatMessage`, `getPreview`). Drive it yourself.

**DEPLOY EVERYTHING TO PRODUCTION.** Nothing sits on staging. Staging exists only because `qd_guard`
refuses direct production writes — apply there, read the definition back, post it to production,
assert md5 on both. If you tell me something is done, it is live on `htdblwldjkcgjvmqkbeh`.

Read `docs/sessions/HANDOVER_2026_08_13_THE_QUEUE_AND_THE_DOCUMENT.md` — nine sections and two
addenda. The addenda are this job.

---

## RULE ZERO, EARNED THE HARD WAY LAST SESSION: OPEN IT IN A BROWSER.

I asked the last session whether it had used the browser, Agent Reach or Playwright to check the
portal. **It had not.** It answered a question about the portal's layout by grepping
`CustomerPortal.tsx` and describing the field order out of the JSX — correct about the file, silent
about the page. **All three defects below are visible in ten seconds on the rendered page and
invisible in the source it read.**

A grep of a component is evidence about a file, not about a screen. Before you say one word about a
surface I will look at, render it: `preview_start`, `read_page`, screenshots at mobile (375) and
desktop (1280), signed in as a customer. Then again after every change.

---

## WHAT IS ALREADY MEASURED — do not re-derive it

- **`/en/me` renders the portal BARE.** `src/app/[locale]/me/page.tsx` is three lines and adds no
  shell. `src/components/me/CustomerPortal.tsx` is 1,046 lines and has exactly two tabs, *Sign in*
  and *Create account*. **There is no supplier surface inside the portal.**
- **The irrelevant tabs are `src/components/SiteHeader.tsx`** — one static, audience-blind nav
  rendered on every page including the signed-in portal:
  `/#how` · `/#why` · **`/portal` (Suppliers)** · `/blog/`.
  Two defects in one array: `/#how` and `/#why` are anchors on the HOME page, so on `/me` they
  scroll nowhere; and `/portal` invites a customer into the supplier portal.
  **The fix is not deleting items. It is that the array has no concept of audience.** A signed-in
  customer needs their own navigation. The data to decide exists client-side (the portal holds the
  session) and server-side (`fn_identify_contact`).
- **The registration flow works** — I completed it. 1 customer, `email_verified` true.

## THE THREE TRACKS

### 1. Information architecture and navigation
Audience-correct nav, and then the actual question: what should a customer's portal *contain*?
Today it is a profile form plus a request list. A procurement customer wants their requests, the
quotes against them, a comparison, the reveal decision, their documents, their account. Design the
IA, do not just filter a menu.

### 2. The assistant — "a dumb chat bot", and that is my words
It cannot answer many questions and some replies are horrible. **Diagnose before rewriting.**
`wa_inbound` received `fn_wa_context` on 13 Aug and now answers from live, SQL-scoped data — the
site widget may still be on the older FAQ-and-facts prompt with no live context at all, which would
explain "cannot answer" exactly. Find the widget, compare the two paths, and give the customer-side
assistant the same live scoping. `fn_wa_context('customer', …)` already returns a customer's own
inquiries, suppliers-received, quotes-received and a **rounded pre-reveal band only** — never
individual quotes, never a supplier name. Keep that rule.

### 3. The visual design
"Extremely basic, felt so static and super outdated." This is where v0 earns its keep.

## TWO THINGS GENERATED MARKUP WILL QUIETLY DESTROY — hold v0 to them

1. **RTL/Arabic bidi isolation.** Phone numbers, emails and URLs are wrapped in U+2066/U+2069 so
   they do not scramble inside Arabic text. The portal is bilingual; half the UAE market reads the
   Arabic.
2. **The a11y fixes of 5 Aug**, commented in the file around lines 525–533: a bare `<div onClick>`
   was given `role="button"`, `tabIndex`, `onKeyDown` and `aria-expanded`. Do not regress it.

Amazing and inaccessible in Arabic is not the standard I asked for. Adapt v0 output onto the
existing shadcn primitives (`Card`, `Button`, `Input`, `cn`, the `S.` class objects) — do not paste
over them.

## THE DOOR IS STILL SHUT, AND IT IS MINE TO OPEN

`create_inquiry` refuses until `customers.phone_verified`. Mine is still false. On `/en/me` the
mobile field is the second in the profile card (`Mobile (05x xxx xxxx)`), and **the Verify mobile
section only renders once name + phone + DOB are saved** — press *Save details* first, then *Send*.
My number is **+971 50 931 9355** (proven SMS-deliverable; Twilio shows an SMS Approved to it on
14 Jul). Every route to send and check the code needs a signed-in session as me, and terms
acceptance writes a signed PDF certifying *I* accepted — **do not do that one for me.** Tell me when
you want me on the screen. **Do not fabricate an inquiries row.** Intake
`18e2c133-f728-464a-b5f1-43d1f9dc3c1e` reaches lead 30466 MERIDIAN MEP at score 5.0 once it opens.

## STATE AT HANDOVER (13 Aug, 00:45 UTC)

Row #3 **128/152** · portal gates **23/23 both** · parity **BOTH PROJECTS IN SYNC** · main CI green
including `deploy edge functions` · Vercel 0 runtime errors · 9 PRs merged (#294–#303) · 1 supplier
· 1 customer · **0 inquiries** · 3 go-live switches false · AI spend ~AED 19/day.

Built and proven on 13 Aug: the dispatcher's `notifies_human` gate, a 105s worker timeout (9/9
succeed where 8 of 10 aborted), `agent_action_kind_policy` (kinds can now answer "unrouted"),
`fn_founder_queue` (**27 decisions waiting on me, oldest 35 days** — now in the WhatsApp context and
the daily brief), WhatsApp media-in (a trade licence updates the lead), PDF out, supplier
price-change writes, a two-attempt retry that recovered 9 of 10 sentenced rows, and handoffs that
state their assumptions, alternatives, impact and cost.

## STILL OPEN, in priority order after the portal

1. **Drawing redaction yields 4 of 6 pages**, so no drawing reaches a supplier. BoQ extraction is
   excellent. A blanket right-22%/bottom-12% mask was measured and gives 4/6 either way — do not
   repeat it. The verifier's own words on what remains: a triangular firm logo bottom-right and a
   REVISIONS block. Repro: `node scripts/staging/prove_boq_real_drawing.mjs <pages.json> [pdf]`.
2. **39 `agent_actions` in `needs_review` that nothing drains.** The writer is `trg_action_gate`, an
   authority gate — so this is a security decision, not neglect. But **28 of the 39 are plain
   handoffs from `docs` to `it`**, and it is not obvious why a documentation handoff needs an
   authority escalation. Start at its `action := case` mapping and `fn_should_escalate`.
3. **The invite ramp**, once ~20 named-human sends have accumulated (13 as of 13 Aug, cap 10/day).
   Role addresses bounce at 8.6% (5/58), named humans at 0% (0/13), and every bounce predates the
   role-last ordering. If the named rate holds near zero, make the throttle read the segment being
   sent rather than the blend — **with a minimum-sample floor for warming up that the code lacks.**
   Do not act on 13 sends. MX is not the answer: all five bounced domains resolve (Google, Outlook,
   Hostinger).
4. **7 of the 22 unread tables** — `ai_quality_snapshots` (1,167), `scenario_expectation_baseline`
   (3,324), `internal_credential_audit` (1,760), `marketing_library`, `catalog_subcategories`,
   `subcategory_agent_map`, `field_definition`.
5. **10 pack artefacts have no source file** (not 6 — the brief was wrong). All 10 probe IN USE.
   File recovery, not engineering.
6. **`s36-recommendation-seven-fields` cannot pass before mid-September** — a rolling 30-day window
   over historical rows. The last live non-compliant writer is fixed. Check the newest rows, not the
   writers.

## TRAPS — do not rediscover

- **`apply_sql --promote` carries the DEFINITION, not the GRANTS.** Use `--promote --ddl`, and
  re-run `project_parity` after any new SECURITY DEFINER function. A file whose only change is
  inside a `DO` block promotes **0 routines** — assert the md5 on both projects yourself.
- **`ai_gateway`'s cache does a semantic lookup at 0.95** over a window a large system prompt
  dominates. Any classifier whose system prompt dwarfs its input gets the previous call's answer.
  Pass `cache_ttl_min: 0` on every classifier.
- **A new table gets RLS on production by event trigger and NOT on staging.** Declare
  `enable row level security` in the DDL or parity fails.
- **An LLM error string is written by our own catch block.** "The model returned nothing" was ten
  client-side aborts at 72s. Check `latency_ms` against the caller's timeout before believing it.
- **A pair of allow/deny lists cannot say "nobody decided".** Ask what the code does with a value in
  neither, and make that case loud.
- **`least()`/`greatest()` ignore NULLs · `_` is a word character in Postgres regex and a
  single-char wildcard in LIKE · BEFORE triggers fire in NAME order · a cron reporting `succeeded`
  for a `net.http_post` only means the request was QUEUED · HTTP 546 kills the isolate so the
  function's own catch never runs · `net.http_post` inside a `DO` block never fires (it dispatches
  on commit).**
- **NEVER push to main.** Everything through a PR.
- A CI failure reading `Failed caching npm package …` is infrastructure. Re-run it.

## HOW I WANT THE SESSION RUN

Do not check in. Do not send progress updates. Take the next item. I decide three things only:
Stripe refunds, spending money, and the three go-live switches — **and a mailing list is not one of
them; measure it instead of asking me.** Verify by execution in the same turn, aborted-transaction
probes for writes, never fabricate or back-date data to turn a gate green, never weaken a check.
Deploy to both projects, merge via PR, run the end-of-session sweep (Actions · Vercel · both
Supabase · Row #3 to completion · pack scorecard both · `fn_os_portals_gates` both ·
`project_parity` → BOTH PROJECTS IN SYNC), and only then the one line:

`all verified and fixed and merged and deployed 100%`

If it is not true, keep working — or hand over honestly and name exactly what is unfinished.

---

## THE VISUAL STANDARD — he supplied two reference designs. This is the MINIMUM.

His words: *"this is the minimum expectation in terms of the visuals and design. of course with our
requirement though."* So: this SHAPE, our domain. Do not copy their nouns — an RFQ marketplace has
no "orders" and no "$250.00 balance due".

**Reference A — a customer dashboard.** Dark navy persistent LEFT SIDEBAR, icon + label, one item
active with a filled pill. Top bar: full-width search, notification bell, avatar + name. Body on a
soft grey canvas, white rounded cards with generous padding: a welcome card ("Welcome, {name} —
here is a summary of your recent activity"), a row of **KPI stat tiles** (big number, small label),
a **data table** with coloured status pills, a right rail carrying a **donut chart**, a stack of
**quick-action rows** (icon + label), and small panels for shortcuts and announcements.

**Reference B — a client portal.** Top nav, a large welcome heading, and — the important one — a
**prominent AI search bar as a primary surface**: *"Search docs, tasks, files and other with AI…"*.
Below it: large card tiles (Files / Tasks / Reports), a left navigation tree, a **progress stepper**
for a multi-stage job, a **chat panel docked in the layout**, a task list with priority tags, and a
recent-documents list.

### The two structural lessons, which matter more than the palette

1. **A PERSISTENT SIDEBAR, NOT A MARKETING HEADER.** Both references put the customer inside an
   application. We put them on a website with a nav bar that offers them the supplier portal. This
   is the same defect as `SiteHeader` having no concept of audience — solved properly, it is a
   portal shell, not a filtered menu.
2. **THE ASSISTANT IS A PRIMARY SURFACE, NOT A WIDGET.** Reference B makes AI search the widest
   element on the page. He called ours "a dumb chat bot"; part of that verdict is that it is a
   bubble in a corner instead of the way you use the portal.

### Mapping to our domain — this is the "our requirement though"

| Reference | Ours |
|---|---|
| My Orders | **My Requests** — the RFQs, with their real lifecycle |
| status pills Shipped/Processing/Pending | **Matching · Quoting · Quotes in · Revealed · Closed** |
| Invoices & Billing, "Balance Due $250.00" | **Reveals** — the 3% facilitation fee is the only money a customer ever pays. There is no balance, no invoice ledger. Do not invent one. |
| Billing Overview donut (Paid/Unpaid) | **The quote spread on a request** — and see the hard rule below |
| Support Tickets | **Support** |
| My Documents | **My Documents** — drawings, extracted BoQs, the signed terms PDF |
| Account Settings | **Account** — name, mobile, verification state, language |
| KPI tiles | **Open requests · Quotes received · Awaiting your decision** |
| Quick actions | **New request · Compare quotes · Upload a drawing** |
| Project Progress stepper | **The request's own journey**: described → structured → matched to N suppliers → quotes arriving → compare → reveal |

### THE ONE RULE NO AMOUNT OF DESIGN MAY BREAK

**Pre-reveal, a customer sees a rounded band and a count — never an individual quote, never a
supplier name.** `fn_wa_context` already enforces exactly this in SQL and the portal enforces it
today. A beautiful chart that plots five distinct quote bars before payment destroys the product's
core promise: the marketplace is anonymous until the customer chooses to reveal. Post-reveal, show
everything. Design both states.

### Craft, since "static and outdated" was half the complaint

Motion on state change (a quote arriving, a status advancing), skeletons rather than spinners,
real empty states that tell a customer what happens next rather than showing an empty box, and the
whole thing correct at 375px — a UAE procurement buyer is on a phone on a site. Dark mode if it
comes free with the token system; not at the cost of the Arabic.
