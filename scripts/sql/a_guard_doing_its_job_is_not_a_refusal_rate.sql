-- A GUARD DOING ITS JOB IS NOT A REFUSAL RATE.
--
-- D9 was built minutes ago to close the founder's instruction "every polite refusal is invisible to
-- IT". It works. On its first live read it raised a CRITICAL finding — and the finding is wrong, in
-- the most instructive way available:
--
--   login_otp turned away 100 of 106 callers in 24 hours (94%)
--
-- Broken down, 81 of those 100 are two refusals, and both of them carry the function's own note
-- saying they are deliberate:
--
--   sms_signup_refused  (43)  "This is deliberate: email is the identity, so a phone alone cannot
--                              create an account... Sign-up is by email."
--   ambiguous_phone     (38)  "This is the guard working, not a fault: a shared number cannot
--                              select a person."
--
-- Both are the founder's own ruling — "a phone may confirm, never select; email is the identity" —
-- enforced correctly. So the detector written to stop the estate ignoring real refusals was about
-- to page him at CRITICAL severity because two of his own rules are being obeyed. That is the
-- estate's oldest lens, "a guard that fires when the system works", and I built a fresh instance of
-- it inside the fix for a different one.
--
-- WHY NOT JUST TRUST THE NOTE. The obvious fix is to read the function's own words and skip
-- anything that says "deliberate". That would let any function opt out of monitoring by describing
-- itself flatteringly, and the next one to do it would not be honest. So the exemption is a
-- REGISTER: an explicit (subject, reason) pair someone had to add on purpose, with the founder rule
-- or policy that justifies it written in the row. Adding one is a reviewable act; writing a nice
-- sentence in a log line is not.
--
-- POLICY REFUSALS ARE STILL COUNTED, JUST NOT ALARMED ON. They stay in the tick's notes with their
-- share, because "43 people tried to sign up with a phone number this week" is a product signal
-- worth having — it says the sign-up screen is pointing people at the wrong door. It is simply not
-- an outage, and the difference between those two is the whole point of this file.
--
-- WHAT REMAINS A FAULT AT login_otp. Stripping the two policy reasons leaves 19 refusals of 106 —
-- 18%, below the 50% dominance bar, no baseline to depart from. So the honest verdict today is: no
-- finding, and the real story is the one the CEO's weekly report already names — nobody has claimed
-- a lead, so there is no account for any phone to match.

create table if not exists public.it_refusal_policy (
  subject     text not null,
  reason_key  text not null,
  justification text not null,
  added_at    timestamptz not null default now(),
  primary key (subject, reason_key)
);
comment on table public.it_refusal_policy is
  'Refusals that are the platform enforcing a rule, not failing. D9 counts these but does not alarm on them. Each row must name the rule it enforces: an exemption nobody can justify is an exemption nobody should have granted.';
alter table public.it_refusal_policy enable row level security;
revoke all on public.it_refusal_policy from anon, authenticated;

insert into public.it_refusal_policy (subject, reason_key, justification) values
  ('login_otp','sms_signup_refused',
   'The founder''s ruling: a phone may confirm, never select; email is the identity. Refusing to create an account from a bare phone number is the rule being enforced. It also avoids a paid Twilio send for a code that verification would then refuse.'),
  ('login_otp','ambiguous_phone',
   'The founder''s ruling: a phone may confirm, never select. Where one mobile number reaches more than one account the platform must NOT guess which person is calling; it asks them to sign in by email. In the UAE a shared office landline or company mobile across several registrations is ordinary, so this will be common and is correct.')
on conflict (subject, reason_key) do update set justification = excluded.justification;

-- ── D9 LEARNS THE DIFFERENCE ────────────────────────────────────────────────────────────────────
-- Only the counting clause changes: a run whose counts carry a REGISTERED policy reason for that
-- subject is no longer counted as a fault-refusal. Thresholds, arms, severity mapping, the 20-run
-- floor and the 24-hour window are all untouched.
create or replace function public.fn_it_refusal_is_policy(p_subject text, p_counts jsonb)
returns boolean language sql stable as $fn$
  select exists (
    select 1 from public.it_refusal_policy p
     where p.subject = regexp_replace(coalesce(p_subject,''), '^fn:', '')
       and coalesce(p_counts, '{}'::jsonb) ? p.reason_key)
$fn$;
revoke execute on function public.fn_it_refusal_is_policy(text, jsonb) from public;

do $do$
declare
  v_total int; v_all_ref int; v_fault_ref int; v_policy int; f jsonb; v_found boolean := false;
begin
  -- The numbers that justify the change, measured rather than asserted.
  select count(*) filter (where true),
         count(*) filter (where status in ('skipped','warn')),
         count(*) filter (where status in ('skipped','warn')
                            and public.fn_it_refusal_is_policy(agent, counts)),
         count(*) filter (where status in ('skipped','warn')
                            and not public.fn_it_refusal_is_policy(agent, counts))
    into v_total, v_all_ref, v_policy, v_fault_ref
    from public.agent_runs
   where agent = 'login_otp' and started_at > now() - interval '24 hours';

  if v_policy = 0 then
    raise exception 'POSITIVE CONTROL FAILED: no login_otp refusal matched the register, so this change would not alter anything';
  end if;
  if v_fault_ref >= v_all_ref then
    raise exception 'the register removed nothing (% of % still counted)', v_fault_ref, v_all_ref;
  end if;

  -- NEGATIVE CONTROL: an unregistered reason on the same subject must still count as a fault.
  if public.fn_it_refusal_is_policy('login_otp', '{"some_unregistered_failure": 1}'::jsonb) then
    raise exception 'an unregistered reason was treated as policy — any function could opt out of monitoring';
  end if;
  -- And a registered reason must not leak to a different subject.
  if public.fn_it_refusal_is_policy('send_outbox', '{"sms_signup_refused": 1}'::jsonb) then
    raise exception 'a policy exemption leaked across subjects';
  end if;

  raise notice 'REGISTER LIVE. login_otp in 24h: % runs, % refusals, of which % are registered policy and % are genuine faults (%.0f%% fault share, below the 50%% dominance bar). The critical finding it was about to page him with was two of his own rules being obeyed.',
    v_total, v_all_ref, v_policy, v_fault_ref, (v_fault_ref::numeric / nullif(v_total,0) * 100);
end
$do$;
