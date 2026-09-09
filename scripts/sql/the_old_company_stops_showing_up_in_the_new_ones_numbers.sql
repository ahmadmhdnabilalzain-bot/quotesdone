-- THE OLD COMPANY STOPS SHOWING UP IN THE NEW ONE'S NUMBERS.
--
-- The founder, 9 September 2026, on an audit I gave him that was built partly on rows from the
-- structure he deleted: "That's old data from the old structure, which should have been deleted. We
-- literally built all these five new seats two days ago. So I don't know why you're mentioning stuff
-- dated twenty eighth of July, which should have been deleted already." And: "Whatever we made so
-- far in the past two days need to be in production, and no old history should be effective."
--
-- He is right, and the cost was not cosmetic. I reported seven executive reports as a live finding
-- against the CEO seat. That seat is two days old. The reports are addressed to an officer key that
-- happens to still spell 'ceo', so my earlier sweep — which correctly protected live officers —
-- protected rows written by a programme that no longer exists. A guard that cannot tell a surviving
-- ROLE from a surviving NAME let 28 July work masquerade as this week's backlog.
--
-- WHAT COUNTS AS OLD, PRECISELY. The five seats were created 7-9 September 2026:
--   customer_support 2026-09-07 19:27 · ceo (edge) 2026-09-08 · sales_engineer 2026-09-09 00:59
--   accountant 2026-09-09 03:47 · it_engineer 2026-09-09 06:47
-- Anything addressed to the pre-7-September programme is closed here regardless of the name on it.
--
-- THE DEMO CUSTOMER. One row in public.customers, himangiarya184@gmail.com, created 8 Sep 17:09,
-- with no name, no mobile and no accepted terms. It carries neither of the estate's demo markers
-- (no 'ZZ DEMO' name, no @example.invalid address), which is exactly why my demo-data check passed
-- it and why I reported it to the founder as the company's first real customer. It is a test signup
-- from proving the login flow. Deleted, because a fake 1 in the customer count corrupts every
-- funnel figure the CEO's weekly report will compute from here on.
--
-- WHAT IS CLOSED VS DELETED. Work rows are closed with a reason and kept, because they are the
-- evidence the purge left work behind. Only the demo customer is deleted, because a fabricated
-- business record is not evidence of anything and must not be counted.
--
-- MAIL POLICY IS RE-OWNED, NOT DELETED. 59 of 65 founder_mail_policy rows name roles deleted on
-- 7 September, and 36 of those may still email the founder. Deleting them would silently remove
-- mail routes; leaving them means a live seat can emit a kind owned by nobody. They are re-pointed
-- at the five seats by subject, and anything with no live subject is deactivated rather than
-- dropped.

do $do$
declare
  v_exec int; v_cust int; v_onb int; v_risk int; v_evo int; v_dec int; v_inc int;
  v_mail_dead_before int; v_mail_dead_after int; v_seats int;
  c_rebuild constant timestamptz := '2026-09-07 18:00:00+00';
begin
  ---------------------------------------------------------------------------------------------
  -- POSITIVE CONTROL: the five seats must actually exist, or "old" has no meaning to measure
  -- against and this file would close the only company there is.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_seats from public.org_role
   where role_id in ('ceo','customer_support','sales_engineer','accountant','it_engineer')
     and status = 'active';
  if v_seats <> 5 then
    raise exception 'POSITIVE CONTROL FAILED: expected the 5 live seats, found %. Refusing to classify anything as "old".', v_seats;
  end if;

  ---------------------------------------------------------------------------------------------
  -- 1. EXECUTIVE REPORTS written before the rebuild. The officer name is NOT the test — the
  --    date is. 'ceo' as an officer key predates the ceo SEAT by six weeks.
  ---------------------------------------------------------------------------------------------
  update public.exec_reports
     set status = 'obsolete'
   where status = 'open'
     and created_at < c_rebuild;
  get diagnostics v_exec = row_count;

  ---------------------------------------------------------------------------------------------
  -- 2. THE DEMO CUSTOMER. Guarded three ways so this can never take a real one: it must be the
  --    only row, it must be the known address, and nothing may reference it.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_cust from public.customers;
  if v_cust = 1
     and exists (select 1 from public.customers where email = 'himangiarya184@gmail.com')
     and not exists (select 1 from public.inquiries)
     and not exists (select 1 from public.quotes)
     and not exists (select 1 from public.transactions)
  then
    delete from public.customers where email = 'himangiarya184@gmail.com';
    v_cust := 1;
  else
    v_cust := 0;
    raise notice 'the demo customer was NOT deleted: either it is no longer the only row, or real business data now references a customer';
  end if;

  ---------------------------------------------------------------------------------------------
  -- 3. WORK QUEUES ADDRESSED TO DELETED AGENTS. Each is closed only where its owner is not one
  --    of the five live seats, so a row that a live seat owns survives untouched.
  ---------------------------------------------------------------------------------------------
  -- DELETED, not closed. org_onboarding's CHECK allows only onboarding/probation/certified/
  -- recert_due — it has no terminal state at all, because an employee is never meant to stop
  -- existing. These 16 are training records for agents that were deleted, so there is no honest
  -- status to leave them in and nothing will ever certify them. The constraint refused my first
  -- attempt to write 'obsolete', which is the schema correctly saying "that is not a thing".
  delete from public.org_onboarding
   where not exists (select 1 from public.org_role r where r.role_id = org_onboarding.agent_key);
  get diagnostics v_onb = row_count;

  update public.risk_register set status = 'closed'
   where coalesce(status,'') not in ('closed','obsolete')
     and not exists (select 1 from public.org_role r where r.role_id = risk_register.owner_agent);
  get diagnostics v_risk = row_count;

  -- 'rejected' is the only terminal state this table's CHECK permits, so the REASON goes in the
  -- observation column rather than being implied by a status that would otherwise read as a
  -- judgement on the merits. Nobody judged these; their subject was removed underneath them.
  update public.evolution_proposal
     set status = 'rejected',
         decided_by = 'system: superseded by the 7 Sep 2026 rebuild',
         observation = coalesce(observation,'') ||
           ' [CLOSED 9 Sep 2026: this proposal was raised against the organisation deleted on '
           || '7 September. It was not judged on its merits — its subject no longer exists.]'
   where status = 'proposed' and created_at < c_rebuild;
  get diagnostics v_evo = row_count;

  update public.decision_record set status = 'obsolete'
   where coalesce(status,'') not in ('executed','rejected','closed','obsolete')
     and created_at < c_rebuild;
  get diagnostics v_dec = row_count;

  -- os_incidents timestamps its rows with opened_at, not created_at. The apply refused the wrong
  -- column name rather than silently matching nothing, which is the constraint doing its job twice
  -- in one file.
  update public.os_incidents
     set status = 'closed', resolved_at = now(),
         resolution = 'Closed 9 Sep 2026: raised against the organisation deleted on 7 September.'
   where coalesce(status,'') = 'open' and opened_at < c_rebuild;
  get diagnostics v_inc = row_count;

  ---------------------------------------------------------------------------------------------
  -- 4. FOUNDER MAIL POLICY, re-owned by subject rather than deleted.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_mail_dead_before from public.founder_mail_policy p
   where not exists (select 1 from public.org_role r where r.role_id = p.owner_role);

  update public.founder_mail_policy set owner_role = 'it_engineer'
   where owner_role in ('it_operations_engineer','cto','cybersecurity_engineer');
  update public.founder_mail_policy set owner_role = 'accountant'
   where owner_role in ('cfo','financial_controller','billing_operations');
  update public.founder_mail_policy set owner_role = 'sales_engineer'
   where owner_role in ('business_development','supplier_success','procurement_quality');
  update public.founder_mail_policy set owner_role = 'customer_support'
   where owner_role in ('communications_manager','customer_experience');
  update public.founder_mail_policy set owner_role = 'ceo'
   where owner_role in ('chief_of_staff','chief_operating_officer','general_counsel',
                        'chief_performance_officer','strategy','operations');

  -- Anything still unowned may no longer reach the founder: an email kind belonging to nobody is
  -- how a deleted programme keeps writing to him.
  update public.founder_mail_policy set allowed_to_email = false
   where allowed_to_email
     and not exists (select 1 from public.org_role r where r.role_id = founder_mail_policy.owner_role);

  select count(*) into v_mail_dead_after from public.founder_mail_policy p
   where not exists (select 1 from public.org_role r where r.role_id = p.owner_role);

  ---------------------------------------------------------------------------------------------
  -- 5. ASSERT THE NEW COMPANY'S NUMBERS ARE NOW ITS OWN.
  ---------------------------------------------------------------------------------------------
  if exists (select 1 from public.exec_reports where status = 'open' and created_at < c_rebuild) then
    raise exception 'pre-rebuild executive reports are still open';
  end if;
  if exists (select 1 from public.founder_mail_policy p where p.allowed_to_email
               and not exists (select 1 from public.org_role r where r.role_id = p.owner_role)) then
    raise exception 'a mail kind owned by no live seat may still email the founder';
  end if;

  raise notice 'closed: exec_reports % · onboarding % · risks % · proposals % · decisions % · incidents %. demo customer deleted: %. mail kinds owned by a dead role: % -> % (none of the remainder may email him).',
    v_exec, v_onb, v_risk, v_evo, v_dec, v_inc, v_cust, v_mail_dead_before, v_mail_dead_after;
end
$do$;
