---
name: a-contact-only-terms-version-asks-nobody-to-sign-again
description: Supplier Agreement v17 (2 Nov 2026) changes the contact line only; app_secrets supplier_terms_carries_from = 'v16' makes every v16 acceptance stand, so nobody re-signs. Deploy the functions BEFORE the apply.
metadata:
  node_type: memory
  type: project
---

**What happened (ceo, 2 Nov 2026, ledger 1482).** The founder's personal mobile (+971 50 931 9355) was printed on
/privacy, /cookie-policy and /supplier-agreement (and in the signed Supplier Agreement body). Public calling is
+971 56 791 8605, WhatsApp +1 218 316 6814. Privacy 1.8, Cookie Policy 1.5 and Supplier Agreement v17 change the contact
line, the label/date and a one-paragraph notice, nothing else
(`scripts/checks/the_founders_mobile_is_in_no_current_public_text_and_a_contact_only_version_asks_nobody_to_sign_again.test.mjs`
undoes exactly those edits and reproduces the old text's hash). Registry SQL:
`scripts/sql/the_founders_mobile_leaves_the_current_legal_texts.sql`.

**The trap.** Every acceptance gate was `accepted_terms_version === current` (SupplierPortal `needsReaccept`, supplier_api
save_profile, kyc accept_terms). A new version number alone would have sent 47 signed suppliers to the re-acceptance card and made
kyc write a second acceptance and a second certificate. The fix is `acceptanceStands()` in `_shared/supplier_terms.ts`: an
acceptance of a version listed in `app_secrets.supplier_terms_carries_from` counts as accepted. The acceptance row is never
rewritten; a v16 supplier stays v16 with the SHA-256 of the v16 text, kept byte-exact at /supplier-agreement/v16 and in
`legal_documents` (`supplier-agreement-v16`). A MATERIAL version publishes that key empty.

**Order.** Deploy supplier_api and kyc (and the web build) first, apply the SQL second. Applied first, the old strict compare
sees v17 against v16 and re-asks everyone.

**Archived pages.** Superseded versions stay served and noindex (a signer's link must work) but are no longer in the sitemap.
They still print the old mobile when opened by URL: /supplier-agreement/v10 to v16 and /privacy/v1.6, both languages. Signed
evidence is why the agreement pages cannot be removed; privacy 1.6 and earlier unsigned texts could be, on the founder's word.

**Still printing the mobile (not fixed by this change):** live routines fn_wa_route, fn_text_did_not_survive_reply,
fn_support_knowledge_gap; company_faq 620 and 622 (Arabic); social_reply_library; pages `about`; the knowledge seed
supabase/seeds/agent_knowledge.seed.sql and ai-organization/org-as-code/agent_knowledge.json (corporate-kit copies).
