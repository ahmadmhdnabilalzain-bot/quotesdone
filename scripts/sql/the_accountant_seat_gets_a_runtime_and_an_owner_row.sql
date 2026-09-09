-- THE ACCOUNTANT SEAT GETS A RUNTIME, AND THE OWNER ROW COMES FIRST.
--
-- The seat itself was established earlier today by
-- scripts/sql/the_company_gets_an_accountant_and_the_money_finally_has_an_owner.sql: org_agents,
-- org_role, the reporting edge to the ceo, five standing grants, the fn.accountant credential and
-- ten payment functions moved to owner 'accountant'. Measured 9 Sep 2026 before writing this file:
-- org_role active = accountant,ceo,customer_support,sales_engineer; org_reporting_edge = 3, all
-- terminating at ceo; ceo_standing_grant for accountant = 5.
--
-- WHAT WAS MISSING was the row that says who owns the seat's OWN edge function. function_owner held
-- 0 rows for slug 'accountant' while the function did not exist, which is correct; this file adds it
-- BEFORE the deploy, so the registry is never behind the estate rather than briefly ahead of it.
-- The same order was used for sales_engineer (see that file's step 8) and for ceo_agent.
--
-- NOTHING ELSE IS TOUCHED. No grant is widened, no credential is minted, no routine is created --
-- so there is no SECURITY DEFINER routine here and no `revoke execute ... from public` to pair with
-- one. An insert with a conflict update is the whole change.

insert into public.function_owner (function_slug, owner, note)
values ('accountant', 'accountant',
        'The Accountant seat''s own runtime. The founder, 9 Sep 2026: "any financial thing on the '
        'platform including refunds. reports to CEO. collects expenses from the email '
        'expenses@mail.quotesdone.com. create weekly report as pdf and share it with me and the '
        'CEO. takes approval from CEO on refunds and Meta ads expenses." Deterministic only, and '
        'no model is called: the seat reads the books (gl_accounts, gl_journal, expenses, '
        'ap_bills) reporting a true zero apart from an unmeasurable figure, answers what it may do '
        'from fn_agent_may_act at call time, and PREPARES a refund -- fn_agent_may_act refuses '
        'every refund amount against this seat''s ceiling of 0, and that refusal is turned into a '
        'CEO decision request through fn_ceo_request_decision. The seat prepares; the CEO decides.')
on conflict (function_slug) do update
  set owner = excluded.owner, note = excluded.note;

-- THE CLOSING ASSERTION. A file that was supposed to register an owner and did not must say so
-- rather than exit 0 quietly.
do $check$
declare
  v_owner int; v_seat int; v_edge int; v_grants int; v_refund_route text;
begin
  select count(*) into v_owner from public.function_owner
   where function_slug = 'accountant' and owner = 'accountant';
  select count(*) into v_seat  from public.org_agents where agent_key = 'accountant' and active;
  select count(*) into v_edge  from public.org_reporting_edge
   where child_role_id = 'accountant' and parent_role_id = 'ceo';
  select count(*) into v_grants from public.ceo_standing_grant where grantee_role_id = 'accountant';

  -- THE ONE BEHAVIOUR THE RUNTIME DEPENDS ON, asserted here rather than assumed by the TypeScript:
  -- a refund must be REFUSED for this seat and must name the CEO as the route. If this ever starts
  -- permitting, the runtime's refund_request would stop routing and nobody would be told.
  select public.fn_agent_may_act('accountant','refund',1) ->> 'route' into v_refund_route;

  if v_owner <> 1 or v_seat <> 1 or v_edge <> 1 or v_grants < 5
     or coalesce(v_refund_route,'') <> 'ceo_case_decision' then
    raise exception 'the accountant seat is not ready for its runtime: owner=% seat=% edge=% grants=% refund_route=%',
      v_owner, v_seat, v_edge, v_grants, coalesce(v_refund_route,'(null)');
  end if;
end $check$;
