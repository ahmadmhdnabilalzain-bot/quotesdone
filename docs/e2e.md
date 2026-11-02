# The end-to-end harness — browsing both portals without anyone's credentials

Founder, 14 Sep 2026: *"do what is needed cause you need to keep browsing stuff without my credentials"*.
Owner: `ceo` (it_engineer's tooling, carried out for the ceo).

```
npm ci && npx playwright install chromium
node scripts/e2e/run.mjs                   # every journey, report + screenshots, full cleanup
node scripts/e2e/run.mjs --journey a,b,c   # only these
node scripts/e2e/run.mjs --keep            # keep the run's rows; later: --purge-tag <tag>
```

It targets the live site (`QD_SITE`, default `https://quotesdone.com`) and the one production project,
because there is no staging by the founder's rule. The report goes to `QD_E2E_REPORTS` or the main
checkout's `e2e-reports/<timestamp>/` (git-ignored). The exit code is 0 only when nothing failed and
nothing was left behind.

## Where things live

| file | what it is |
|---|---|
| `scripts/e2e/run.mjs` | the one command: preflight, fixtures, journeys, safety assertion, teardown, report |
| `scripts/e2e/fixtures.mjs` | demo customers and suppliers, sign-in without an OTP, leftovers count |
| `scripts/e2e/browser.mjs` | a signed-in Playwright page, timings, console capture, screenshots |
| `scripts/e2e/journeys.mjs` | journeys a-g |
| `scripts/e2e/founder_demo_tour.mjs` | the STANDING demo of both portals and the sign-in link that opens it (§6) |
| `scripts/lib/demo_pdf.mjs` | the ZZ DEMO trade-licence PDF (shared with `scripts/staging/make_fixture_licence_pdf.mjs`) |
| `scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql` | the database half: marker, pairing guard, capture, figures |
| `supabase/functions/_shared/demo_identity.ts` | the TypeScript half of the same rule (`send_whatsapp`, `stripe_checkout`, `stripe_confirm`) |
| `scripts/checks/demo_identities_never_reach_a_real_person.test.mjs` | proves the database half on production in an aborted transaction |

It builds on `scripts/lib/demo_factory.mjs`, which does auth admin, teardown by run tag and the OTP
hop. It does not replace it. `journey_test.mjs` is older API-only coverage. It still calls
`dispatch_inquiry`, which no longer exists, so this harness does not reuse it.

## 1. Identities without credentials

Every identity is recognisable as demo by the data itself:

- email `qd-<tag>-<kind><n>@example.invalid`, an RFC 2606 domain nobody can receive mail at;
- mobile `+971 50 000 00xx`, the reserved fixture block;
- name `ZZ DEMO …`.

The database derives `customers.is_demo` and `leads.is_demo` from those (generated columns, so nothing can
set them or forget to). A real customer cannot acquire the marker: they would have to receive an OTP at a
reserved domain.

- **Customer:** name, date of birth 1990 (18+), email verified through the real `login_otp` endpoint (the
  code is seeded hashed, exactly as `login_otp` stores it; only delivery is skipped), mobile recorded as
  verified, current customer terms accepted and signed through `kyc accept_terms`.
- **Supplier:** the mandatory six. Name, mobile, email, a generated ZZ DEMO trade-licence PDF uploaded to
  `supplier-docs`, the profile, and the current Supplier Agreement accepted and signed through `kyc`. It
  is approved and its capability confirmed for `aluminium`.

**Sign-in, and why this way.** The Auth admin API creates the user with a random password held only in
the harness process. The password grant returns a normal Supabase session, and the harness writes it into
the portal's own storage keys (`qd-cust-token`, `qd-cust-refresh`, `qd-cust-auth`; suppliers
`qd-sup-token`, `qd-sup-refresh`, `qd-portal-auth`). All three are written; see quotesdone-session §7 for
why two is not enough. **Nothing in Auth's configuration was changed** and no test-OTP numbers were
registered, so real users sign in by OTP exactly as before. That is why this was chosen over test OTP
entries.

## 2. Nothing reaches a real person

- **`zzzz_notifications_demo_capture`** (database). Any notification addressed to a demo email or mobile,
  or about a demo lead, request or quote, is recorded as `suppressed` with a `captured:` reason, both on
  insert and on any later move back to queued. That covers a notification to the founder or a real
  supplier about a demo entity. Both dispatchers drain only `queued`.
- **`send_whatsapp`** also refuses a `+971 50 000 00xx` number at the only place a WhatsApp can leave.
  `send_outbox` has refused reserved domains since 3 Sep.
- **Rehearsal window.** The harness declares one, so `fn_watch_failed_runs` never pages the founder
  about a rehearsal.
- **Refuses to start** unless the guards are installed. **After the run** it asserts that no notification
  it caused was sent, queued or pending.

## 3. Demo and real never meet, and demo is never counted

- A match between a demo request and a real supplier (or the reverse) is not recorded. Both writers read
  the landed rows back, so the fanout stays honest.
- A quote across the line is refused (`23514`). Demo-to-demo still matches, which the harness needs.
- `fn_health_index`, `fn_os_dashboard_viz`, `fn_os_health` and `fn_company_snapshot` no longer count demo
  rows.
- `fn_ops_dashboard` and `fn_wa_context` were left alone: they call routines that do not exist and throw
  on every call today. See the PR.

## 4. Stripe: test mode only, for demo accounts only

`stripe_checkout` and `stripe_confirm` derive the mode on the server from the signed-in account's email.
A reserved domain gets `stripe_secret_key_test` / `stripe_publishable_key_test`. Everyone else gets live.
Nothing the browser sends can change it, and when the test pair is absent a demo account is refused with
`stripe_test_not_configured`. **There is no fall-through to the live key.** Journey d skips without
calling Stripe until the founder adds the two test secrets.

## 5. The journeys

The funnel runs once, in order. The screens run across English and Arabic, desktop 1440 and mobile 375.

| | proves |
|---|---|
| a | sign-in without an OTP; overview data under 2.5 s; Arabic right-to-left; a request through the sales-engineer chat, its answers (installation, warranty, materials, date) on the row |
| b | the invitation is visible and anonymised (screen and API); incomplete → HELD → notice captured → filled in → regenerated → approved → released; two options → two quotes; a complete quote accepted first time; a held quote is not ranked |
| c | the comparison report and a quotation open as PDFs in EN and AR; the deep link opens the request |
| d | the reveal in Stripe TEST mode (skips until the test keys exist) |
| e | the invoice; the refund ladder (skips; see the run report) |
| f | every nav item on both portals — the supplier's Account menu opened, the phone's More sheet opened — and the non-destructive buttons in each view, with timings and console errors |
| g | the WhatsApp question inside sign-up: Yes (en), No + a second number (ar), and a supplier through the same kyc actions |

A step that could not be proved says SKIP or FAIL with the reason. It never passes by assumption.

### Journey f follows the ACCOUNT's language, not the URL

Both portals render in the language the account registered in (founder, 14 Sep 2026: *"if someone
registered while the language was arabic then arabic follows through the whole workflow"* —
`customers.locale`, `leads.locale`). So journey f sets that column per matrix before it opens the
portal, exactly as journey a does, and restores `en` afterwards. Without it the two Arabic passes
crawl an English screen and every Arabic label waits out its click timeout: measured 18 Sep on
production, an `en`-registered fixture opening `/ar/portal` gets `dir=ltr lang=en`.

The list of destinations journey f expects lives in `scripts/e2e/journeys.mjs` (`NAV`,
`ACCOUNT_MENU`) and is a second copy of words owned by `src/components/me/portalText.ts` and
`src/components/portal/supplier/workspaceCopy.ts`. It is kept honest by
`scripts/checks/the_crawl_names_the_navigation_the_portals_render.test.mjs`, which fails in CI the
moment a tab is renamed — written after the 15 September supplier rebuild (#722, #723) renamed six
destinations and moved three into an Account menu without it, and the nightly run was cancelled at
its 30-minute wall on 15, 16 and 17 September.

## 6. The standing demo, and the link that opens it

Founder, 18 Sep 2026: *"generate a link for me to access the supplier portal directly without signing
up."* `scripts/e2e/founder_demo_tour.mjs` stands up ONE complete demo that stays alive — it is the
only thing in `scripts/e2e/` that deliberately does not tear itself down — and mints a Supabase magic
link into it. Owner: `sales_engineer` (the supplier portal is his surface).

```
node scripts/e2e/founder_demo_tour.mjs --seed       stand it up and print both links
node scripts/e2e/founder_demo_tour.mjs --link       mint FRESH links (a used one is spent)
node scripts/e2e/founder_demo_tour.mjs --verify     prove a link lands signed in; screenshot every tab
node scripts/e2e/founder_demo_tour.mjs --teardown   remove every row, file and auth user it seeded
```

Run tag `founderdemo`, fixed on purpose: `--link` and `--teardown` must find the demo tomorrow without
being handed a hex string from today. Identities, guards and teardown are §§1-4 unchanged — this file
adds only the CONTENT (services in the supplier's own words put through the rewrite, three inquiries
with a BOQ and a redacted drawing page, two quotations carried through the review conversation to
submission, supporting documents), so there stays exactly one way to make a demo supplier.

**The link.** `POST /auth/v1/admin/generate_link`, `type: magiclink`. Two things make it land signed
OUT on the home page instead, and both answer HTTP 200 with an `action_link`, so `mintLink` reads the
returned `redirect_to` back and refuses rather than hand over a link that does not work:

1. **`redirect_to` nested under `options`.** That is the supabase-js admin CLIENT's shape; the REST
   endpoint reads `redirect_to` at the TOP level and ignores anything else.
2. **A `redirect_to` that is not on the project's redirect allow list.** Until 18 Sep 2026
   `uri_allow_list` held only the Vercel preview hosts, so `https://quotesdone.ae/portal` fell back to
   `SITE_URL`. The company's own domains (`quotesdone.ae`, `quotesdone.com`, both with `www.` and
   `/**`) were added that day; nothing was removed. Measured: an unlisted host still falls back, so
   the list is enforced and those entries are what the link depends on.

The token is single-use and expires after `mailer_otp_exp` (3600 s on this project). The SESSION it
creates is an ordinary one — the portal refreshes it, so a tab left open keeps working past the hour.

## Stage 2: the sandbox run with the model hold lifted (ledger 1119)

`scripts/e2e/stage2.mjs` reuses the stage-1 fixtures and teardown, and runs the whole funnel at founder scale. The scale is 10 ZZ DEMO suppliers in 10 trades, plus 3 more aluminium suppliers so one request gets a real comparison, and 10 ZZ DEMO customers in EN and AR.

- `--dry-run` checks every precondition, runs every cleanup path on an empty tag, scans the 701-table export registry, prints the spend estimate and coverage, and writes the Desktop skeleton with INDEX.html. It makes no model call.
- `--run` does not lift the founder's hold. It opens a rehearsal window with `models_allowed`, a USD 4 `cap_usd` and a 2-hour `expires_at`. `fn_kernel_paid_provider_gate` lets only calls carrying this run's tag past the hold, and refuses them once the tagged `ai_cost_log` spend reaches the cap. Untagged traffic takes exactly the path it took before; there is no cap on production spend (ledger 1134). The window is turned off in a `finally` block and expires in the database regardless. The run exports every artifact to `C:UsersOperaDesktopQuotesDone Sandbox Test 2026-10`, then cleans up and verifies that 0 rows remain.
- `--cleanup-only --tag <t>` and `--verify-clean --tag <t>` handle a run that did not finish.
- Chat turns name no customer, so they are scoped by the run tag. This covers `assistant_logs`, `sales_decision_log` and `support_reply_readability`, which are stamped with `e2e_run_tag` at insert, plus any knowledge gap and the task it opened from the run's own turns. `teardown()` deletes them and `--verify-clean` counts them, both through `demo_factory.chatTurnSql`. With the tag set, `fn_sales_assist` and `fn_support_knowledge_gap` file no gap, bump no counter and open no task (`scripts/sql/a_harness_chat_turn_carries_its_run_tag_and_files_no_gap_or_task.sql`, applied at merge).
- Live duties are `public.seat_duty` plus the zero-argument routines `resilience_ping` ticks. They are not `cron_registry`: `cron.job` held 0 rows on 6 Oct. Each one runs in an aborted transaction with `app.e2e_run_tag` set (`scripts/e2e/stage2_duties.mjs`) and must write no non-demo row.
- Model cost is attributed exactly. The harness sends `x-qd-e2e-run`, `_shared/observe.ts` forwards it on every call back to the project, and `trg_ai_cost_log_e2e_run_tag` stamps `ai_cost_log.e2e_run_tag` (`scripts/sql/a_sandbox_run_is_tagged_capped_and_let_through_only_inside_its_window.sql`, applied at merge). `--run` refuses until that file is applied.
- Coverage comes from `scripts/e2e/stage2_coverage.mjs`, which reads routes, portal tabs, edge-function actions, notice types and duties from the code and the database. Fences: `scripts/checks/the_stage2_sandbox_run_is_fenced.test.mjs`.
