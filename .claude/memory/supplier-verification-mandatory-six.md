---
name: supplier-verification-mandatory-six
description: "The founder's ruling on what a supplier must provide to be verified — six items, everything else optional"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T09:37:38.510Z
---

Founder ruling, 7 September 2026, in his words: "name/mobile/email/trade license/company
profile/terms and conditions signed copy. nothing else is mandatory, the rest are extra".

**The six mandatory items:**
1. Name
2. Mobile — a **UAE mobile number**, not a landline (founder, 7 Sep 2026: "we need UAE mobile number")
3. Email
4. Trade licence
5. Company profile
6. Terms & Conditions signed copy

**Explicitly NOT mandatory** (they are "extra", nice to have, never a blocker): establishment card,
bank IBAN letter, VAT certificate or TRN, insurance certificate, product catalogue, ISO certificate,
manufacturer authorisation.

**Why:** he was shown a ten-item list from `v_supplier_doc_score` described as mandatory and
challenged it — "10 mandatory requirements? who said so?" The ten came from the view's own scoring
array, which annotates only the trade licence as "(mandatory)". Nobody had ruled on the other nine.
Presenting them as mandatory was an overstatement.

**How to apply:** score suppliers against these six, not against ten. `v_supplier_doc_score` grades
against ten and its grade is therefore NOT the founder's bar — a supplier can be complete on his
list and still score D. Do not use that grade to decide approval or to report readiness. The extra
seven may be collected and displayed, never required. Note that email is the identity here, per
[[a-phone-may-confirm-never-select]], so a record with a landline and no email fails two of the six.

**Since PR #698 (15 Sep 2026) the six are a DATABASE rule.** fn_supplier_mandatory_six checks six codes: reg_name, reg_mobile (OTP-verified UAE +9715), reg_email (verified), reg_licence (the DOCUMENT must exist in supplier-docs; a typed number doesn't count), reg_profile (a document in supplier-docs) and reg_terms (a signed certificate, not a tick). Trigger trg_leads_e0_mandatory_six_gate refuses approved/verified while anything is missing, and demotes an approved supplier when an item is cleared. fn_sales_engineer_verifies_supplier makes the decision, and fn_is_matchable requires approval_status='approved'. The old fn_supplier_licence_gate was dropped on 7 Sep.

**Founder, 15 Sep 2026 (founder_instruction 434): "all 6 are fine. no need for extra mandatory fields."** I asked whether the trade should be a 7th item, since matching needs confirmed trades (Scope tab); he declined. The trade stays OPTIONAL at sign-up. The WhatsApp answer is still required at submit (instruction 391), but it isn't one of the six. Don't propose extra mandatory fields again.

**CUSTOMERS ARE DIFFERENT: FOUR, NOT SIX.** Founder ruling 7 Sep 2026: "mandatory fields are
different for customers. its just mobile, email and name and signed terms and conditions". A buyer
needs NO trade licence and NO company profile. Both sets now live in public.mandatory_field_policy
and are checked by fn_supplier_mandatory_check(lead_id) and fn_customer_mandatory_check(uuid).

Related: [[the-only-hard-rules-and-operating-doctrine]], [[demo-fixture-convention]].
