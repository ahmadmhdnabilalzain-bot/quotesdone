---
name: supplier-portal-tab-spec-15-sep
description: "Founder's 15 Sep 2026 spec for the supplier portal's tabs and the quotation-review chat (instructions 435-437); API-first for a future mobile app"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T10:57:53.029Z
---

Founder, 15 Sep 2026 (founder_instruction 435), the supplier portal after sign-in:

**Tabs, in order:**
1. **Services checklist.** THE main cross-matching source.
   - The sales engineer auto-fills a ready checklist as checkboxes.
   - The supplier adds extra services by text or by voice-to-text.
2. **Inquiries received.** Each inquiry has an ID (job number) and opens the sales engineer's template with all requirements. BOQ and drawings are downloadable (redacted).
3. **Quotations submitted.** The same list. Clicking one opens a CHAT with the sales engineer:
   - the supplier uploads a quotation;
   - an immediate rules-based review runs, with a "Reviewing your quotation, please wait…" animation;
   - it answers either "Quotation approved for submission" or with the adjustments and clarifications needed;
   - the conversation stays free until everything is clear;
   - finally it asks: re-upload a new version, or shall the engineer generate it? Then the conversation ends.

   The founder called this "the most important part in the whole supplier portal … built perfectly".
4. **Messages.** A supplier↔customer mailbox, gated on the customer paying the reveal fee. Otherwise a professional "available after you win a job" state.
5. **Documents.** Free upload of supporting documents.
6. **Insights.** Pricing against the market, hints, and totals: inquiries received, quotations submitted, jobs won, revenue. Visual, not text.

**At sign-up, the emirates served** are one checkbox per emirate plus select-all, not text.

**Decisions:**
- **Instruction 436:** "we cant use the browser built in. later this will be a mobile app as well. the structure need to be built in already". Build API-first: server actions with typed contracts and docs/api/*.md files; React is only a client.
  - Voice-to-text goes through the existing server `transcribe` function (ai_gateway → OpenRouter, ON HOLD). It sits behind a feature flag that is OFF; the mic shows "coming soon". NEVER add another STT provider and NEVER ask to lift the hold ([[never-raise-openrouter-again]]).
- **Instruction 437, "drop it":** the "Get matched" overview is removed and suppliers land on Services.
  - Alerts go to the bell.
  - The mandatory-six checklist goes to the top of Documents.
  - Stats go to Insights.
- **My calls, stated to him:** Profile, Billing and Settings go in the account menu, and Projects (won jobs) fold into Messages.
- The quote review is deterministic (exact specs per line, BOQ lines priced, quantities and units, VAT basis with no invented TRN, validity, lead time). "Generate" means the standard quote_pdf.

**Builds launched about 10:05Z, in three worktrees:**
- **A:** Services tab and emirate checkboxes.
- **B:** Inquiries received, Quotations submitted and the review chat.
- **C:** Messages gate, Documents, Insights, navigation, and the AR fixes (the documents-unlock panel in English, "00%", the clipped SHORTLIST).

Each keeps its SupplierPortal.tsx edits minimal. The merges are serialized.

**Progress:**
- **#722 merged as 1710fda (~10:35Z).** Builders B and C were told to merge main. C wires 'services' as the landing tab and removes Get matched.
- **#722 (Services tab and emirate checkboxes):** SQL `a_supplier_states_its_services_from_a_checklist_the_sales_engineer_prepares.sql` applied ~10:25Z. It adds 200 services across 40 trades, the voice flag `decision_policy.supplier_voice_input_enabled` = `{"enabled": false}` (off), and the `supplier_voice_note` audit. The merge chain is running; the merge deploys `supplier_api` with the actions `services_state`, `services_resolve`, `services_save` and `transcribe_service_note`.
- **GAP (next build after the tabs):** ticked services reach matching only through their TRADES (`supplier_capabilities.services` stores `<trade>.<code>`); `fn_match_capability` is unchanged. The founder called services "our cross matching main source", so matching should use service-level codes when an inquiry names specific services. That needs the inquiry side mapped to service codes.

**CORRECTION, founder_instruction 438 (15 Sep 2026):** "for adding services its not a checkbox or drop down menu. i told you its a voice to text or text box. once filled the sales engineer will rewrite that professionally since he will cross match based on that".
- Adding services is a text box or voice only. #722's "add a trade" dropdown is to be removed. The only checkboxes are the ready list the sales engineer pre-fills.
- The sales engineer rewrites the free text into standard service names deterministically, using EN+AR aliases (the LLM is on hold). Unknown phrases are tidied and flagged for the sales engineer, never dropped.
- The supplier confirms the rewrite.
- Matching runs service-level on the confirmed rewrite (this closes the GAP above).
- A rework builder was launched around 10:50Z.

**~10:55Z:**
- **#723** (Messages gate, Documents, Insights, tab shell, Services landing, Get matched removed) is MERGED as d986358. supplier_portal v61 and messages_api v67 were deployed before the merge. Screenshots are in Downloads/"Messages, Documents and Insights".
  - Leftover: one English line on AR "Recommended for you".
- **#724** (enqueue regression) SQL is applied and dropbox_backup is deployed. Measured: enqueue 2.9 s, backfill 0.3 s (368 queued). The stopgap loop is stopped.
  - The PR probe can't run: it needs a demo lead, and none exists. Fix the probe to seed its own.
  - The merge chain is running.
- **Still open:** #725 (Inquiries + Quotations review chat; told to merge main) and the Services text/voice rework.

Related: [[supplier-portal-build-15-sep]], [[supplier-verification-mandatory-six]], [[exact-specs-or-the-quote-is-held]].
