-- a_supplier_is_told_approval_is_automatic_when_the_gate_passes.sql
-- Seat: sales_engineer. Supplier journey audit, 28 Oct 2026 (docs/reports/supplier_journey_audit_28_oct/sales_agent).
-- The company knowledge told agents and suppliers two things production does not do:
--   "Today approval is manual; an auto-approve flag ... is currently switched off" -- pricing_config.auto_approve_suppliers
--   is true, and fn_sales_engineer_verifies_supplier approves when the gate passes (SA v16 "Automated decisions");
--   "The trade licence is the only required document" -- the mandatory six (fn_supplier_mandatory_six, SA v16 clause 13)
--   require the licence AND the company profile, both uploaded.
-- knowledge/COMPANY_CANON.md and the brief are corrected in the same commit; this file corrects the live copies of the
-- same canon answers (public.dept_library, searched by agents through dept_library_search) and the two eval references
-- (public.canon_eval_questions). Each update matches the OLD text exactly, so it is idempotent and touches nothing else.
-- Measured 28 Oct 2026, read-only: 5 dept_library rows (ids 1431-1435) and 2 canon_eval_questions rows (ids 18, 38).
-- FOUNDER LEDGER 1469 (2 Nov 2026) is in the new text: a supplier is held (pending / services_unconfirmed) until it confirms the
-- services it provides, so "automatic" is true only once the six are complete, the licence is read and in date AND the services
-- are confirmed. The first draft of this file left the services confirmation out of that condition.
-- Data only: no routine, no table, no grant.
begin;

update public.dept_library set content = replace(content, 'A supplier registers and is approved by providing a contact name, an SMS-verified mobile, a trade licence number, a company profile document, and accepting supplier terms.',
  'A supplier registers and completes the mandatory six: the company''s licensed name, a UAE mobile number verified with a code, a verified work email, the trade licence (uploaded), the company profile (uploaded) and acceptance of the Supplier Agreement.')
  where department = 'company' and content like 'A supplier registers and is approved by providing a contact name, an SMS-verified mobile, a trade licence number, a company profile document, and accepting supplier terms.%';

update public.dept_library set content = 'Open the supplier portal, choose "Create account" with your work email, and complete the mandatory six: the company''s licensed name, a UAE mobile number verified with a code, a verified work email, the trade licence (uploaded), the company profile (uploaded) and acceptance of the Supplier Agreement. The licence number, issuing authority and expiry date are read from the licence itself. Approval follows within 3 working days of complete documents. It is automatic once the six are complete, the licence is read and in date, and you have confirmed the services your company provides in the Services tab of your portal; until you confirm them you are held, and the portal says what is left.'
  where department = 'company' and content = 'You provide a contact name, an SMS-verified mobile number, your trade licence number, a company profile document, and accept the supplier terms. The trade licence is the only required document and is machine-verified by OCR. Approval is targeted within 3 working days.';

update public.dept_library set content = 'Every supplier completes the mandatory six before it can be matched: the company''s licensed name, a UAE mobile number verified with a code, a verified work email, the trade licence (uploaded), the company profile (uploaded) and acceptance of the Supplier Agreement. The licence number, issuing authority and expiry date are read from the licence itself and checked (Supplier Agreement clause 13). This is what lets a quote carry a licence-verified badge.'
  where department = 'company' and content = 'Every supplier provides a trade licence number, the only required document, machine-verified by OCR against the licence itself. They also need a contact name, SMS-verified mobile, a company profile document, and to accept the terms. This is what lets a quote carry a licence-verified badge.';

update public.dept_library set content = 'No. Insurance, ISO, manufacturer authorisation, EGR, and catalogues are all optional; they only widen reach and improve ranking. The two required documents are your trade licence and your company profile, both uploaded.'
  where department = 'company' and content = 'No. Insurance, ISO, manufacturer authorisation, EGR, and catalogues are all optional; they only widen reach and improve ranking. The only required document is your trade licence.';

update public.dept_library set content = 'Within 3 working days of complete documents (Supplier Agreement clause 13). Approval is automatic when the mandatory six are complete, the licence is read and in date, and the supplier has confirmed the services it provides (Services tab); a supplier is held until it confirms them. An expired licence must be renewed first, and a licence that cannot be read in full is held for review; the supplier is told what is pending.'
  where department = 'company' and content = 'Supplier approval is targeted within 3 working days. Today approval is manual; an auto-approve flag exists in the system but is currently switched off.';

update public.canon_eval_questions set reference = 'Complete the mandatory six: the licensed company name, a UAE mobile verified with a code, a verified work email, the trade licence (uploaded), the company profile (uploaded) and acceptance of the Supplier Agreement; approval follows within 3 working days of complete documents, automatically once the licence is read and in date and the supplier has confirmed the services it provides; until it confirms them it is held.'
  where reference = 'Submit a trade licence (the only required document, OCR-verified), verify their mobile via SMS, complete a company profile, and accept the terms; approval follows within 3 working days.';

update public.canon_eval_questions set reference = 'Two documents are required: the trade licence and the company profile, both uploaded. The licence number, issuing authority and expiry date are read from the licence and checked.'
  where reference = 'A trade licence; it is the only required document and is OCR-verified.';

do $$ declare n int; begin
  select count(*) into n from public.dept_library where content ilike '%only required document%' or content ilike '%approval is manual%';
  if n > 0 then raise exception 'dept_library still states the old approval or document rule on % row(s)', n; end if;
  select count(*) into n from public.canon_eval_questions where reference ilike '%only required document%';
  if n > 0 then raise exception 'canon_eval_questions still states the old document rule on % row(s)', n; end if;
end $$;
commit;
