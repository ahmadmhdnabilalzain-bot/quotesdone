-- CUSTOMER EXPERIENCE AND ASSURANCE GET THEIR OWN OPERATING SYSTEM (org audit A4).
--
-- THE GAP, MEASURED. os_department rolled customer_experience into the MARKETPLACE OS and assurance
-- into the OPERATIONS OS, so the ten operating systems mapped to eight owner departments and two of
-- the ten departments — customer_experience (7 roles) and assurance (6 roles, home of the security
-- stop-authority) — were never surfaced in fn_exec_meeting under their own owner. A whole department's
-- reliability, security and customer health hid inside a larger OS's aggregate.
--
-- THE FIX. Two new operating_system rows (Customer Experience OS, Assurance OS), owned by each
-- department's lead, and os_department remapped so each of those two departments maps to ITS OWN OS
-- instead of the parent it was buried in. v_os_scoreboard / v_os_health iterate operating_system
-- LEFT JOIN os_department, so they cover the two new OS with no view change; fn_os_review scores them
-- and fn_exec_meeting surfaces them on its next run. Every one of the ten departments now maps to one
-- operating system and gets a weekly review under an accountable owner.
--
-- Not frozen: operating_system and os_department are operational configuration, absent from every
-- Phase A/B baseline digest (departments/roles/reporting-graph/agents), so this drifts nothing.
--
--   node scripts/apply_sql.mjs scripts/sql/customer_experience_and_assurance_get_their_own_os.sql --apply --ddl

begin;

insert into public.operating_system (os_key, num, name, charter, mandate, owner_agent, mission, adapts_by, active)
values
 ('customer_experience', 11, 'Customer Experience OS',
  'Wins, keeps and grows customers across every channel.',
  'Owns onboarding, support, retention, communications and the customer relationship after the match.',
  'followup',
  'Make every customer succeed and stay, and turn served customers into repeat and referral demand.',
  'Shifts support, onboarding and retention playbooks from satisfaction, churn and response-time signals.',
  true),
 ('assurance', 12, 'Assurance OS',
  'Holds quality, security and reliability independently of the teams it reviews.',
  'Owns QA gates, model evaluation, security, test automation and incident assurance.',
  'qa_manager',
  'Independently assure that what the company ships is correct, secure and reliable.',
  'Tightens gates and test coverage from defect-escape, incident and evaluation signals.',
  true)
on conflict do nothing;

-- Move the two departments off the OS they were buried in and onto their own.
delete from public.os_department where dept_key='customer_experience' and os_key='marketplace';
delete from public.os_department where dept_key='assurance'           and os_key='operations';
insert into public.os_department (os_key, dept_key, note) values
 ('customer_experience','customer_experience',
  'Customer Experience runs its own operating system so the exec meeting surfaces it (org audit A4).'),
 ('assurance','assurance',
  'Assurance runs its own operating system so quality, security and reliability are reviewed independently (org audit A4).')
on conflict do nothing;

commit;
