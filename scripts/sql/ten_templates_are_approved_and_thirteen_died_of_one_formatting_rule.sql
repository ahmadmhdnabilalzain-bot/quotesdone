-- TEN TEMPLATES ARE APPROVED, AND THIRTEEN DIED OF ONE FORMATTING RULE
--
-- Founder, 7 September 2026: "we have submitted meta approval 10 times maybe. why its not approved
-- till now?"
--
-- Asked Twilio's Content API directly rather than guessing. The answer contradicts what this estate
-- has been telling itself, including what I wrote into the channel policy two hours ago.
--
--   32 templates submitted.  10 APPROVED.  14 rejected.  3 pending.  5 never submitted.
--
-- THIRTEEN OF THE FOURTEEN REJECTIONS ARE ONE CAUSE, REPEATED:
--   "Variables can't be at the start or end of the template."
-- That is a Meta formatting rule: a template body may not begin or end with a {{1}} placeholder. It
-- was hit thirteen times, which means the same defect was resubmitted rather than read. The fix is a
-- sentence of static text before the first variable and after the last one, and it is the whole fix.
--
-- The fourteenth is different and needs a person, not a code change:
--   "This WhatsApp business account does not have permission to create message template"
-- on an AUTHENTICATION-category template. Authentication templates need that category enabled on the
-- WhatsApp Business Account; the platform refused before Meta ever reviewed the content.
--
-- WHAT THIS CORRECTS. I recorded WhatsApp as blocked partly "for want of an approved template". That
-- was wrong. Ten are approved, and among them is exactly the one the founder's licence-renewal flow
-- needs, approved since 21 July:
--     quotesdone_supplier_doc_expiry_en_mruoodat   UTILITY
--     quotesdone_supplier_doc_expiry_ar_mruoofbi   MARKETING
-- Also approved: new quote to a customer, supplier unlocked, new inquiry to a supplier, and quote
-- accepted, each in English and Arabic.
--
-- SO THE REAL GATE IS NOT THE TEMPLATE. It is opt-in: no contact has recorded consent to be messaged,
-- and the code path reaches for 'founder_alert', which is one of the three still pending. The estate
-- has been reporting a template problem and holding an opt-in problem.

begin;

create table if not exists public.wa_template_registry (
  template_name   text primary key,
  language        text not null,
  category        text not null,
  status          text not null check (status in ('approved','pending','rejected','unsubmitted')),
  purpose         text not null,
  approved_on     date,
  rejection_cause text,
  checked_at      timestamptz not null default now(),
  source          text not null default 'Twilio Content API'
);

comment on table public.wa_template_registry is
  'What Meta has actually approved, read from the provider rather than assumed. The estate spent weeks reporting a template problem while holding an opt-in problem.';

insert into public.wa_template_registry
  (template_name, language, category, status, purpose, approved_on) values
  ('quotesdone_supplier_doc_expiry_en_mruoodat','en','UTILITY','approved',
   'Tells a supplier a document is expiring and asks for the renewed copy. THIS IS THE ONE THE LICENCE FLOW NEEDS.','2026-07-21'),
  ('quotesdone_supplier_doc_expiry_ar_mruoofbi','ar','MARKETING','approved',
   'Arabic of the above.','2026-07-21'),
  ('quotesdone_customer_new_quote_en','en','UTILITY','approved','Tells a buyer a new quote has arrived.','2026-07-01'),
  ('quotesdone_customer_new_quote_ar','ar','MARKETING','approved','Arabic of the above.','2026-07-01'),
  ('quotesdone_customer_supplier_unlocked_en','en','UTILITY','approved','Confirms a reveal to the buyer.','2026-07-01'),
  ('quotesdone_customer_supplier_unlocked_ar','ar','UTILITY','approved','Arabic of the above.','2026-07-01'),
  ('quotesdone_supplier_new_inquiry_en','en','MARKETING','approved','Tells a supplier a request in their category is open.','2026-07-01'),
  ('quotesdone_supplier_new_inquiry_ar','ar','UTILITY','approved','Arabic of the above.','2026-07-01'),
  ('quotesdone_supplier_quote_accepted_en','en','UTILITY','approved','Tells a supplier their quote was accepted. THE JOBS-AWARDED NOTIFICATION.','2026-09-03'),
  ('quotesdone_supplier_quote_accepted_ar','ar','UTILITY','approved','Arabic of the above.','2026-09-03')
on conflict (template_name) do update set
  status = excluded.status, category = excluded.category,
  purpose = excluded.purpose, approved_on = excluded.approved_on, checked_at = now();

insert into public.wa_template_registry
  (template_name, language, category, status, purpose, rejection_cause) values
  ('_13_rejected_for_variable_placement','--','--','rejected',
   'Thirteen separate templates, all refused for the same reason and resubmitted without reading it.',
   'Meta: "Variables can''t be at the start or end of the template." A body may not begin or end with a {{1}} placeholder. Fix: put a sentence of static text before the first variable and after the last.'),
  ('quotesdone_control_mode_code','en','AUTHENTICATION','rejected',
   'A one-time code template for control mode.',
   'Meta: "This WhatsApp business account does not have permission to create message template." AUTHENTICATION category is not enabled on the WABA. This needs a person to enable it in Meta Business Manager; no code change will pass it.')
on conflict (template_name) do update set
  status = excluded.status, rejection_cause = excluded.rejection_cause, checked_at = now();

commit;

-- ---------------------------------------------------------------------------------------------
-- THE CHANNEL POLICY IS CORRECTED. The reason it is blocked was partly wrong.
-- ---------------------------------------------------------------------------------------------

update public.outreach_channel_policy set
  status_reason =
     'CORRECTED 7 Sep 2026 after reading Twilio''s Content API directly. Ten templates ARE approved, '
  || 'including quotesdone_supplier_doc_expiry_en (21 Jul, UTILITY) which is exactly what the licence '
  || 'renewal flow needs, and quotesdone_supplier_quote_accepted_en (3 Sep) which is the jobs-awarded '
  || 'notification. My earlier reason, "no approved template", was wrong. '
  || 'WHAT ACTUALLY BLOCKS IT: no recipient has recorded opt-in, so a business-initiated message would '
  || 'be unsolicited whatever template carries it. Secondly the send path reaches for founder_alert, '
  || 'which is one of the three still pending, so it falls back to email and reports a template problem '
  || 'while the real problem is consent. '
  || 'TO OPEN: capture opt-in at website registration and in the invitation email, then point the send '
  || 'path at an approved template name rather than a pending one.',
  reviewed_at = now()
 where channel_key = 'whatsapp';
