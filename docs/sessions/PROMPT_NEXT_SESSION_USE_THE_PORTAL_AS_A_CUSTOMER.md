# Next session prompt — use the portal as a customer, then upgrade it

Copy everything below the line into a new session.

---

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Don't report the
OpenRouter balance, but DO tell me if it's refusing calls.

**THE JOB: BE A CUSTOMER, IN A BROWSER, FOR REAL — THEN UPGRADE WHAT YOU FIND.** The portal shell
was rebuilt on 13 Aug and it is now a real application: sidebar, top-bar assistant, mobile tab bar,
proper empty states. That was the floor, not the ceiling. Your job is to *use* it the way I use it
and make it better.

## HOW I WANT YOU TO FIND THE WORK — THIS IS THE METHOD, NOT A SUGGESTION

Open the portal signed in as me. Click every tab. Click every button. Type in every field. Then, on
each screen, ask yourself the question I ask:

> **"I wish this thing did X."**

Write the X down and then go build it. That question finds more than any audit does, because it is
the question a paying customer actually asks. Some of mine, to show you the shape:

- *I wish it told me what happens after I post, without me having to ask.*
- *I wish I could see, on one screen, which of my requests is waiting on ME versus waiting on a
  supplier.*
- *I wish the assistant offered me the next thing instead of waiting to be asked.*
- *I wish I knew what a reveal will cost me before I click it.*

**Do not stop at "it renders and nothing 500s".** That is the bar for a bug fix. The bar here is:
would a procurement manager at a real UAE contractor choose this over emailing five suppliers?

**RULE ZERO, AND IT HAS BEEN EARNED TWICE.** A grep of a component is evidence about a file, not
about a screen. Before you say one word about a surface I will look at: `preview_start`, render it,
screenshot at 375 and 1280, signed in as a customer. Then again after every change. The last session
that skipped this described the field order out of the JSX and missed all three defects I could see
in ten seconds.

Signing in as me for testing, without emailing me a code: insert a row into `email_verifications`
with `token_hash = encode(hmac('<code>', (select value from app_secrets where key='otp_hmac_key'),
'sha256'),'hex')`, `purpose='login'`, `user_kind='customer'`, `email='djzaino@outlook.com'`, then
POST `login_otp` `{action:'verify', user_kind:'customer', identifier:'djzaino@outlook.com',
code:'<code>'}`. Put the returned `access_token` in `localStorage['qd-cust-token']`.

## WHAT IS ALREADY DONE — DO NOT REBUILD IT

Merged 13 Aug as PRs #306–#314, all live on production:

- **The portal shell.** `src/components/me/PortalShell.tsx` — persistent grouped sidebar (Work /
  Collaborate / Intelligence / Account), a top bar whose widest element is the assistant field with
  ⌘K, a five-item mobile tab bar with a More sheet, the assistant docked as a panel. §21's
  per-customer `layout.order` is applied *within* each group via CSS `order`; Overview and My
  requests are pinned ahead of it. Module surfaces render in the main region, not in a Dialog.
- **The assistant has identity.** `site_assistant` takes the session JWT, resolves the caller, and
  answers from `fn_wa_context` — whose identifier now accepts an email as well as a phone, so the
  portal and WhatsApp share ONE copy of the pre-reveal rule. `try_faq` is off for a signed-in
  person; a `customer_portal_assistant` policy routes signed-in conversations to the large tier;
  `cache_ttl_min: 0` is passed at the call site because `sys` now carries one person's data.
- **KPI tiles, the five lifecycle pills** (Matching · Quoting · Quotes in · Revealed · Closed), a
  journey rail, quick actions, real empty states, skeletons, a two-column sign-in, an editable
  Account (name, mobile, language — `customer_api` gained a narrow `set_locale`), and a bell that
  opens the actual alerts.
- **`QuoteSpread` renders both states.** Pre-reveal it is a count and a band rounded to the nearest
  1,000 behind a lock chip — never one bar per quote, never a supplier name. Proven by an
  aborted-transaction probe with five real quotes.
- **Security:** `kyc save_customer` now clears `phone_verified` when the digits change. It did not,
  so any signed-in customer could change their number and keep the verified flag.
- **Session:** the portal signed people out every hour while holding a valid refresh token. Fixed
  with an `onAuthStateChange` listener plus one refresh attempt on a 401.
- **`SiteHeader` knows its audience** — a signed-in customer is no longer offered the supplier
  portal.

**THE SIDEBAR IS APPROVED AND SETTLED (13 Aug).** Row #4 sits at **146/147**; the one failure is
spec §21's `ui-not-sidebar-pages-tables`, evidence `sidebar: 1`. That single hit is the `<aside>` of
the docked assistant, not the navigation. **Do not remove the sidebar to make the score green, and
do not rename that element to dodge the check.** I asked for the sidebar. Leave the red.

## WHAT IS PENDING — in the order I care about

### 1. The portal itself. Upgrades, found by using it. (This is the job.)
Nobody has posted an inquiry yet, so most screens are in their empty state. **Judge the empty state
AND the full state.** For the full state you can drive fixture rows into the UI by patching
`window.fetch` for `customer_api my_inquiries` in the browser — do NOT write fake inquiries to the
database. Things I already suspect are worth your judgement, but find your own:
- Is the Overview the right first screen, or should a customer with a live request land on it?
- The nine module surfaces got a shell and a page header; their *insides* are unchanged and plain.
- Nothing tells a customer what a reveal will cost before they commit to one.
- The assistant answers when asked. It never offers.

### 2. `ai_quality_snapshots` has no screen
1,219 rows, 38 agents, `override_pct` per agent — how often a human overrides each AI employee —
written as recently as this morning, and nothing in `src/` reads it. It is the best quality signal
in the estate and it is invisible. Put it where I will see it.

### 3. The unidentified legacy-secret caller
`internal_credential` id 1 (`legacy.shared`, the pre-9.5 shared `inbound_secret`) is still `active`,
never retired, no expiry, scope already narrowed to `{ai_gateway, postiz_publish, knowledge_exam}`.
Last used **12 Aug 07:38** — 1 use in 24h, 5 in 7 days. Every caller in the repo already presents a
per-context credential (`cred_fn_ai`, `cred_fn_social_stage`, `cred_cron_knowledge`). The repo's own
notes describe an invoker that falls back to the shared secret when `cred_fn_<fn>` is missing "while
logging the fallback" — that matches these rows exactly and I could not find that code path. **Find
the caller. Do not retire the credential without telling me** — something still uses it daily.
`fn_resilience_watch` now names any user of it within ten minutes.

### 4. The 35 held handoffs — my decision, and I have not given it
`fn_should_escalate`'s prior-failure rule was holding 32 handoffs and zero strategies; it is fixed,
so new ones flow. The 35 already in `needs_review` were held by the defect. Re-run through the
corrected gate, 41 of the 44 release and 3 stay held. **`zzz_action_gate` is `BEFORE INSERT` only,
so a bulk UPDATE overrides the gate rather than re-running it** — the query that asks the gate row
by row is in the PR #311 comment. Ask me before running it; several rows quote conditions from
10 Aug and releasing three days of frozen work at once may duplicate work.

### 5. Drawing redaction — the retry is wired and unexercised
On a refused page the detector now gets a second look with the verifier's own findings as its brief.
Neither committed fixture is ever refused, so **a recovery has never been observed**. Measuring a
yield needs the real 6-sheet consultant set, which is not in this working tree (one of the ten pack
artefacts with no source file). Do not quote "4 of 6"; it has not been re-measured.

### 6. The invite ramp — measured, do not act yet
named humans **12 sent, 0 bounced (0.0%)**; role addresses **59 sent, 5 bounced (8.5%)**.
`invite_enabled=true`, cap 10/day, 19,833 uncontacted leads still hold an email. Below the ~20
named-human sample I set. Re-measure; act only if it has crossed.

### 7. Also open
7 unread tables (all seven reach `src/` zero times — `scenario_expectation_baseline`, 3,324 rows, is
consumed by nothing anywhere) · 10 pack artefacts with no source file (file recovery) ·
`s36-recommendation-seven-fields` cannot pass before mid-September (rolling 30-day window).

## STATE (13 Aug, ~06:45 UTC)

Row #3 **128/152** · Row #4 portal blueprint **146/147** (one deliberate red, see above) · portal
gates **23/23 both** · parity **BOTH PROJECTS IN SYNC** · main CI green including `deploy edge
functions` · Vercel 0 runtime errors · **zero agent errors on production in the last 45 minutes**
(both watchers that failed all night are green because their diagnoses were corrected, not silenced)
· 3 customers · **0 inquiries** · 0 quotes · 7 claimed supplier rows, of which 6 are `ZZ DEMO`
fixtures · 44 actions in `needs_review` · 115 workflow steps ready, 51 ineligible by a stated policy
· AI spend yesterday AED 21.5 · 3 go-live switches false.

**My account is fully open**: `djzaino@outlook.com`, `phone_verified` true, `email_verified` true,
terms accepted, `can_post_request` true. Older briefs say otherwise — they describe the OTHER
customer row (the landline). **Do not fabricate an inquiries row.**

## TRAPS — do not rediscover

- `apply_sql --promote` carries the DEFINITION, not the GRANTS — use `--promote --ddl`, and a file
  whose only change is inside a `DO` block promotes 0 routines. Assert md5 on both yourself.
- `ai_gateway`'s cache does a semantic lookup at 0.95 over a window a large system prompt dominates.
  Pass `cache_ttl_min: 0` on every classifier and on anything carrying one person's data.
- A new table gets RLS on production by event trigger and NOT on staging — declare it in the DDL.
- An LLM error string is written by our own catch block. Check `latency_ms` against the caller's
  timeout before believing it.
- `least()`/`greatest()` ignore NULLs · `_` is a word character in Postgres regex and a single-char
  wildcard in LIKE · BEFORE triggers fire in NAME order · a cron reporting `succeeded` for a
  `net.http_post` only means the request was QUEUED · HTTP 546 kills the isolate so the function's
  own catch never runs · `net.http_post` inside a `DO` block never fires.
- `onClick={fn}` passes the MouseEvent as the first argument. If `fn` takes a flag, it arrives
  truthy — this cost a real bug in the portal's session retry.
- A count reached by SUBTRACTING the reasons you thought of is a count of the reasons you did not.
  If a watcher says "unexplained", join it to the table that explains it before you believe it.
- Ask whether a condition can ever NOT fire. A text-similarity rule aimed at "is this the same
  attempt" also matches "is this about the same subject", and a report is always about its subject.
- A CI failure reading `Failed caching npm package …` is infrastructure. Re-run it.
- **NEVER push to main.** Everything through a PR.

## HOW I WANT THE SESSION RUN

Do not check in. Do not send progress updates. Take the next item. I decide three things only:
Stripe refunds, spending money, and the three go-live switches. Verify by execution in the same
turn, aborted-transaction probes for writes, never fabricate or back-date data to turn a gate green,
never weaken a check — and never rename an element to dodge one. Deploy to BOTH Supabase projects
(`htdblwldjkcgjvmqkbeh` production, `pglpqrhvozwepymcuunn` staging), merge via PR, run the
end-of-session sweep (Actions · Vercel · both Supabase · Row #3 to completion · Row #4 portal
blueprint · pack scorecard both · `fn_os_portals_gates` both · `project_parity` → BOTH PROJECTS IN
SYNC), and only then the one line:

`all verified and fixed and merged and deployed 100%`

If it is not true, keep working — or hand over honestly and name exactly what is unfinished.
