# Supplier registration with the REAL e-mail code, in a browser, on quotesdone.com — 28 Oct 2026

**Assigned:** `sales_engineer` (supplier registration and the supplier portal).
**Asked:** founder ledger 1375, "tomorrow morning i need suppliers receiving invitations and registering", and, through
the coordinator, "you have to verify 100% the registration is smooth through a browser … i wont be near the laptop".

Measured 27 Oct 23:20Z to 28 Oct ~03:30Z (03:20–07:30 Dubai) with headless Chromium 153 from a cloud container in the
US region, through an egress proxy. **Every timing below comes from that container, not from a UAE supplier.** A phone
in Dubai sits nearer to the database and may be faster or slower; nobody measured that.

Fixes that were deployed during the night and walked again afterwards:
- #1699: `email_triage` v310 and `resend_inbound` v348.
- #1700: Vercel `dpl_H17bGDhpZCzfaMgBJXQmu1iZscxd`, quotesdone.com.

## The journey per channel

### E-mail, Microsoft 365 lane (supplier@quotesdone.com): the channel the invitations resume on

| # | step | handled by | before the fixes | after (28 Oct) |
|---|---|---|---|---|
| 1 | Invitation, variant A, plain text, **no link**: "Would your company like to receive … requests?" | `send_outbox` → `send_outbox/m365_lane.ts` `m365InvitationText` | not sent: `invite_enabled=false` | not sent |
| 2 | The supplier replies "yes" to supplier@ | Graph → `_shared/m365_reply_inbox.ts` (resilience_ping, every 15 min) → Svix-signed hand-off → `resend_inbound` → `inbound_messages` | PASS: the three warm-up replies of 27 Oct were read in; 1,036 `ok` reader runs and 1 error in 14 days | **PASS**: probe stored with `sender_authenticated=true` from Microsoft's verdict |
| 3 | The reply is filed for the sales engineer | `z52_invite_reply_reaches_sales_engineer` → `fn_marketing_files_invite_reply` → `fn_seat_handoff('invite.reply')` | the handoff only **waits** (`fn_sales_engineer_takes_invite_reply`) | unchanged; a demo lead files none (ruling 1199) |
| 4 | The supplier gets an answer | `email_triage` (woken by `resend_inbound`) → `fn_inbox_send` → `notifications` `inbound_reply` → `send_outbox` (Resend, from info@) | **FAIL**: `noAutoReply` returned `internal` for every mail to supplier@. Inbound rows 653–655 were "Not answered automatically: internal", and a probe got `not_answered: 1` | **PASS** (#1699): answered in 141–172 s |
| 5 | The answer says how to register | `email_triage/account_facts.ts` | **FAIL**: every lead (20,276 rows, 20,274 unclaimed) was described to the model as "A REGISTERED SUPPLIER … No jobs yet" | **PASS** (#1699): "not registered yet", plus the company's own `https://quotesdone.com/portal?t=<claim_token>` |
| 6 | The link opens the company's listing on "Create account" | `/portal?t=` → `claim_lookup` | PASS | **PASS** ×4 |
| 7–12 | real code, claim, documents, terms, approval, dashboard | portal + `login_otp` + `supplier_api` + `supplier_portal` | PASS, except the 390 px Upload clip | **PASS** ×4 (matrix below) |

Step 4 is reproducible by script: `node scripts/e2e/invitation_reply_probe.mjs` (the M365 lane) or `--lane=row`. The last
run passed 6/6 and left nothing behind; see `invitation_reply_probe_m365.txt`. The answer it received, word for word, is
in the PR that adds the script.

### Resend path for invitations

Not used. The Microsoft 365 lane is on (`invite_m365_enabled=true`, mailbox supplier@). `campaignMail` builds the same
no-link text for either route, so a fall-back to Resend could not bring back the old e-mail.

The sign-up **code** e-mail does go through Resend, from info@quotesdone.com ("Your QuotesDone sign-in code"). Resend
reported it `delivered` on every leg, 2.0–3.8 s after the click. Inbox versus spam placement for that e-mail was NOT
measured: the sink proves delivery, not placement.

### WhatsApp

Not live for invitations:
- `wa_supplier_invite_golive=false`;
- 0 rows in `supplier_whatsapp_optin`;
- 0 WhatsApp invitation rows ever.

A lead is recognised on WhatsApp only by a CONFIRMED number (`fn_identify_contact`), so an invited lead who writes in is
treated as a visitor. "Set up my page" files an `invite.reply` handoff (`fn_marketing_files_wa_invite_reply`). This
channel was not walked: nothing can reach a supplier on it until opt-ins exist.

## The browser walk: invited supplier, real e-mail code, production

`scripts/e2e/supplier_registration_walk.mjs --real-otp --lang en,ar --vp desktop,mobile --desktop-width 1366`. Desktop is
1366×900; phone is 390×844 with touch and DPR 2.

**How the code is real yet reaches nobody.** The form is filled with `delivered+qd-<tag>-sup<n>@resend.dev`, which is
Resend's own test sink: it accepts the message, records it delivered and drops it. The walk reads the delivered message
back from Resend through pg_net and types the six digits.

**The fixture guards still apply.** The lead stays `ZZ DEMO …` with an `@example.invalid` address, so
`fn_seat_clock_refusal` refused the approval mail to the sink ("a fixture subject may not write to a real address") and
every other notice was suppressed.

**Clean-up.** Every run tore down to 0 rows in every table and left 0 sink accounts.

**Final post-deploy run `f224f85a`: 112 PASS, 0 FAIL.** An earlier post-deploy run (`958df99e`) passed 110 and failed 2.
Both failures were the walk's own new off-screen check catching the closed account-menu `<details>`: Chromium gives its
unrendered items a box. The check now skips closed `<details>`; the open menu is walked and passes.

| step | en 1366 | en 390 | ar 1366 | ar 390 |
|---|---|---|---|---|
| invitation link names the company | PASS | PASS | PASS | PASS |
| "Claim my listing" brings the e-mail box into view | PASS | PASS | PASS | PASS |
| form sends the code; the code step opens and names the address (#1700) | PASS | PASS | PASS | PASS |
| code e-mail delivered (Resend `last_event` delivered) | PASS | PASS | PASS | PASS |
| real code verifies; company opens, claimed | PASS 7.0 s | PASS 7.9 s | PASS 7.1 s | PASS 9.9 s |
| licence + profile stored; expiry read; name matches | PASS | PASS | PASS | PASS |
| every Documents button is on screen (Insurance / ISO / dealer letter at 390) | PASS | PASS (#1700) | PASS | PASS (#1700) |
| WhatsApp question present and recorded | PASS | PASS | PASS | PASS |
| terms + Save → approved, signed certificate | PASS | PASS | PASS | PASS |
| acceptance hashed; mobile + e-mail verified | PASS | PASS | PASS | PASS |
| every tab and the account menu settle | PASS | PASS | PASS | PASS |

The `/ar/` link lands and registers in English, as ruled: suppliers are always English (ruling 1008).

**Fresh supplier (not invited), public `/supplier` page → sign-up → registration → Services → dashboard:** 28 of 28
steps PASS on run `412a3fbf`, at both widths and in both languages; the details are in `summary_fresh_supplier.json`. That leg
still uses the harness's seeded code.

## Defects found, and where each went

| # | defect | severity for the morning | fix | prevented by |
|---|---|---|---|---|
| 1 | a reply to supplier@ was never answered (`noAutoReply` → internal) | **blocker** | #1699, deployed and re-walked | `_shared/customer_mail.test.ts`, `scripts/checks/an_invited_suppliers_reply_to_the_invitation_is_answered.test.mjs` |
| 2 | the answer called an unregistered lead "A REGISTERED SUPPLIER" and gave no way in | **blocker** (with 1) | #1699 | `email_triage/account_facts.test.ts` |
| 3 | at 390 px, the Upload button for Insurance, ISO and the dealer letter sat past the right edge, clipped and unreachable | high (optional documents only) | #1700, deployed and re-walked | `scripts/checks/the_code_step_names_the_address_it_was_sent_to.test.mjs` |
| 4 | the code step did not say which address the code went to | medium (copy) | #1700 | same check |
| 5 | "Claim my listing" scrolled to the box but did not put the cursor in it | low | #1700 | same check |
| 6 | verify + claim takes 6–10 s behind "Attaching your company listing…" | friction, not fixed | — | measured: the claim's database work is ~22 ms (an aborted-transaction probe), so the time is spent in edge and page round trips |
| 7 | the answer to a "yes" takes 141–172 s to write | friction, not fixed | — | model time (think, then the direct reply) |
| 8 | the walk harness: at 390 px it clicked the site header and hung; file inputs differ by width; the profile read raced its write | harness | #1702 | `scripts/checks/the_registration_walk_reads_only_its_own_sink.test.mjs` |

**Seen, and NOT a defect.** Right after an upload, the checklist and "What your documents unlock" briefly lag the
document card. The next screenshot shows all three agreeing (4/7, profile on file).

## The funnel, Sep–Oct 2026

Production, real leads only: not `ZZ DEMO` and not `@example.invalid`.

| measure | count |
|---|---:|
| invitations delivered (`notifications` of type `supplier_invite*`, seeds excluded) | **0**, ever |
| leads with `invited_at` set in Sep–Oct | 0 (see note) |
| `invite_clicked_at` set | 0 |
| replies to supplier@ from an invited lead | 0 |
| `invite.reply` handoffs | 0 |
| real leads claimed | 0 |
| WhatsApp invitations / opt-ins | 0 / 0 |

Note: 171 leads have `invited_at` set, all before September (`invite_status`: sent 161, bounced 10). That is a status
column, not a delivery record.

So there is no real drop-off to read yet, because no invitation has reached a supplier. Registration errors in the last
14 days were guards and fixtures only: login_otp refused fixture numbers, refused SMS sign-up by design, and locked
brute-force attempts. No supplier claim failed.

## Screenshots

`screenshots/` holds every screen of the post-deploy invited run (`postdeploy_invited_*`) and of the fresh leg
(`fresh_*`), JPEG-compressed as the 27 Oct report did. Also there:
- `before_1700_390px_upload_clipped.jpg` and `after_1700_390px_upload_wraps.jpg`;
- the PR #1700 preview check, in that PR. Preview origins get no CORS from the edge functions, so the live flow cannot
  run on a preview; only the send was stubbed there.
