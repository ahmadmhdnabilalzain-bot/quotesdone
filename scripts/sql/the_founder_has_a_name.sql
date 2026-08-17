-- ---------------------------------------------------------------------------------------------
-- THE FOUNDER HAS A NAME, AND THE SYSTEM DID NOT KNOW IT.
--
-- Founder, 16 Aug 2026: "founder is Ahmad Alzain and his mobile number is 0509319355 and his
-- email is management@quotesdone.com."
--
-- Checked against every place the database stores an identity:
--   email   management@quotesdone.com   MATCHES app_secrets.admin_emails (first entry) and
--                                       phase_c_founder_identity; auth.users last sign-in
--                                       15 Aug 2026 11:21 UTC.
--   mobile  0509319355                  MATCHES app_secrets.admin_mfa_phone (+971509319355)
--                                       exactly, in international form.
--   name    Ahmad Alzain                APPEARS NOWHERE. Not in app_secrets, not in
--                                       phase_c_founder_identity, not in auth.users, not in
--                                       customers. The company has been addressing its founder as
--                                       an email string for its entire existence.
--
-- That last one is this codebase's most expensive recurring defect in miniature - work addressed
-- to an identity nobody models. The morning brief says "Good morning" to no one; the founder queue
-- is "waiting on you" with no idea who "you" is; the escalation emails open with an address.
--
-- One canonical record, three keys, and it also repairs a dead reference: fn_page_high_agent_action
-- already reads app_secrets.founder_email as its FIRST choice of recipient and that key has never
-- existed, so it has always silently fallen through to splitting admin_emails on a comma. The
-- lookup was written for a fact nobody had stored. Now it resolves.
--
-- admin_emails is deliberately NOT changed. It is the authorisation allow-list - who MAY act - and
-- that is a different question from who the founder IS. Collapsing the two would mean a second
-- administrator could not exist without becoming the founder.
-- ---------------------------------------------------------------------------------------------

insert into public.app_secrets (key, value) values
  ('founder_name',   'Ahmad Alzain'),
  ('founder_email',  'management@quotesdone.com'),
  ('founder_mobile', '+971509319355')
on conflict (key) do update set value = excluded.value;

-- The Command Center door gains the name too, so an audit row can say who acted rather than only
-- which address was used.
alter table public.phase_c_founder_identity
  add column if not exists display_name text;

update public.phase_c_founder_identity
   set display_name = 'Ahmad Alzain'
 where identity = 'management@quotesdone.com';

update public.phase_c_founder_identity
   set display_name = 'Not a person - the open door while build mode is on'
 where identity = 'build-mode@quotesdone.local';
