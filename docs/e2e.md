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
| `scripts/e2e/journeys.mjs` | journeys a-f |
| `scripts/lib/demo_pdf.mjs` | the ZZ DEMO trade-licence PDF (shared with `scripts/staging/make_fixture_licence_pdf.mjs`) |
| `scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql` | the database half: marker, pairing guard, capture, figures |
| `supabase/functions/_shared/demo_identity.ts` | the TypeScript half of the same rule (`send_whatsapp`, `stripe_checkout`, `stripe_confirm`) |
| `scripts/checks/demo_identities_never_reach_a_real_person.test.mjs` | proves the database half on production in an aborted transaction |

It builds on `scripts/staging/demo_factory.mjs`, which does auth admin, teardown by run tag and the OTP
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
| f | every nav item on both portals, and the non-destructive buttons in each view, with timings and console errors |

A step that could not be proved says SKIP or FAIL with the reason. It never passes by assumption.
