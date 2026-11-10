# Admin two-step sign-in: enrolment, recovery, release

Seat: it_engineer. Written 10 Nov 2026 for open item 1 of the
[10 Nov security checklist audit](../reports/2026-11-10-security-checklist-audit.md) ("Admin accounts have one factor").

## What changed

Ten edge functions grant admin power to a signed-in JWT whose e-mail is in `app_secrets.admin_emails`. These are
`accountant`, `ceo_agent`, `compliance_archive`, `extract_text`, `it_engineer`, `marketing`, `pdf_native`,
`quote_compare`, `refunds_api` and `sales_engineer`. Until now, that e-mail was the only test. Whoever read the
founder's mailbox, or held the SIM behind `admin_mfa_phone`, was the admin.

All ten now go through one door, `supabase/functions/_shared/admin_session.ts` (`adminCaller()`). It also requires
the token's `aal` claim to be `aal2`, which is Supabase Auth's record that this session passed a second factor. The
only second factor is **TOTP from an authenticator app**. It is free on every Supabase plan. Phone/SMS MFA is a paid
add-on, and the founder ruled on 10 Nov 2026 (ledger 1606) that nothing that costs money is added, so it is never
offered.

| caller | before | after |
|---|---|---|
| admin e-mail, aal1 session (the e-mail code alone) | admin | **403** `{"error":"two_step_required","step":"challenge" or "enrol","url":"https://quotesdone.com/admin","message":"Two-step sign-in required: …"}` |
| admin e-mail, aal2 session | admin | admin (unchanged) |
| signed-in customer or supplier, aal1 or aal2 | its own path | its own path, same status and body (measured on all ten) |
| internal credential (`__secret`) | its seat | its seat (unchanged; it is not a JWT) |

The internal credential is untouched. So the seats, the pg_cron jobs and the founder's Claude sessions keep working,
whatever happens to his phone.

## The sign-in screen: https://quotesdone.com/admin

The screen is English only and is not indexed. Nothing on the site links to it.

1. **Admin e-mail → code.** This is `login_otp` with `user_kind: 'admin'`, the sign-in that already existed. It gives
   an aal1 session.
2. **First time only: enrol.** The page shows a QR code and the setup key. Scan it with Google Authenticator,
   Microsoft Authenticator, 1Password or any TOTP app, then enter the 6-digit code it shows.
3. **Every later time: challenge.** Enter the current 6-digit code.
4. The session is now aal2 and the ten functions accept it. The page can copy the access token for an admin call.

The session is stored under its own key, `qd-admin-auth`, so it never mixes with a customer or supplier session in
the same browser.

## Lock-out safety (why the founder cannot be locked out)

- **No authenticator yet → enrolment, not refusal.** The 403 says `step: "enrol"` and names the page. The first factor
  still opens /admin, and /admin sets up the second.
- **A half-finished enrolment** (QR shown, never confirmed) opens nothing. The page removes it before it starts a new
  one, so a closed tab never blocks the next try.
- **The internal credential is a separate door**, so seat and cron work never depends on the phone.
- **A lost phone is recovered without code changes**, as described below.

**The window before enrolment.** Until the founder enrols, someone who takes over the mailbox could sign in at
/admin and enrol their own authenticator first. Once a verified factor exists, Supabase refuses a new enrolment from
an aal1 session, so that window closes when the founder enrols. **Enrol right after the deploy.**

## Recovery: the authenticator phone is lost or reset

Only the release operator (a Claude session with the management credential, or the founder in the dashboard) does
this, and only on the founder's word.

**A. Supabase dashboard.** Open project `htdblwldjkcgjvmqkbeh` → Authentication → Users → the admin account
(admin_emails[0]). Remove its MFA factor, then confirm. If this dashboard version shows no remove control for
factors, use B.

**B. Auth admin API (service role).** In a session that holds the service-role key server-side:

```js
const { data } = await admin.auth.admin.mfa.listFactors({ userId: '<the admin user id>' });
for (const f of data.factors) await admin.auth.admin.mfa.deleteFactor({ userId: '<the admin user id>', id: f.id });
```

After either one, the founder signs in at /admin with the e-mail code. The page sees no factor, shows a new QR code,
and he enrols the new phone. His existing aal2 sessions fall back to aal1 at their next refresh (up to 1 hour,
`jwt_exp 3600`). To end them at once, sign the account out everywhere in the same Users panel.

Do not delete the auth user itself. That would also end the admin account's identity in `auth.users`.

## Release steps (for the release operator)

Production auth config was **read** on 10 Nov 2026 (`GET /v1/projects/htdblwldjkcgjvmqkbeh/config/auth`):
`mfa_totp_enroll_enabled: true`, `mfa_totp_verify_enabled: true`, `mfa_phone_enroll_enabled: false`,
`mfa_phone_verify_enabled: false`, `mfa_max_enrolled_factors: 10` and `mfa_allow_low_aal: false`. Nothing was changed.
**No auth config change is needed.** TOTP is already on and phone is already off. Leave phone off.

1. Deploy the web app, so that /admin exists before any function sends people there.
2. Deploy the ten functions: `node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production accountant
   ceo_agent compliance_archive extract_text it_engineer marketing pdf_native quote_compare refunds_api
   sales_engineer`.
3. Tell the founder to enrol at /admin straight away (see "The window before enrolment" above).
4. Verify with a non-founder probe only. A call with no token, and a call with a ZZ DEMO customer session, must still
   get their old answers (401 or 403 `unauthorized`/`forbidden`). Never sign in as the founder, and never enrol,
   unenrol or change a real account to test this.

`mfa_allow_low_aal: false` was read but its effect on an enrolled user's aal1 token was not measured. If the auth
server refuses that token outright, the ten functions answer it 401 instead of the 403 with the step. The fix is the
same: sign in at /admin.

## Tests

- `supabase/functions/_shared/admin_session.test.ts` checks the decision itself: aal1/aal2, enrol/challenge, subject
  mismatch, a phone factor not counted, and an outage.
- `supabase/functions/<each of the ten>/two_step.test.ts` drives the real handler over a stubbed auth server and
  PostgREST: an aal1 admin gets 403, an admin with no factor is sent to enrolment, an aal2 admin gets the answer it
  got before, and a non-admin gets exactly what it got before.
- `src/lib/adminTwoStep.test.mjs` drives the real `@supabase/auth-js` client through enrol → wrong code → right code
  → aal2, then a later challenge, over a stub.
- `scripts/checks/every_admin_door_requires_a_two_step_session.test.mjs` fails if any function reads `admin_emails`
  outside the door without being a registered address list, if a door drops `adminCaller` or its test, or if a phone
  factor is ever enrolled.
