---
name: admin-power-needs-an-aal2-session
description: "10 Nov 2026: a JWT becomes admin ONLY through supabase/functions/_shared/admin_session.ts adminCaller() — admin_emails AND aal=aal2 (TOTP authenticator, free; phone MFA is paid and off, ledger 1606). Ten doors use it; an aal1 admin gets 403 two_step_required and is sent to /admin. A check fails on any new admin_emails read outside the door. Recovery of a lost phone: docs/runbooks/admin-two-step-sign-in.md."
metadata:
  type: project
  modified: 2026-11-10
---

**The rule.** Never write `allow.includes(user.email)` against `admin_emails` again. A function that needs the
founder or an admin calls `adminCaller(admin, sec, req.headers.get('Authorization'))` and handles four answers:
`admin` (aal2), `two_step_required` (return `J(a.body, 403)`), `not_admin` (that caller's own path, unchanged) and
`signed_out`. The internal credential (`__secret`, requireInternal) is a separate door and needs no second factor.

**The ten doors (10 Nov 2026):** accountant, ceo_agent, compliance_archive, extract_text, it_engineer, marketing,
pdf_native, quote_compare, refunds_api, sales_engineer. The audit row named email_triage and wa_templates_watch.
Those read admin_emails only as a recipient list. It missed ceo_agent, marketing and sales_engineer.
`scripts/checks/every_admin_door_requires_a_two_step_session.test.mjs` holds the register of address-list readers,
with a reason and a read count for each.

**Testing a door.** `_shared/admin_two_step_harness.ts` drives a real handler over stubbed GoTrue and PostgREST
(`twoStepCases(...)`). A test fixture that uses an opaque string as a founder token (as
`accountant/actions_contract.test.ts` did) now gets 401: signedInUser refuses a non-JWT locally. Use JWT-shaped ZZ
DEMO tokens with `sub` and `aal`.

**The UI cannot be walked in a browser from a worktree on the shared deno-layout node_modules** (measured 10 Nov).
`next dev` (Turbopack) refuses the symlinked node_modules, and `next dev --webpack` renders HTML 200 but hydrates
no page, /contact included. The sign-in logic is in `src/lib/adminTwoStep.ts` instead, driven by the real
`@supabase/auth-js` client over a stub in `src/lib/adminTwoStep.test.mjs`. A browser walk needs a worktree with its
own `npm ci`.
