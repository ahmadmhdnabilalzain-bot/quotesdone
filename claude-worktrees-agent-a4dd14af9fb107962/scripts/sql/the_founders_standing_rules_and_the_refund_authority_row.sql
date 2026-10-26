-- THE FOUNDER'S STANDING RULES AND THE REFUND AUTHORITY ROW (6 Sep 2026).
--
-- Two things the knowledge plan (docs/KNOWLEDGE_PLAN_2026-09-06.md §5, rows 9 and 15) still had open:
--   * employee_authority granted followup `refund_within_window` AUTONOMOUS at AED 10,000 while the
--     founder's ruling of 17 Aug 2026 ("every refund needs me"), restated on 6 Sep 2026 with the
--     ladder ("on the 5th day i should be notified to do a final call ... if no response we issue the
--     refund"), makes every refund his decision. The row becomes advisory at 0: followup prepares and
--     chases; the founder decides; the existing refund door executes.
--   * His standing rules lived in .claude/skills and memory, not in any row an agent reads. They are
--     now decisions in company_policy_decision, rendered by fn_company_self_knowledge_sync as
--     qd-company:decisions like the other rulings of the day, so every employee head carries them.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founders_standing_rules_and_the_refund_authority_row.sql --apply --ddl

begin;

update public.employee_authority
   set max_tier = 'advisory', threshold_aed = 0,
       note = 'Prepares and chases the refund case (the 5-working-day ladder); execution is the founder''s decision — ruling 17 Aug 2026, restated 6 Sep 2026 — through the existing refund door.'
 where agent_key = 'followup' and action_class = 'refund_within_window';

insert into public.company_policy_decision (decision_key, decided_on, decided_by, decision_text, applies_to, never_ask_again)
values
 ('refund_ladder', '2026-09-06', 'founder',
  'Refund policy: five working days from the time the customer pays. After three working days with no response from the supplier, the employee who owns supplier follow-up chases them. On the fifth day the founder is notified to make the final call. If there is still no response, the refund is issued; banks usually take 7-14 working days to show it. The refund admin fee is AED 250 and stays. The 3% the customer paid is refunded to the customer in full; the AED 250 and 9% per year interest (the UAE statutory maximum) are charged to the supplier. Update everywhere; never ask again.',
  '{refunds,followup,cfo,customer_experience,legal}', true),
 ('every_refund_is_the_founders', '2026-08-17', 'founder',
  'Every refund, of any amount, is the founder''s decision. No employee issues a refund autonomously; employees prepare the case, chase the supplier, and put the final call to him on day five of the ladder. Nothing else in the company routes to his approval.',
  '{refunds,employee_authority,founder_review_gates}', true),
 ('supplier_acquisition_and_screening', '2026-09-06', 'founder',
  'The supplier invite campaign starts from the leads the company holds; the existing business-development employee tracks the inbound emails, sources new leads and contacts them to register; the target is at least 300 supplier registrations a month. None of it runs until the founder says the app is perfect (app_secrets.supplier_outreach_golive). The existing compliance employee checks the sanctions lists weekly and tells the team when a registered supplier appears on one so he is removed. These are the existing employees'' tasks, not new agents.',
  '{business_development,compliance_and_privacy_officer,suppliers}', true),
 ('whatsapp_and_brand', '2026-09-06', 'founder',
  'The Twilio WhatsApp credentials are with the company: the team fixes and submits templates itself. The brand kit the founder supplied is the reference for every output; it may be upgraded except the logo; it lives in company knowledge (qd-company:brand) so nobody asks for it again.',
  '{marketing,design,messaging,reports}', true),
 ('founder_standing_rules', '2026-09-06', 'founder',
  'Standing rules: (1) nothing needs the founder''s approval except Stripe refunds; (2) he is emailed exceptions only (founder_mail_policy) — everything else becomes the owning employee''s task; (3) he is never asked technical questions — engineering decides, does, and records the reasoning; he sets boundaries, not methods; (4) a session reports one completion line only when everything is verified and deployed, otherwise an honest hand-over; (5) WhatsApp is his command channel; (6) money above AED 10,000, destructive production changes and facts only he holds are the three things that escalate to him; (7) paid inference stays off until he activates it and he recharges the credit himself; (8) the OS stays signed in for him and the company solves its own problems.',
  '{every_employee}', true)
on conflict (decision_key) do update
   set decided_on = excluded.decided_on, decision_text = excluded.decision_text, applies_to = excluded.applies_to, never_ask_again = excluded.never_ask_again;

select public.fn_company_self_knowledge_sync();

do $$
declare v text; n int;
begin
  select max_tier into v from public.employee_authority where agent_key = 'followup' and action_class = 'refund_within_window';
  if v is distinct from 'advisory' then raise exception 'followup refund authority is %', v; end if;
  select count(*) into n from public.ops_knowledge where content like '%Standing rules: (1) nothing needs%';
  if n = 0 then raise exception 'qd-company:decisions does not carry the standing rules'; end if;
  select count(*) into n from public.ops_knowledge where content like '%five working days from the time the customer pays%';
  if n = 0 then raise exception 'qd-company:decisions does not carry the refund ladder'; end if;
end $$;

commit;
