-- THE `knowledge_fill_gap` ACTION CLASS IS A COVERAGE DETERMINATION OVER TABLES, NOT A GENERATION (MASTER_PLAN §5.3, 5 Sep 2026).
--
-- MEASURED before this file: 2 workflow steps carry action_class 'knowledge_fill_gap' -
-- knowledge_lifecycle #6 "Decay confidence past the review date" and #8 "Category module coverage:
-- is a module missing, stale, or failing its coverage check?" - both routed to the edge executor
-- kb_fill_gap, which asks ai_gateway to WRITE trade knowledge for the thinnest category. Neither
-- step asks for writing: #6 is a date comparison over ops_knowledge.review_after and #8 is counting
-- kb_chunks per active category_agents row against dates. With the model held, 5 such steps closed
-- advisory on 4-5 Sep unworked, and 3 knowledge_lifecycle runs failed at step 6.
--
-- WHAT IT DOES (an expert acts, it does not only observe):
--   #6 decay  -> ops_knowledge rows whose review_after has passed and are not yet marked are set
--               source_freshness = 'review_required' (the value 1,103 rows already carry for the same
--               meaning; reversible by setting it back). The count written is stated. 0 today: the
--               earliest review_after on the estate is 2027-01-31, and that is the honest output.
--   #8 coverage -> every active category is classified from its chunk count and dates:
--               missing (0 chunks), thin (below the roster's 25th percentile), stale (newest
--               effective_date older than 365 days, or every chunk undated), ok. The gaps are the
--               recommendation, each with its numbers. When the run context names a category, the
--               determination is scoped to it.
--
-- CONTRACT with fn_action_invoke_rpc: zero required arguments; self-locates its queued
-- action_execution row as fn_recommend_deterministic does.
--
-- RETURN SHAPES: 'decayed' (rows_written may be 0, stated), 'coverage_gaps' (gaps non-empty),
-- 'coverage_ok' (gaps empty, counts stated), 'no_scope' (a named category the roster does not hold).
-- Generation of missing knowledge remains the edge executor's job by hand; org_action_executor.params
-- records kb_fill_gap as model_escalation_target for the day the roster has a category with 0 chunks.

create or replace function public.fn_knowledge_gap_deterministic(p_step_run_id bigint default null)
returns table(
  determination text, employee text, department text, workflow_key text, step_no integer, step text,
  outcome text, deliverable text, inputs jsonb, gaps jsonb, rows_written integer, used_llm boolean)
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_sid bigint := p_step_run_id; v_located text := 'p_step_run_id';
  v_actor text; v_employee text; v_dept text; v_wf text; v_wfname text; v_step_no int; v_step text; v_run uuid; v_ctx jsonb := '{}'::jsonb;
  v_cat text; v_mode text;
  v_past int := 0; v_marked int := 0; v_total int := 0; v_no_date int := 0; v_next date; v_by_dept jsonb;
  v_p25 numeric; v_roster int := 0; v_gaps jsonb; v_ngaps int := 0; v_missing int := 0; v_thin int := 0; v_stale int := 0; v_ok int := 0;
  v_text text;
begin
  used_llm := false; rows_written := 0;
  if v_sid is null then
    select x.workflow_step_run_id, x.request->>'actor' into v_sid, v_actor
      from public.action_execution x
      join public.org_action_executor e on e.action_class = x.action_class and e.kind = 'rpc'
     where x.action_class = 'knowledge_fill_gap' and x.status = 'queued'
     order by x.created_at limit 1;
    v_located := case when v_sid is not null then 'action_execution.workflow_step_run_id'
                      when v_actor is not null then 'action_execution.request.actor' else 'nothing queued' end;
  end if;
  if v_sid is not null then
    select s.actor, s.step_no, s.input->>'step', s.workflow_run_id, r.workflow_key, coalesce(r.context,'{}'::jsonb), w.name
      into v_actor, v_step_no, v_step, v_run, v_wf, v_ctx, v_wfname
      from public.workflow_step_run s join public.workflow_run r on r.id = s.workflow_run_id
      left join public.workflow w on w.workflow_key = r.workflow_key
     where s.id = v_sid;
    v_employee := public.fn_workflow_actor_resolve(v_run, v_actor);
  elsif v_actor is not null then
    v_employee := public.fn_org_agent_resolve(v_actor);
  end if;
  select o.department into v_dept from public.org_agents o where o.agent_key = v_employee and o.active;
  employee := v_employee; department := v_dept; workflow_key := v_wf; step_no := v_step_no; step := v_step;
  v_cat := nullif(btrim(coalesce(v_ctx->>'category', v_ctx->>'category_slug', v_ctx->>'slug', '')), '');
  v_mode := case when v_step ilike '%decay%' or v_step ilike '%review date%' then 'decay' else 'coverage' end;

  if v_mode = 'decay' then
    select count(*), count(*) filter (where review_after < current_date),
           count(*) filter (where review_after < current_date and coalesce(source_freshness,'') <> 'review_required'),
           count(*) filter (where review_after is null), min(review_after) filter (where review_after >= current_date)
      into v_total, v_past, v_marked, v_no_date, v_next
      from public.ops_knowledge
     where v_cat is null or category_key = v_cat or scope_key = v_cat;
    select coalesce(jsonb_agg(jsonb_build_object('dept', dept_key, 'past_review', n) order by n desc), '[]'::jsonb)
      into v_by_dept
      from (select coalesce(dept_key, '(company)') dept_key, count(*) n from public.ops_knowledge
             where review_after < current_date and (v_cat is null or category_key = v_cat or scope_key = v_cat) group by 1) q;
    update public.ops_knowledge
       set source_freshness = 'review_required'
     where review_after < current_date and coalesce(source_freshness,'') <> 'review_required'
       and (v_cat is null or category_key = v_cat or scope_key = v_cat);
    get diagnostics rows_written = row_count;
    determination := 'decayed';
    inputs := jsonb_build_object('located_by', v_located, 'step_run_id', v_sid, 'employee', v_employee, 'department', v_dept, 'mode', v_mode,
                'category', v_cat, 'ops_knowledge_rows', v_total, 'past_review_after', v_past, 'newly_marked', v_marked, 'no_review_date', v_no_date,
                'next_review_after', v_next, 'past_review_by_dept', v_by_dept, 'measured_at', now());
    gaps := v_by_dept;
    outcome := format('decayed %s of %s ops_knowledge row(s) past their review date (%s already marked, %s without a review date, next review falls due %s)%s',
                      rows_written, v_past, v_past - v_marked, v_no_date, coalesce(v_next::text, 'never'), coalesce(' for category ' || v_cat, ''));
    deliverable := format(E'CONFIDENCE DECAY PAST REVIEW DATE\nWorkflow %s step %s (%s), worked by %s for %s%s.\n%s.\nBy department: %s.\nAction taken: source_freshness set to review_required on %s row(s); reversible. Basis: ops_knowledge.review_after against current_date %s. No model call.',
                          coalesce(v_wfname, v_wf), v_step_no, v_step, v_employee, v_dept, coalesce(' scoped to ' || v_cat, ' (company-wide)'), outcome,
                          coalesce((select string_agg(format('%s %s', x->>'dept', x->>'past_review'), ', ') from jsonb_array_elements(v_by_dept) x), 'none past review'),
                          rows_written, current_date);
    return next; return;
  end if;

  -- coverage
  if v_cat is not null and not exists (select 1 from public.category_agents c where c.active and c.slug = v_cat) then
    determination := 'no_scope';
    outcome := format('category %s is not an active category_agents row; nothing to measure', v_cat);
    deliverable := outcome;
    inputs := jsonb_build_object('located_by', v_located, 'step_run_id', v_sid, 'employee', v_employee, 'department', v_dept, 'mode', v_mode, 'category', v_cat);
    gaps := null; return next; return;
  end if;
  -- One grouped pass over the roster's categories through kb_chunks_cat_id_idx; four correlated
  -- subqueries per category hit the statement timeout on the 2.68M-row table (measured 5 Sep 2026).
  with agg as (
    select k.category, count(*) n, max(k.effective_date) newest,
           count(*) filter (where k.effective_date is null) undated, max(k.created_at) last_added
      from public.kb_chunks k
     where k.category in (select c.slug from public.category_agents c where c.active and (v_cat is null or c.slug = v_cat))
     group by k.category
  ), per as (
    select c.slug, c.name, c.requires_regulation, coalesce(a.n, 0) n, a.newest, coalesce(a.undated, 0) undated, a.last_added
      from public.category_agents c left join agg a on a.category = c.slug
     where c.active and (v_cat is null or c.slug = v_cat)
  ), stats as (
    select (percentile_cont(0.25) within group (order by n))::numeric p25, count(*) roster from per
  ), cls as (
    select per.*, s.p25, s.roster,
           case when n = 0 then 'missing'
                when n < s.p25 then 'thin'
                when newest is null or newest < current_date - 365 then 'stale'
                else 'ok' end state
      from per, stats s
  )
  select coalesce(jsonb_agg(jsonb_build_object('category', slug, 'name', name, 'state', state, 'chunks', n, 'roster_p25', round(p25, 1),
           'newest_effective_date', newest, 'undated_chunks', undated, 'last_added', last_added, 'requires_regulation', requires_regulation,
           'determination', case state
             when 'missing' then format('MISSING: %s has 0 kb_chunks; acquire from a cited source (knowledge_acquire) before it can serve a quote', name)
             when 'thin' then format('THIN: %s has %s chunks against a roster 25th percentile of %s; deepen it next', name, n, round(p25,1))
             when 'stale' then format('STALE: %s has %s chunks but the newest effective_date is %s (%s undated); re-validate against a current source', name, n, coalesce(newest::text, 'none'), undated)
             else format('OK: %s has %s chunks, newest effective_date %s', name, n, newest) end)
           order by case state when 'missing' then 0 when 'thin' then 1 when 'stale' then 2 else 3 end, n, slug) filter (where state <> 'ok' or v_cat is not null), '[]'::jsonb),
         count(*) filter (where state <> 'ok'), count(*) filter (where state = 'missing'), count(*) filter (where state = 'thin'),
         count(*) filter (where state = 'stale'), count(*) filter (where state = 'ok'), max(roster), max(p25)
    into v_gaps, v_ngaps, v_missing, v_thin, v_stale, v_ok, v_roster, v_p25
    from cls;
  inputs := jsonb_build_object('located_by', v_located, 'step_run_id', v_sid, 'employee', v_employee, 'department', v_dept, 'mode', v_mode,
              'category', v_cat, 'roster', v_roster, 'roster_p25_chunks', round(v_p25, 1), 'missing', v_missing, 'thin', v_thin, 'stale', v_stale, 'ok', v_ok,
              'measured_at', now());
  gaps := v_gaps;
  determination := case when v_ngaps > 0 then 'coverage_gaps' else 'coverage_ok' end;
  outcome := format('%s of %s active categor%s measured: %s missing, %s thin (below %s chunks), %s stale (newest effective_date older than 365 days or all undated), %s ok',
                    v_ngaps, v_roster, case when v_roster = 1 then 'y' else 'ies' end, v_missing, v_thin, round(v_p25, 1), v_stale, v_ok)
             || case when v_cat is not null then ' - scoped to ' || v_cat else '' end;
  deliverable := format(E'CATEGORY MODULE COVERAGE\nWorkflow %s step %s (%s), worked by %s for %s%s.\n%s.\n%s\nBasis: kb_chunks counted per active category_agents row, effective_date and created_at read as stored. No model call.',
                        coalesce(v_wfname, v_wf), v_step_no, v_step, v_employee, v_dept, coalesce(' scoped to ' || v_cat, ' (whole roster)'), outcome,
                        coalesce((select string_agg(t.x->>'determination', E'\n' order by t.o) from jsonb_array_elements(v_gaps) with ordinality as t(x, o) where t.o <= 12), 'No gap: every category is at or above the roster percentile with a dated chunk inside 365 days.'));
  return next;
end $$;

revoke execute on function public.fn_knowledge_gap_deterministic(bigint) from public;
revoke execute on function public.fn_knowledge_gap_deterministic(bigint) from anon;
grant execute on function public.fn_knowledge_gap_deterministic(bigint) to service_role;
