-- PROBE: THE COMPANY KNOWLEDGE SAYS THE CEO DECIDES, AND THE COMPANY IS SIX SEATS. Seat: ceo. Agent: simplify_build_D, 16 Nov 2026.
-- Pure probe: no DDL, never applied; run after the_company_knowledge_says_the_ceo_decides_and_the_company_is_six_seats.sql on a
-- LOCAL Postgres 16 (never on production) whose pricing_config, company_goals, org_role, company_policy_decision and
-- company_faq hold production's rows (none is secret). It always raises, so the regenerated rows are rolled back.
-- PROBE OK only if, after fn_company_self_knowledge_sync() runs again:
--   1. no current, runtime-eligible qd-company record says the founder approves refunds or takes the final call, names a
--      Customer Success Director or ten departments, holds paid inference, or has the CFO act;
--   2. governance says the CEO seat has full authority (1696), the refund ladder says the CEO decides, the organization
--      record says there are no departments and names every active seat of org_role;
--   3. no department record (qd-company:org-*) is current;
--   4. the standing decisions say paid inference is on (1175) and every applies_to names a seat;
--   5. the public refund FAQ (167, 616) names no Customer Success Director.
do $probe$
declare fails text := ''; r record; n int; v_stale text :=
  'Customer Success Director|founder''s (final call|approval)|founder is notified|final call \+ approval = the founder|ONLY approver of refunds'
  || '|founder-approved|ten (autonomous )?(AI )?departments|\m10 departments|THE TEN DEPARTMENTS|Paid inference \(OpenRouter\) is HELD'
  || '|nothing needs the founder''s approval except|the CFO opens|AI departments|money above AED 10,000';
begin
  if not exists (select 1 from public.pricing_config) or not exists (select 1 from public.org_role) then
    raise exception 'CHK<<PROBE FAILED: seed pricing_config, company_goals and org_role from production first (no secret rows)>>';
  end if;
  perform public.fn_company_self_knowledge_sync();

  for r in select record_id, content from public.ops_knowledge
            where record_id like 'qd-company:%' and supersession_state = 'current' and runtime_eligible
              and split_part(content, E'\n\nYou can answer questions about:', 1) ~* v_stale loop
    fails := fails || ' 1:' || r.record_id || '=' || coalesce(substring(r.content from '(?i)(' || v_stale || ')'), '?');
  end loop;

  if not exists (select 1 from public.ops_knowledge where record_id = 'qd-company:governance' and content like '%CEO seat has full authority%' and content like '%1696%') then fails := fails || ' 2:governance'; end if;
  if not exists (select 1 from public.ops_knowledge where record_id = 'qd-company:refunds' and content like '%the CEO seat decides%' and content like '%the CEO approves the refund%') then fails := fails || ' 2:refunds'; end if;
  if not exists (select 1 from public.ops_knowledge where record_id = 'qd-company:commercials' and content like '%the CEO seat decides%') then fails := fails || ' 2:commercials'; end if;
  if not exists (select 1 from public.ops_knowledge where record_id = 'qd-company:organization' and content like '%THERE ARE NO DEPARTMENTS%') then fails := fails || ' 2:organization'; end if;
  select count(*) into n from public.org_role o where o.status = 'active'
     and not exists (select 1 from public.ops_knowledge k where k.record_id = 'qd-company:organization' and k.content like '%  - ' || o.role_id || ' (%');
  if n > 0 then fails := fails || ' 2:seats_missing=' || n; end if;

  if exists (select 1 from public.ops_knowledge where record_id like 'qd-company:org-%' and supersession_state = 'current') then fails := fails || ' 3:department_rows'; end if;

  if exists (select 1 from public.company_policy_decision where decision_key = 'openrouter_credit')
     and not exists (select 1 from public.ops_knowledge where record_id = 'qd-company:decisions' and content like '%ruling 1175%') then fails := fails || ' 4:openrouter'; end if;
  select count(*) into n from public.company_policy_decision d, unnest(d.applies_to) a
   where a not in ('ceo','sales_engineer','customer_support','accountant','it_engineer','marketing','*','every_employee');
  if n > 0 then fails := fails || ' 4:applies_to_not_a_seat=' || n; end if;

  if exists (select 1 from public.company_faq where id in (167, 616) and answer ~ 'Customer Success Director|مدير نجاح العملاء|decided by a person here') then fails := fails || ' 5:faq'; end if;

  if coalesce(fails, 'a check wrote null') <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: the regenerated company knowledge says the CEO decides refunds and approvals, names the six seats and no departments, says paid inference is on; no department record is current; every applies_to is a seat; the public refund FAQ names no Customer Success Director>>';
end $probe$;
