# Supplier-registration email campaign — lawful basis and opt-out

Owner: marketing (with it_engineer). Written 23 Sep 2026 for founder instruction 584. Checked by
`scripts/campaign_readiness.mjs` (row "6 consent" confirms this file exists; rows 2, 3, 5 and 7 prove
the controls below on production).

## What is sent, to whom

- One invitation per business email address, ever (unique outbox index on the lower-cased address, and
  `fn_supplier_invite_eligible` reads `notifications`, not a status column), plus at most three reminders to an
  unopened invitation on day 3, 7 and 14 (#1149), under the same switch, cap and opt-out. The privacy policy (1.6, s9)
  states "one invitation and up to three reminders".
- Recipients are **businesses**: `leads` rows built from published business listings (company name,
  trade, business email on the company's own domain, measured MX), and only a **role address** (info@,
  sales@, enquiries@, office@ ... `fn_is_role_address`), never a person's mailbox. Mailboxes read by people outside the
  business (careers, hr, legal, privacy, webmaster, ...) are excluded.
- Never to a demo fixture, a sanctioned or screened party, a banned or closed lead, or an address on
  `email_suppressions` for any reason.
- English, or Arabic where the company writes its own name in Arabic script or its locale is Arabic.

## Lawful basis

**UAE PDPL (Federal Decree-Law No. 45 of 2021).** The data processed is business contact data of a
company: its published business email and name. The purpose is a single business-to-business offer
(a free, commission-free supplier listing), made to the address the business itself published for
enquiries. The basis is PDPL Art. 4: the data is data the business has itself made publicly available
(founder decision, 19 Oct 2026, legal finding 3). We do NOT rely on legitimate interests. That basis holds
only for a role mailbox the business publishes (info@, sales@, enquiries@ ...), so **only role addresses are
contacted, never a named person's mailbox** (ahmed@, j.smith@): the rule is `public.fn_is_role_address(text)`,
read by the invitation selection (`fn_supplier_invite_eligible`, `fn_supplier_invite_eligible_ids`) and by
the reminders (`fn_supplier_invite_nudges_due`) - scripts/sql/supplier_invitations_go_only_to_role_addresses_never_a_persons_mailbox.sql.
Processing is limited to the minimum data, with an immediate and permanent opt-out. No personal data is sold or shared; nothing beyond the published listing is collected before
the business chooses to register. A PDPL access or erasure request is recorded in `pdpl_requests` and
answered through `fn_pdpl_open` -> emailed code -> `fn_pdpl_verify` (or self-service `pdpl_request_me` for a signed-in, email-verified account); erasure has a 7-day cooling-off (`fn_pdpl_cancel`) and suppresses marketing only. Until 6 Oct 2026
this line named functions that had been dropped on 7 Sep; see
scripts/sql/a_person_can_get_a_copy_of_their_data_and_have_it_erased_where_no_law_requires_it_kept.sql.

**Cabinet Resolutions No. 56 and No. 57 of 2024 (telemarketing and its penalties).** The published
summaries we read (Mondaq, June 2024) describe their scope as marketing phone calls, SMS and marketing
messages through social applications, directed at consumers, effective 27 Aug 2024. Email is not named
in that summary; one secondary source says email is covered. The official text
(uaelegislation.gov.ae, legislation 2519) returned HTTP 403 when read on 23 Sep 2026, so we have NOT
read the articles themselves. We therefore apply their requirements to this campaign anyway:

| Requirement (as summarised) | How the campaign meets it |
|---|---|
| Identify the sender and the purpose | From "QuotesDone Suppliers", the subject states an invitation; the body names the company and the offer |
| Contact only within 9:00–18:00 | Sends are spread with `not_before` across 09:00–17:00 Dubai (`invite_warmup`) |
| Honour an opt-out at once and permanently | One-click unsubscribe (RFC 8058 List-Unsubscribe + footer link, and a mailto), written to `email_suppressions` on the first POST, checked before every send |
| Do not contact those who opted out | Suppressed addresses are excluded at selection and again at send |
| Keep records | Every send is a `notifications` row with the provider message id; every opt-out a `email_suppressions` row |

The WhatsApp/SMS channels are out of scope for this campaign.

## Opt-out, end to end

1. Every invitation carries a signed unsubscribe link and `List-Unsubscribe` / `List-Unsubscribe-Post`
   headers; `send_outbox` holds supplier marketing if the link cannot be built.
2. GET shows a confirmation; POST (one-click or the button) writes `email_suppressions(reason='unsubscribe')`.
3. An unsubscribe stops the invitation and its reminders; a hard bounce or complaint (from
   `resend_webhook`) stops every mail to that address.
4. The recipient can resubscribe from the same signed link.

This is an engineering record of the controls, not legal advice. Before the ramp goes past a volume the
founder considers material, the official text of Resolution 56 should be read once and this file
updated with the article numbers.
