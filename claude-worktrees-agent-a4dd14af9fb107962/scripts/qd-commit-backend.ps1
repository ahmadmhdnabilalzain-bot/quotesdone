$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Opera\quotesdone'
git add supabase/functions/supplier_portal/index.ts supabase/functions/supplier_api/index.ts supabase/functions/stripe_webhook/index.ts scripts/
$msg = @"
Supplier portal backend: document coverage, registration payment, quote preflight

supplier_portal v4
- DOC_KINDS held a single entry (iso), so save_documents could write an ISO
  certificate and nothing else. The trade licence and company profile rendered
  read-only, and VAT / insurance / manufacturer authorisation had no UI at all.
  fn_supplier_expiries raises "Insurance has expired - upload a renewed copy to
  stay eligible" and routes to the documents tab, where no insurance field
  existed. An established supplier also had no way to replace an expired trade
  licence, because the only licence upload lives in ProfileForm, which renders
  only while the account still has no company. Both read and write now derive
  from one map covering all nine document types.
- save_documents swallowed upload failures and still reported the kind as saved,
  so a supplier could be told their licence was on file when the storage write
  had failed. Failures are now returned to the caller.
- New eligibility action: a why-am-I-not-matched diagnostic evaluated against the
  real clauses in match_suppliers_kw. Document expiry is deliberately NOT listed
  as blocking, because match_suppliers_kw has no expiry clause - claiming
  otherwise would repeat the false promise the alert copy already makes.

supplier_api
- pay_registration wrote registration_status:'paid' and registration_fee_due:0
  directly, with no payment taken, no Stripe call and no webhook. Any supplier
  holding a valid JWT could clear their own AED 1,000 fee with a single POST.
  Dormant only because every supplier is inside the free tier. It now creates a
  Stripe Checkout Session and nothing else, matching the discipline supplier_pay
  already applied to supplier_dues.
- process_docs assigned catalog_doc_paths wholesale, wiping every catalogue the
  supplier had already uploaded the moment they added one more. Now appends.
- submit_quote accepts dry_run: runs the real scorer and the real accept rule,
  then stops - no status change, no customer notification. fn_quote_coach is not
  called because it queues an email that must not fire mid-edit. Returns
  accept_via so the portal can show that a quote passing via form_complete at 65
  is still going out without per-item pricing.

stripe_webhook v5
- Handles kind=supplier_registration. This is now the only place
  leads.registration_status is set to paid, on a signature-verified event.
  Guarded against duplicate delivery so a repeat webhook cannot silently extend
  the expiry by another year.

Verified: deno check reports zero new type errors on all three (baselines carry
the same pre-existing counts). Webhook rejects unsigned and forged events,
including a forged supplier_registration payload.
"@
git commit -m $msg | Out-Null
git log --oneline -1
git status --porcelain -- supabase/functions | Select-Object -First 5
