-- COMPONENT 15 — "Who can help?" and "Who owns this process?" must name a party that exists.
--
-- Measured on production 6 Aug 2026: org_departments holds 15 rows, and TWO of them have zero
-- employees — supplier_success (0) and analytics (0). Four collaboration_rule declarations point at
-- supplier_success:
--
--   #2  owner_dept    = supplier_success   ("Approving a supplier whose documents are incomplete")
--   #5  must_involve  = {analytics, supplier_success}
--   #8  must_involve  = {supplier_success, customer_success}
--   #1  may_challenge = {customer_success, supplier_success}
--   #10 may_challenge = {analytics, supplier_success, customer_success}
--
-- Nobody works in supplier_success, so a rule that names it names nobody: the situation it governs
-- is owned by no employee and the helper it summons does not exist. The people who actually do this
-- work are elsewhere and are named — `onboarding` is the Supplier Success Manager and is an ACTIVE
-- employee of `procurement`, alongside supplier_verification and eight others.
--
-- So the declarations are repointed at the parties that exist, NOT at the vacant unit:
--   owner_dept      -> procurement   (a department, because fn_task_review matches owner_dept
--                                     against org_tasks.dept_key; supplier onboarding tasks are
--                                     raised in procurement)
--   must_involve    -> onboarding    (the named Supplier Success Manager — the person, since
--                                     must_involve is a helper and a helper is a party)
--   may_challenge   -> procurement / intelligence (fn_challenge takes a DEPARTMENT as challenger
--                                     and records it on challenge_record.challenged_by; 'analytics'
--                                     as a department has no staff, and the company's analysts —
--                                     market_analyst, forecast_analyst, supplier_analyst — sit in
--                                     intelligence)
--
-- `analytics` is left alone inside must_involve: it resolves there as an ACTIVE EMPLOYEE (the Data
-- & Analytics Engineer in `it`), which is a real party. Only the DEPARTMENT reading of the name is
-- vacant, and only may_challenge reads it that way.
--
-- This is a correction of who the rules point at, not a widening of them: every rule keeps the same
-- number of helpers, reviewers and challengers, and no rule is removed.
update public.collaboration_rule set owner_dept = 'procurement' where id = 2;

update public.collaboration_rule
   set must_involve = array['analytics','onboarding']::text[] where id = 5;
update public.collaboration_rule
   set must_involve = array['onboarding','customer_success']::text[] where id = 8;

update public.collaboration_rule
   set may_challenge = array['customer_success','procurement']::text[] where id = 1;
update public.collaboration_rule
   set may_challenge = array['intelligence','procurement','customer_success']::text[] where id = 10;

-- Post-condition, asserted rather than assumed: no member of must_involve, must_review or
-- may_challenge, and no owner_dept, may name a party the org model does not staff. This raises on
-- staging BEFORE anything is promoted, so a repointing that misses a row cannot reach production.
do $$
declare v_bad int;
begin
  select count(*) into v_bad from (
    select x from public.collaboration_rule c,
           unnest(coalesce(c.must_involve,'{}'::text[])
                  || coalesce(c.must_review,'{}'::text[])
                  || coalesce(c.may_challenge,'{}'::text[])
                  || array[c.owner_dept]) x
     where x is not null
       and not exists (select 1 from public.org_agents a where a.agent_key = x and a.active)
       and not exists (select 1 from public.org_departments d where d.dept_key = x
                       and exists (select 1 from public.org_agents a2
                                    where a2.department = d.dept_key and a2.active))) s;
  if v_bad > 0 then
    raise exception 'collaboration_rule still names % part(ies) with no active employee', v_bad;
  end if;
end $$;
