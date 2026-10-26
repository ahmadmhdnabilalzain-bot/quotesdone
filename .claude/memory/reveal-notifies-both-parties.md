---
name: reveal-notifies-both-parties
description: On reveal-fee payment the platform must notify BOTH parties by email AND WhatsApp; the code sends one email to the customer only.
metadata:
  type: project
---

Founder, 19 Aug 2026: once the reveal fee is paid, QuotesDone **automatically** sends
an email to **both** the customer and the supplier confirming the customer has selected
that supplier, **and** a WhatsApp notification to **both**, on the numbers each registered with.

**Measured against the code the same day — the product does not do this.**
`trg_reveal_receipt` on `public.transactions` (fires when `revealed_at` goes non-null)
contains exactly **one** `insert into public.notifications`, addressed `to_role='customer'`.
Its body mentions no channel, no phone and no WhatsApp. So the declared contract is
4 messages (2 email + 2 WhatsApp) and the implementation is **1 email, customer only**.

**Why:** this is the external-effect contract for the reveal path, and it is the founder's
own specification — not something derivable from the schema. Phase D §9 must build to
4 messages, not to what the trigger currently does.

**How to apply:** treat the reveal notification as a 4-message contract when building the
durable adapter. The supplier-side email and both WhatsApp messages do not exist yet —
they are missing capability, not held capability. Do not "fix" the trigger while the
automation hold stands; build the adapter contract and leave it mock.

See [[the-funnel-was-all-fixtures]] — `public.notifications` holds 0 rows of this type,
so nothing has ever exercised the path. Related: [[a-canonical-write-that-emails]].

**UPDATE 3 Sep 2026 — IMPLEMENTED AND PROVEN.** trg_reveal_receipt (canonical file
scripts/sql/reveal_notifies_both_parties_on_both_channels.sql) now queues BOTH emails from the one door
(transactions.revealed_at transition): reveal_receipt to the customer and quote_accepted to the supplier
(moved out of stripe_webhook, which now only counts what the trigger queued). The WhatsApp half already
existed as trg_wa_fanout on notifications, which mirrors every email row to a WhatsApp row when that party
has a number AND wa_optin=true — the 19 Aug measurement missed it because the fixtures had the default
wa_optin=false. Do NOT add explicit WhatsApp inserts to the reveal trigger: the first cut did and the
rehearsal measured six messages. send_whatsapp maps quote_accepted to the template key
supplier_quote_accepted; wa_template_setup takes body.key from a catalogue (supplier_doc_expiry,
supplier_quote_accepted) and registers Content templates; the credential to call it is
app_secrets.cred_ops_wa_template_setup (context ops.wa_template_setup). Proof: rehearse_full_funnel.mjs
20/20 — exactly four reveal messages, email + WhatsApp per party.
