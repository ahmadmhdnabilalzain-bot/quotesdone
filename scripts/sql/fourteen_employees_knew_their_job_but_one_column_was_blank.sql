-- "14 EMPLOYEES WITH NO RESPONSIBILITIES - WRITE THEM OR REMOVE THEM."
--
-- Removing them would have been a serious mistake, and the measurement is why. The 14 are among the
-- most active employees in the company. Measured on production 2026-08-11 18:45 UTC:
--
--   onboarding          1,208 agent_runs · 7 KPIs · 8 tasks   (Supplier Success Manager)
--   security            1,178 agent_runs · 1 KPI  · 1 task    (Cybersecurity Manager)
--   docs                   68 agent_runs                      (Documentation Manager)
--   followup               55 agent_runs · 2 KPIs             (Customer Success Director)
--   collections            19 agent_runs · 2 KPIs             (Accounts Receivable Specialist)
--   procurement            15 agent_runs · 2 KPIs · 13 tasks  (Procurement Director)
--   cfo                     3 agent_runs · 2 KPIs · 11 tasks  (Finance Director)
--   ... and 7 more, every one with a role, a title, a seniority and a resolving manager_key.
--
-- All 14 have a populated `role` column, several of them detailed ("Head of Marketplace Operations
-- - intake->match->quote->reveal quality, SLAs, fairness, fraud doctrine"). What is blank is one
-- column: `responsibilities`. They were never employees who did not know what they were for.
--
-- So this writes the column, and writes it as a ROUTINE rather than 14 hand-typed strings, because
-- the same gap will otherwise reappear the moment the company hires. Composed only from facts the
-- company already holds - the employee's own role, title, seniority, its live KPIs and its
-- department's objectives - so nothing here is invented, and every clause is traceable to a row.
-- Idempotent: fills blanks only, never overwrites a responsibility somebody wrote deliberately.

create or replace function public.fn_employee_responsibilities_backfill()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_txt text; v_kpi text; v_obj text; v_n int := 0;
begin
  for r in select a.agent_key, a.role, a.title, a.seniority, a.department, a.manager_key
             from org_agents a
            where a.active and coalesce(btrim(a.responsibilities),'') = ''
  loop
    select string_agg('- '||k.kpi||' (target '||coalesce(k.target_value::text,'?')||' '
                      ||coalesce(k.unit,'')||', '||coalesce(k.cadence,'ongoing')||')', E'\n' order by k.kpi)
      into v_kpi from employee_kpi k where k.agent_key = r.agent_key and k.active;

    select string_agg('- '||d.objective, E'\n' order by d.sort, d.id)
      into v_obj from department_objective d where d.dept_key = r.department and d.active;

    v_txt := coalesce(r.role, r.title, r.agent_key)
      || case when r.seniority is not null then E'\n\nSeniority: '||r.seniority else '' end
      || case when r.manager_key is not null then '. Reports to: '||r.manager_key else '' end
      || case when v_kpi is not null then E'\n\nYou are measured on:\n'||v_kpi else '' end
      || case when v_obj is not null then E'\n\nYour department exists to:\n'||v_obj else '' end
      || E'\n\nYou own the operational decisions inside this scope. When the answer is not in your'
      || ' knowledge, retrieve it, consult the specialist who holds it, or raise a knowledge-gap'
      || ' task - never answer from a guess.';

    update org_agents set responsibilities = v_txt where agent_key = r.agent_key;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('written', v_n,
    'note', 'Composed from role, title, seniority, manager, live employee_kpi rows and the department''s objectives. Blanks only; never overwrites.');
end $function$;

revoke all on function public.fn_employee_responsibilities_backfill() from public;

select public.fn_employee_responsibilities_backfill();
