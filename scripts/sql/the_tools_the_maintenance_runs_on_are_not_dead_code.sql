-- FOURTEEN OPERATOR TOOLS COME BACK — the sweep drew the line in the wrong place for them.
--
-- retire_the_routines_no_seat_can_reach.sql retired 149 routines outside a reachability closure whose
-- roots deliberately excluded scripts/. The reasoning was that a routine mentioned only by a check is
-- reachable by the machinery that MAINTAINS the company, not by the company itself, and so is not
-- kept alive by that mention.
--
-- That is right for a routine a check ASSERTS ABOUT and wrong for one a script CALLS in order to do
-- its job, and the difference is a call site, not a mention. Eleven of the 149 are the second kind, and
-- two more come with them because those eleven CALL them.
-- It announced itself on the very next command: regenerating the schema mirror runs
-- "select * from public.fn_schema_export()" and returned 42883, function does not exist.
--
--   fn_schema_export             the mirror generator itself, and schema_dump_not_replayable
--   fn_phase_b_effective_errata  scripts/phase_b/freeze.mjs, scripts/phase_c/final_measurements.mjs
--   fn_category_questions        scripts/kb/pack_scorecard.mjs, staging/verify_intake_routing.mjs
--   fn_kb_route_decide           staging/verify_intake_routing.mjs, staging/verify_taxonomy.mjs
--   fn_intake_slug_for_catalog   staging/verify_intake_routing.mjs
--   fn_kernel_all_boards         board discovery BY SIGNATURE — it has no textual caller by design,
--                                and the 3 Sep retirement kept this whole class for that reason
--   fn_board_review              scripts/sql/patch_fn_decide_board_review.mjs
--   fn_action_invoke_rpc         staging/rehearse_change_deployment_loop.mjs
--   fn_supplier_exception_open   staging/verify_exception_window.mjs
--   fn_write_decision_trace      scripts/checks/v3_remediation_regression.mjs
--   recompute_supplier_rating    scripts/rehearsal/hvac_dress_rehearsal.mjs
--
-- And two the apply guard refused to let me forget. It reads every callee a file names and refuses
-- the file if production lacks one, because plpgsql resolves a callee at RUN time: without that
-- guard this would have applied cleanly, matched every digest, and thrown the first time it ran.
--
--   fn_phase_b_gate_attachment   called by fn_phase_b_effective_errata
--   fn_kb_route                  called by fn_kb_route_decide
--
-- NOT restored, though scripts name them too: fn_category_checklist, fn_record_context_retrieval and
-- fn_phase_c_step_owner_valid. Every one of their callers is itself a .RETIRED.mjs file, so restoring
-- them would revive a routine whose only caller is already retired.
--
-- The bodies are the exact text from supabase/schema/full_schema.sql at the commit before the drops —
-- the mirror of production as it was — so nothing here is a re-derivation or a rewrite from memory.
--
-- GRANTS. A dropped-and-recreated SECURITY DEFINER function is granted EXECUTE to PUBLIC by
-- creation; CREATE OR REPLACE would have preserved the old ACL, but these were DROPPED, so there is
-- no ACL left to preserve. The mirror records definitions and not grants, so the estate's default is
-- reapplied explicitly: PUBLIC first (revoking anon alone is a silent no-op while the grant is held
-- through PUBLIC), then anon and authenticated. Nothing in the app or the edge functions calls any of
-- these — that is why they were in the unreachable set at all — and the scripts reach them over the
-- management API as postgres, which needs no grant.
--
--   node scripts/apply_sql.mjs scripts/sql/the_tools_the_maintenance_runs_on_are_not_dead_code.sql --apply --ddl

begin;

-- fn_phase_b_gate_attachment -- called by a script
CREATE OR REPLACE FUNCTION public.fn_phase_b_gate_attachment()
 RETURNS TABLE(gate_id text, workflow_id text, step_id text, attachment_basis text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with scoped as (
    -- expand workflow_scope; 'ALL' means every canonical workflow. Both ';' and '/' appear as
    -- separators across the package's registries, so both are split on.
    select g.gate_id, g.gate_name, g.gate_type, w.workflow_id
    from public.phase_b_gate g
    join public.phase_b_workflow w
      on g.workflow_scope = 'ALL'
      or w.workflow_id = any (string_to_array(replace(g.workflow_scope, '/', ';'), ';'))
  )
  -- gates that govern the phase rather than a step
  select s.gate_id, s.workflow_id, null::text, 'phase_level'
  from scoped s
  where s.gate_type = 'phase_boundary' or s.gate_id = 'GATE-001'

  union all
  -- GATE-008 closure completeness -> the workflow's closure step
  select s.gate_id, s.workflow_id, st.step_id, 'declared_step_property'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id and st.is_closure_step
  where s.gate_id = 'GATE-008'

  union all
  -- GATE-005 founder boundary -> steps that carry a founder gate
  select s.gate_id, s.workflow_id, st.step_id, 'declared_step_property'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id
   and st.founder_gate is not null and lower(st.founder_gate) <> 'none'
  where s.gate_id = 'GATE-005'

  union all
  -- GATE-004 creator/reviewer separation -> steps that carry an independent reviewer
  select s.gate_id, s.workflow_id, st.step_id, 'declared_step_property'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id
   and st.independent_reviewer_role_id is not null
  where s.gate_id = 'GATE-004'

  union all
  -- GATE-007 complete handoff -> steps that send one
  select distinct s.gate_id, s.workflow_id, h.from_step_id, 'declared_step_property'
  from scoped s
  join public.phase_b_handoff h on h.workflow_id = s.workflow_id
  where s.gate_id = 'GATE-007'

  union all
  -- gates that govern every step
  select s.gate_id, s.workflow_id, st.step_id, 'universal'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id
  where s.gate_id in ('GATE-002','GATE-003','GATE-006')

  union all
  -- workflow-scoped gates with no finer anchor declared in the package
  select s.gate_id, s.workflow_id, st.step_id, 'workflow_scope'
  from scoped s
  join public.phase_b_workflow_step st on st.workflow_id = s.workflow_id
  where s.gate_id not in ('GATE-001','GATE-002','GATE-003','GATE-004','GATE-005',
                          'GATE-006','GATE-007','GATE-008')
    and s.gate_type <> 'phase_boundary';
$function$;

-- kb_norm -- called by fn_kb_route
CREATE OR REPLACE FUNCTION public.kb_norm(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select nullif(
    btrim(regexp_replace(
      translate(
        regexp_replace(lower(normalize(coalesce(p,''), NFKC)), '[ً-ْٰـ]', '', 'g'),
        'أإآةىؤئ', 'اااهيوي'
      ),
      '[^[:alnum:]؀-ۿ]+', ' ', 'g')),
    '');
$function$;

-- fn_kb_route -- called by a script
CREATE OR REPLACE FUNCTION public.fn_kb_route(p_text text, p_limit integer DEFAULT 5)
 RETURNS TABLE(catalog_num integer, live_slug text, live_name text, score numeric, matched_aliases jsonb, languages text[])
 LANGUAGE sql
 STABLE
AS $function$
with q as (select ' ' || kb_norm(p_text) || ' ' as t),
hits as (
  select a.catalog_num, a.alias, a.language, a.weight, a.negative,
         array_length(string_to_array(a.alias_norm, ' '), 1) as words
  from public.kb_operational_alias a, q
  where length(a.alias_norm) >= 3
    and q.t like '%' || ' ' || a.alias_norm || ' ' || '%'
),
scored as (
  select h.catalog_num,
         sum(case when h.negative then -1 else 1 end * h.weight * h.words) as score,
         jsonb_agg(jsonb_build_object('alias', h.alias, 'lang', h.language,
                                      'w', h.weight, 'words', h.words, 'neg', h.negative)
                   order by h.weight * h.words desc) as matched,
         array_agg(distinct h.language) as langs
  from hits h group by h.catalog_num
)
select s.catalog_num, c.slug, c.name, s.score, s.matched, s.langs
from scored s join public.catalog_supplier_categories c on c.num = s.catalog_num
where s.score > 0
order by s.score desc, s.catalog_num
limit greatest(p_limit, 1);
$function$;

-- fn_schema_export -- called by a script
CREATE OR REPLACE FUNCTION public.fn_schema_export()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with t as (
  select c.relname as rel,
    'CREATE TABLE IF NOT EXISTS public.'||quote_ident(c.relname)||E' (\n'||
    string_agg('  '||quote_ident(a.attname)||' '||format_type(a.atttypid,a.atttypmod)||
      case a.attidentity when 'a' then ' GENERATED ALWAYS AS IDENTITY' when 'd' then ' GENERATED BY DEFAULT AS IDENTITY' else '' end||
      case when a.attgenerated='s' then ' GENERATED ALWAYS AS ('||pg_get_expr(ad.adbin,ad.adrelid)||') STORED'
           when ad.adbin is not null then ' DEFAULT '||pg_get_expr(ad.adbin,ad.adrelid) else '' end||
      case when a.attnotnull then ' NOT NULL' else '' end, E',\n' order by a.attnum)
    ||E'\n);' as tbl_ddl
  from pg_class c join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
  join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid=c.oid and ad.adnum=a.attnum
  where c.relkind='r' and not exists(select 1 from pg_depend d where d.objid=c.oid and d.deptype='e')
  group by c.relname
)
select
  '-- QuotesDone — FULL SCHEMA EXPORT (generated from the live database)'||E'\n'
  ||'-- Excludes: secret VALUES (key names listed below), and table ROW DATA (PII).'||E'\n'
  ||'-- Order is best-effort; this is a faithful reference mirror, not a guaranteed one-click restore.'||E'\n\n'
  ||'-- ===== EXTENSIONS =====' ||E'\n'|| coalesce((select string_agg('CREATE EXTENSION IF NOT EXISTS '||quote_ident(extname)||' WITH SCHEMA '||quote_ident(nx.nspname)||';', E'\n' order by extname) from pg_extension e join pg_namespace nx on nx.oid=e.extnamespace),'')
  ||E'\n\n-- ===== SEQUENCES =====\n'|| coalesce((select string_agg('CREATE SEQUENCE IF NOT EXISTS public.'||quote_ident(sequence_name)||';', E'\n' order by sequence_name) from information_schema.sequences where sequence_schema='public'),'')
  ||E'\n\n-- ===== TABLES ('||(select count(*) from t)||') =====\n'|| coalesce((select string_agg(tbl_ddl, E'\n\n' order by rel) from t),'')
  ||E'\n\n-- ===== CONSTRAINTS =====\n'|| coalesce((select string_agg('ALTER TABLE public.'||quote_ident(c.relname)||' ADD CONSTRAINT '||quote_ident(con.conname)||' '||pg_get_constraintdef(con.oid)||';', E'\n' order by case con.contype when 'p' then 1 when 'u' then 2 when 'c' then 3 else 9 end, c.relname, con.conname) from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where con.contype in ('p','u','c','f')),'')
  ||E'\n\n-- ===== INDEXES =====\n'|| coalesce((select string_agg(pg_get_indexdef(i.indexrelid)||';', E'\n' order by ic.relname) from pg_index i join pg_class ic on ic.oid=i.indexrelid join pg_namespace n on n.oid=ic.relnamespace and n.nspname='public' where not exists(select 1 from pg_constraint con where con.conindid=i.indexrelid) and not exists(select 1 from pg_depend d where d.objid=ic.oid and d.deptype='e')),'')
  ||E'\n\n-- ===== VIEWS =====\n'|| coalesce((select string_agg('CREATE OR REPLACE VIEW public.'||quote_ident(viewname)||' AS '||definition, E'\n\n' order by viewname) from pg_views where schemaname='public'),'')
  ||E'\n\n-- ===== FUNCTIONS =====\n'|| coalesce((select string_agg(pg_get_functiondef(p.oid), E'\n\n' order by p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.prokind in ('f','p') and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')),'')
  ||E'\n\n-- ===== TRIGGERS =====\n'|| coalesce((select string_agg(pg_get_triggerdef(tg.oid)||';', E'\n' order by c.relname) from pg_trigger tg join pg_class c on c.oid=tg.tgrelid join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where not tg.tgisinternal),'')
  ||E'\n\n-- ===== ROW LEVEL SECURITY (enable) =====\n'|| coalesce((select string_agg('ALTER TABLE public.'||quote_ident(relname)||' ENABLE ROW LEVEL SECURITY;', E'\n' order by relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where relkind='r' and relrowsecurity),'')
  ||E'\n\n-- ===== POLICIES =====\n'|| coalesce((select string_agg('CREATE POLICY '||quote_ident(policyname)||' ON public.'||quote_ident(tablename)||' AS '||permissive||' FOR '||cmd||' TO '||array_to_string(roles,', ')||coalesce(' USING ('||qual||')','')||coalesce(' WITH CHECK ('||with_check||')','')||';', E'\n' order by tablename,policyname) from pg_policies where schemaname='public'),'')
  ||E'\n\n-- ===== CRON JOBS =====\n'|| coalesce((select string_agg('select cron.schedule('||quote_literal(jobname)||','||quote_literal(schedule)||',$CRON$'||command||'$CRON$);', E'\n' order by jobid) from cron.job),'')
  ||E'\n\n-- ===== APP_SECRETS KEY NAMES (values intentionally excluded) =====\n'|| coalesce((select string_agg('--   '||key, E'\n' order by key) from public.app_secrets),'')
  ||E'\n'
$function$;

-- fn_phase_b_effective_errata -- called by a script
CREATE OR REPLACE FUNCTION public.fn_phase_b_effective_errata()
 RETURNS TABLE(erratum text, condition text, measured text, resolved boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select 'EX-006',
         'exception is complete: escalation owner, required response and closure condition present, and escalation is independent of detection',
         format('escalation=%s detection=%s response=%s closure=%s',
                e.escalation_owner_role_id, e.detection_owner_role_id,
                case when e.required_response <> '' then 'present' else 'MISSING' end,
                case when e.closure_condition <> '' then 'present' else 'MISSING' end),
         e.escalation_owner_role_id <> '' and e.required_response <> ''
           and e.closure_condition <> '' and e.escalation_owner_role_id <> e.detection_owner_role_id
  from public.phase_b_exception e where e.exception_id = 'EX-006'

  union all
  select 'W13',
         'primary business object references an existing canonical object',
         format('primary_object=%s exists=%s', w.primary_object, (o.object_id is not null)),
         o.object_id is not null
  from public.phase_b_workflow w
  left join public.phase_b_business_object o on o.object_id = w.primary_object
  where w.workflow_id = 'W13'

  union all
  select 'W22',
         'workflow has exactly one explicit closure step, it is the step reaching WORKFLOW_COMPLETE, and GATE-008 is attached to it',
         format('closure_steps=%s reaches_complete=%s gate_008_attached_to=%s',
                (select count(*) from public.phase_b_workflow_step where workflow_id='W22' and is_closure_step),
                (select bool_and(next_step_if_pass = 'WORKFLOW_COMPLETE')
                   from public.phase_b_workflow_step where workflow_id='W22' and is_closure_step),
                coalesce((select string_agg(a.step_id, ',') from public.fn_phase_b_gate_attachment() a
                           where a.gate_id='GATE-008' and a.workflow_id='W22'), 'NONE')),
         (select count(*) from public.phase_b_workflow_step where workflow_id='W22' and is_closure_step) = 1
         and (select bool_and(next_step_if_pass = 'WORKFLOW_COMPLETE')
                from public.phase_b_workflow_step where workflow_id='W22' and is_closure_step)
         and exists (select 1 from public.fn_phase_b_gate_attachment() a
                      where a.gate_id='GATE-008' and a.workflow_id='W22' and a.step_id is not null);
$function$;

-- fn_category_questions -- called by a script
CREATE OR REPLACE FUNCTION public.fn_category_questions(p_category text, p_lang text DEFAULT 'en'::text, p_limit integer DEFAULT 22)
 RETURNS TABLE(field_key text, question text, answer_type text, mandatory boolean, ask_order integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'kb_stage'
AS $function$
  -- THE SPEC'S "INQUIRY QUALIFICATION LOGIC", REACHABLE FOR THE FIRST TIME.
  -- 16,588 questions (4,117 distinct texts, 7,079 mandatory, 14,051 bilingual) live in kb_stage
  -- keyed by FAMILY slug. The intake speaks a legacy slug. The chain is
  --   intake slug -> lead_trade_map -> catalogue slug -> catalog_category_domain -> family
  -- and this walks all of it, accepting either vocabulary at the front.
  --
  -- field_key is NULL on every row; the real supplier-facing key and the ask-order live inside
  -- `activation`. Sorting by that order is the point - it is what makes this an ordered interview
  -- rather than the flat, unordered list category_specs.fields produces.
  --
  -- Deduplicated on question text: a family spans up to 465 subcategories which repeat the generic
  -- spine (emirate, exact need, scope, quantity, date), so without DISTINCT ON the first 20 rows
  -- would be the same question twenty times.
  with fam as (
    select d.domain_slug
      from public.catalog_category_domain d
     where d.catalog_slug = coalesce(
       (select c.slug from public.catalog_supplier_categories c where c.slug = p_category),
       (select m.catalog_slug from public.lead_trade_map m where m.trade_key = p_category))
  )
  select * from (
    select distinct on (q.question_en)
           coalesce(q.activation->>'supplier_facing_field', q.field_key) as field_key,
           case when p_lang = 'ar' and coalesce(q.question_ar,'') <> '' then q.question_ar else q.question_en end as question,
           q.answer_type,
           q.mandatory,
           coalesce((q.activation->>'order')::int, 999) as ask_order
      from kb_stage.questions q
      join fam on fam.domain_slug = q.category_slug
     where coalesce(q.question_en,'') <> ''
     order by q.question_en, q.mandatory desc
  ) x
  order by x.mandatory desc, x.ask_order, x.field_key
  limit greatest(p_limit, 1);
$function$;

-- fn_kb_route_decide -- called by a script
CREATE OR REPLACE FUNCTION public.fn_kb_route_decide(p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v jsonb; top numeric; second numeric; n int; v_action text; v_conf numeric; v_reason text;
  v_cat int; v_rules jsonb; v_dropped int := 0;
begin
  -- deactivated routes are removed BEFORE scoring, so a blocked route cannot win, tie, or make
  -- the decision look ambiguous
  select coalesce(jsonb_agg(to_jsonb(r) order by r.score desc), '[]'::jsonb) into v
  from (select * from public.fn_kb_route(p_text, 5)) r
  where not coalesce((public.fn_kb_route_activation_blocked(r.catalog_num)->>'blocked')::boolean, true);

  select count(*) into v_dropped
  from (select * from public.fn_kb_route(p_text, 5)) r
  where coalesce((public.fn_kb_route_activation_blocked(r.catalog_num)->>'blocked')::boolean, true);

  n := jsonb_array_length(v);
  if n = 0 then
    return jsonb_build_object(
      'action', 'ask_clarifying_question', 'confidence', 0, 'top_score', 0,
      'candidates', '[]'::jsonb, 'catalog_num', null, 'multi_category', false,
      'reason', case when v_dropped > 0
                     then format('%s matching route(s) are not activated for live use', v_dropped)
                     else 'no deterministic alias matched the customer wording' end,
      'clarification', 'Could you tell me in your own words what you need supplied or done? For example "waterproof a warehouse roof" or "supply 200 office chairs".',
      'rules', '[]'::jsonb, 'deactivated_candidates', v_dropped,
      'normalised', public.kb_norm(p_text));
  end if;

  top    := (v->0->>'score')::numeric;
  second := case when n > 1 then (v->1->>'score')::numeric else 0 end;
  v_conf := round(top / nullif(top + second, 0), 3);

  if top < 3 then
    v_action := 'ask_clarifying_question';
    v_reason := 'only a weak fragment matched; not enough to act on';
  elsif n = 1 or top >= second * 1.5 then
    v_action := 'route_or_ask_scope_details';
    v_reason := case when n = 1 then 'single deterministic alias match'
                     else 'leading route is decisively ahead of the runner-up' end;
  else
    v_action := 'ask_clarifying_question';
    v_reason := 'leading routes are too close to call';
  end if;

  v_cat := case when v_action = 'route_or_ask_scope_details' then (v->0->>'catalog_num')::int end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rule_id', d.rule_id, 'type', d.rule_type, 'priority', d.priority,
           'when', d.when_json, 'then', d.then_json,
           'requires_human_review', d.requires_human_review,
           'confidence', d.confidence) order by d.priority desc nulls last, d.rule_id), '[]'::jsonb)
    into v_rules
    from (select * from kb_stage.decision_rules dr
           where v_cat is not null
             and dr.category_slug in (select m.package_slug from public.kb_operational_route_map m
                                       where m.catalog_num = v_cat)
           order by dr.priority desc nulls last, dr.rule_id
           limit 5) d;

  return jsonb_build_object(
    'action', v_action,
    'confidence', v_conf,
    'top_score', top,
    'candidates', v,
    'catalog_num', v_cat,
    'multi_category', (n > 1 and second >= top * 0.75),
    'reason', v_reason,
    'clarification', case when v_action = 'ask_clarifying_question' then
        'Just so this reaches the right suppliers - is this closer to "' || (v->0->>'live_name') ||
        '" or "' || coalesce(v->1->>'live_name', 'something else') || '"?' end,
    'rules', coalesce(v_rules, '[]'::jsonb),
    'deactivated_candidates', v_dropped,
    'normalised', public.kb_norm(p_text));
end $function$;

-- fn_intake_slug_for_catalog -- called by a script
CREATE OR REPLACE FUNCTION public.fn_intake_slug_for_catalog(p_catalog_slug text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- The reverse of fn_category_knowledge: catalogue slug -> the legacy intake slug that owns the
  -- checklist. It is 1-to-many (flooring-suppliers is reached by carpets, epoxy-flooring, flooring,
  -- marble-granite and tiling), so the choice has to be deterministic or the same customer wording
  -- would land on a different checklist run to run.
  --
  -- Prefer a key the catalogue slug actually BEGINS with - 'flooring' for flooring-suppliers,
  -- 'aluminium' for aluminium-and-glass-suppliers, 'mep' for mep-suppliers-electromechanical.
  -- That picks the base trade over a facet of it. Where none prefixes, the shortest wins, which
  -- also prefers the base ('carpentry' over 'carpentry-joinery', 'fitout' over
  -- 'commercial-retail-fitout'). Only keys that exist in category_specs are eligible, because the
  -- answer has to be something the checklist lookup can actually use.
  select m.trade_key
    from public.lead_trade_map m
    join (select distinct category from public.category_specs) cs on cs.category = m.trade_key
   where m.catalog_slug = p_catalog_slug
   order by (p_catalog_slug like m.trade_key || '%') desc, length(m.trade_key) asc, m.trade_key asc
   limit 1;
$function$;

-- fn_kernel_all_boards -- called by a script
CREATE OR REPLACE FUNCTION public.fn_kernel_all_boards()
 RETURNS TABLE(board text, check_name text, expected text, actual text, ok boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  b record;
begin
  for b in
    select p.proname as fn
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.pronargs = 0
       and p.proargnames @> array['check_name','expected','actual','ok']
       -- IT DISCOVERED ITSELF. Written and applied without this line, and the first call recursed
       -- until the statement timeout killed it: this function returns exactly the shape it searches
       -- for, so it found itself, called itself, found itself again. Left as the reason the
       -- exclusion is by name rather than by a comment saying "don't add recursive boards".
       and p.proname <> 'fn_kernel_all_boards'
     order by p.proname
  loop
    board := b.fn;
    begin
      return query execute format(
        'select %L::text, x.check_name, x.expected, x.actual, x.ok from public.%I() x', b.fn, b.fn);
    exception when others then
      -- A BOARD THAT RAISES IS A FAILURE, NOT AN ABSENCE. fn_phase_c_invariants once raised 22007
      -- on every call after a column retype, which also took out fn_phase_c_baseline_drift. If that
      -- happens again it must read as red here rather than as a board that quietly returned nothing.
      check_name := 'BOARD_RAISED';
      expected   := 'the board returns rows';
      actual     := sqlstate || ' ' || sqlerrm;
      ok         := false;
      return next;
    end;
  end loop;
end
$function$;

-- fn_board_review -- called by a script
CREATE OR REPLACE FUNCTION public.fn_board_review(p_subject text, p_subject_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare adv record; ch jsonb; v_rec text; v_conf numeric; v_supply int; v_rev numeric;
  n_pro int:=0; n_cond int:=0; n_against int:=0; v_out jsonb := '[]'::jsonb;
begin
  ch := fn_challenge(p_subject,'board','board');
  select count(*) into v_supply from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at>now()-interval '30 days';

  for adv in select * from board_advisor where active order by advisor_key loop
    -- each advisor reasons through its own lens against the same facts
    if adv.advisor_key='risk' and (ch->>'stance')='recommend_against' then
      v_rec:='do_not_proceed'; v_conf:=0.85;
    elsif adv.advisor_key='economist' and v_rev=0 then
      v_rec:='proceed_with_conditions'; v_conf:=0.7;
    elsif adv.advisor_key in ('customer','supplier') and v_supply=0 then
      v_rec:='abstain'; v_conf:=0.5;
    elsif (ch->>'stance')='recommend_against' then
      v_rec:='do_not_proceed'; v_conf:=0.75;
    elsif (ch->>'stance')='concern' then
      v_rec:='proceed_with_conditions'; v_conf:=0.65;
    else
      v_rec:='proceed'; v_conf:=0.6;
    end if;

    insert into board_opinion (subject,subject_ref,advisor_key,recommendation,rationale,confidence)
    values (p_subject,p_subject_ref,adv.advisor_key,v_rec,
      adv.name||' ('||adv.lens||') asks: '||adv.asks||' — '||
      case v_rec
        when 'do_not_proceed' then 'On the evidence available this fails that test.'
        when 'proceed_with_conditions' then 'Proceed only with a named metric, a captured baseline and a reversal path.'
        when 'abstain' then 'There is no data on this side of the marketplace yet; an opinion would be invention.'
        else 'Nothing in this lens argues against it.' end, v_conf);

    if v_rec='proceed' then n_pro:=n_pro+1;
    elsif v_rec='proceed_with_conditions' then n_cond:=n_cond+1;
    elsif v_rec='do_not_proceed' then n_against:=n_against+1; end if;

    v_out := v_out || jsonb_build_array(jsonb_build_object('advisor',adv.name,'lens',adv.lens,'recommendation',v_rec,'confidence',v_conf));
  end loop;

  return jsonb_build_object('subject',p_subject,'proceed',n_pro,'with_conditions',n_cond,
    'against',n_against,'abstained',(select count(*) from board_advisor where active)-n_pro-n_cond-n_against,
    'board_verdict', case when n_against>0 then 'DO NOT PROCEED' when n_cond>0 then 'PROCEED WITH CONDITIONS' else 'PROCEED' end,
    'challenge_stance', ch->>'stance', 'opinions', v_out);
end $function$;

-- fn_action_invoke_rpc -- called by a script
CREATE OR REPLACE FUNCTION public.fn_action_invoke_rpc(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_ran int := 0; v_refused int := 0; v_skipped int := 0; v_failed int := 0; v_deferred int := 0;
        v_key text; v_res jsonb; v_missing boolean; v_required int; v_takes_jsonb boolean; v_arg jsonb;
begin
  for r in
    select a.id, a.action_class, a.request, a.idempotency_key, a.attempts,
           e.target, e.active, e.risk_tier, e.advisory_safe, e.reversible,
           e.required_authority, e.compensation_action_class, e.idempotency_strategy,
           e.notifies_human, e.unattended_ok, e.params
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
     where a.status = 'queued' and e.kind = 'rpc'
       -- a deferred execution is not due yet; see (2) in the header
       and coalesce(nullif(a.request->>'not_before','')::timestamptz, now()) <= now()
     order by a.created_at
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    -- THE SAME REFUSALS AS THE EDGE PATH, in the same order and for the same reasons. A SQL
    -- function is not safer than an HTTP call because it is closer to the data; if anything it is
    -- nearer the money. notifies_human is still checked before the risk tier: a message that
    -- should not have been sent cannot be un-sent by a low risk score.
    if not r.active
       or coalesce(r.required_authority,'') = 'founder'
       or (not r.reversible and r.compensation_action_class is null)
       or (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))
       or not (r.risk_tier = 'low' and r.advisory_safe and r.reversible) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','refused','at',now(),'kind','rpc',
               'reason', case
                 when not r.active then 'executor row is inactive'
                 when coalesce(r.required_authority,'') = 'founder' then 'reserved to the founder'
                 when (not r.reversible and r.compensation_action_class is null)
                   then 'not reversible and declares no compensation_action_class'
                 when (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))
                   then 'notifies_human is true and unattended_ok has not been set for this class'
                 else format('risk gate: tier=%s advisory_safe=%s reversible=%s - the invoker runs low/advisory_safe/reversible only',
                             r.risk_tier, r.advisory_safe, r.reversible) end)
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- CAN THIS TARGET ACTUALLY BE CALLED? Asked of pg_proc, not assumed from the table. A missing
    -- function, a function that takes the request as one jsonb, and a function needing arguments we
    -- do not have are three different cases and are reported as three different things.
    select (p.oid is null),
           coalesce(p.pronargs - p.pronargdefaults, -1),
           coalesce(p.pronargs = 1 and p.proargtypes[0] = 'jsonb'::regtype::oid, false)
      into v_missing, v_required, v_takes_jsonb
      from (select 1) _
      left join pg_proc p on p.proname = r.target and p.pronamespace = 'public'::regnamespace;

    if v_missing then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', format('executor target public.%s() does not exist', r.target))
       where id = r.id;
      v_failed := v_failed + 1;
      continue;
    end if;

    if v_required > 0 and not v_takes_jsonb then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', format('public.%s() requires %s argument(s) with no default, and a workflow step carries none to give it. Take the request as ONE jsonb parameter (the invoker passes params || request || {action_execution_id}), or give the function defaults - do not let the invoker invent them.',
                               r.target, v_required))
       where id = r.id;
      v_failed := v_failed + 1;
      continue;
    end if;

    v_key := coalesce(nullif(btrim(r.idempotency_key),''),
                      r.action_class || ':' || md5(coalesce(r.request::text,'')));
    if r.idempotency_strategy is distinct from 'none_read_only'
       and exists (select 1 from public.action_execution x
                    where x.id <> r.id and x.status = 'succeeded'
                      and x.idempotency_key = v_key
                      and x.finished_at > now() - interval '24 hours') then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','deduplicated','at',now(),'kind','rpc','idempotency_key',v_key)
       where id = r.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    -- One form for every return shape. A set-returning function yields its rows; a scalar
    -- function in FROM yields exactly one. Wrapped per row so one failing target cannot roll back
    -- the others in this sweep. A jsonb-taking target gets the same body the edge invoker posts.
    begin
      if v_takes_jsonb then
        v_arg := coalesce(r.params, '{}'::jsonb) || coalesce(r.request, '{}'::jsonb)
                 || jsonb_build_object('action_execution_id', r.id);
        execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I($1) t', r.target)
          into v_res using v_arg;
      else
        execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I() t', r.target)
          into v_res;
      end if;

      -- (2) THE TARGET ASKED TO BE CALLED BACK LATER. Left queued and dated; not an attempt.
      if jsonb_typeof(v_res->0) = 'object' and (v_res->0) ? 'defer_until'
         and nullif(v_res->0->>'defer_until','') is not null then
        update public.action_execution
           set executor = r.target, idempotency_key = v_key,
               request = coalesce(request,'{}'::jsonb)
                         || jsonb_build_object('not_before', (v_res->0->>'defer_until')::timestamptz),
               response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','deferred','at',now(),'kind','rpc',
                 'not_before', (v_res->0->>'defer_until')::timestamptz,
                 'defer_reason', left(coalesce(v_res->0->>'reason',''), 500),
                 'deferrals', coalesce((response->>'deferrals')::int, 0) + 1)
         where id = r.id;
        v_deferred := v_deferred + 1;
        continue;
      end if;

      update public.action_execution
         set status = 'succeeded', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             executor = r.target, idempotency_key = v_key,
             started_at = coalesce(started_at, now()),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','succeeded','at',now(),'kind','rpc','result', v_res)
       where id = r.id;
      v_ran := v_ran + 1;
    exception when others then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             executor = r.target,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', replace(coalesce(sqlerrm,'unknown'), '''', ''))
       where id = r.id;
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object('ran', v_ran, 'refused', v_refused, 'deduplicated', v_skipped,
                            'failed', v_failed, 'deferred', v_deferred, 'ran_at', now());
end $function$;

-- fn_supplier_exception_open -- called by a script
CREATE OR REPLACE FUNCTION public.fn_supplier_exception_open(p_lead_id bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_days int := public.fn_supplier_exception_days(); r public.leads;
begin
  select * into r from public.leads where id = p_lead_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'lead_not_found'); end if;

  if r.exception_opened_at is not null and r.exception_closed_at is null then
    return jsonb_build_object('ok', true, 'reopened', false, 'due_at', r.exception_due_at,
                              'note', 'already open - the clock does not restart on a repeat failure');
  end if;

  update public.leads
     set exception_opened_at = now(),
         exception_due_at = now() + make_interval(days => v_days),
         exception_reminders = 0, exception_last_reminder_at = null,
         exception_closed_at = null, exception_outcome = null,
         licence_gate_reason = coalesce(p_reason, licence_gate_reason)
   where id = p_lead_id;

  return jsonb_build_object('ok', true, 'reopened', true,
                            'due_at', now() + make_interval(days => v_days), 'days', v_days);
end $function$;

-- fn_write_decision_trace -- called by a script
CREATE OR REPLACE FUNCTION public.fn_write_decision_trace(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id       uuid;
  v_agent    text := nullif(p->>'agent_key','');
  v_role     text;
  v_dept     text;
  v_mgr      text;
  v_dobj     text;
  v_corr     uuid := coalesce(nullif(p->>'correlation_id','')::uuid, gen_random_uuid());
begin
  if v_agent is null then
    raise exception 'fn_write_decision_trace: agent_key is required. A trace that cannot name who decided is not evidence.';
  end if;

  -- Identity is resolved SERVER-SIDE from the roster. A model cannot label its own trace with
  -- someone else's role, which is the whole point of separating role_id from agent_key.
  select a.department, a.manager_key, d.north_star
    into v_dept, v_mgr, v_dobj
    from org_agents a left join org_departments d on d.dept_key = a.department
   where a.agent_key = v_agent;

  v_role := coalesce(nullif(p->>'role_id',''),
                     (select i.packaged_role_id from org_role_identity i
                       where i.agent_key = v_agent order by i.packaged_role_id limit 1));

  insert into decision_trace (
    correlation_id, entity_type, entity_id, decision_type, proposed_by, decided_by,
    policy_keys, knowledge_refs, evidence_refs, alternatives, assumptions, risk,
    confidence, authority_result, decision, outcome_status,
    task_id, agent_key, role_id, department_id, manager_id, task_class,
    company_objective, department_objective, relevant_kpi,
    knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
    uncertainty, escalation_decision, proposed_action, expected_outcome, review_date,
    model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status
  ) values (
    v_corr,
    coalesce(nullif(p->>'entity_type',''),'agent_task'),
    nullif(p->>'entity_id',''),
    coalesce(nullif(p->>'decision_type',''),'agent_decision'),
    v_agent,
    coalesce(nullif(p->>'decided_by',''), v_agent),
    coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'policy_keys','[]'::jsonb)) x), '{}'),
    coalesce(p->'knowledge_refs','[]'::jsonb),
    coalesce(p->'evidence_refs','[]'::jsonb),
    coalesce(p->'alternatives','[]'::jsonb),
    coalesce(p->'assumptions','[]'::jsonb),
    coalesce(p->'risk','{}'::jsonb),
    nullif(p->>'confidence','')::numeric,
    coalesce(p->'authority_result','{}'::jsonb),
    coalesce(p->'decision','{}'::jsonb),
    coalesce(nullif(p->>'outcome_status',''),'pending'),
    nullif(p->>'task_id',''), v_agent, v_role, v_dept, v_mgr, nullif(p->>'task_class',''),
    -- The canonical company objective, read from the row that owns it rather than restated here:
    -- company_goals.revenue_annual = "Reach AED 1,000,000 annual revenue", target 1000000 AED.
    coalesce(nullif(p->>'company_objective',''),
             (select g.goal || ' (' || g.target_value::text || ' ' || coalesce(g.unit,'') || ')'
                from company_goals g where g.key = 'revenue_annual' and g.active limit 1)),
    coalesce(nullif(p->>'department_objective',''), v_dobj),
    nullif(p->>'relevant_kpi',''),
    coalesce(p->'knowledge_versions','{}'::jsonb),
    coalesce(p->'source_freshness','{}'::jsonb),
    coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'tools_requested','[]'::jsonb)) x), '{}'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'tools_executed','[]'::jsonb)) x), '{}'),
    coalesce(p->'tool_result_refs','[]'::jsonb),
    nullif(p->>'uncertainty',''), nullif(p->>'escalation_decision',''),
    nullif(p->>'proposed_action',''), nullif(p->>'expected_outcome',''),
    nullif(p->>'review_date','')::date,
    nullif(p->>'model',''), nullif(p->>'provider',''),
    nullif(p->>'input_tokens','')::integer, nullif(p->>'output_tokens','')::integer,
    nullif(p->>'estimated_cost_aed','')::numeric, nullif(p->>'final_status','')
  ) returning id into v_id;

  return v_id;
end $function$;

-- recompute_supplier_rating -- called by a script
CREATE OR REPLACE FUNCTION public.recompute_supplier_rating(p_supplier bigint)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  update public.leads l set
    app_rating  = (select round(avg(rating)::numeric, 2) from public.reviews r where r.supplier_id = p_supplier),
    app_reviews = (select count(*)::int from public.reviews r where r.supplier_id = p_supplier)
  where l.id = p_supplier;
$function$;

-- THE ACL THE DROP TOOK WITH IT
revoke all on function public.fn_phase_b_gate_attachment from public;
revoke all on function public.fn_phase_b_gate_attachment from anon;
revoke all on function public.fn_phase_b_gate_attachment from authenticated;
revoke all on function public.kb_norm from public;
revoke all on function public.kb_norm from anon;
revoke all on function public.kb_norm from authenticated;
revoke all on function public.fn_kb_route from public;
revoke all on function public.fn_kb_route from anon;
revoke all on function public.fn_kb_route from authenticated;
revoke all on function public.fn_schema_export from public;
revoke all on function public.fn_schema_export from anon;
revoke all on function public.fn_schema_export from authenticated;
revoke all on function public.fn_phase_b_effective_errata from public;
revoke all on function public.fn_phase_b_effective_errata from anon;
revoke all on function public.fn_phase_b_effective_errata from authenticated;
revoke all on function public.fn_category_questions from public;
revoke all on function public.fn_category_questions from anon;
revoke all on function public.fn_category_questions from authenticated;
revoke all on function public.fn_kb_route_decide from public;
revoke all on function public.fn_kb_route_decide from anon;
revoke all on function public.fn_kb_route_decide from authenticated;
revoke all on function public.fn_intake_slug_for_catalog from public;
revoke all on function public.fn_intake_slug_for_catalog from anon;
revoke all on function public.fn_intake_slug_for_catalog from authenticated;
revoke all on function public.fn_kernel_all_boards from public;
revoke all on function public.fn_kernel_all_boards from anon;
revoke all on function public.fn_kernel_all_boards from authenticated;
revoke all on function public.fn_board_review from public;
revoke all on function public.fn_board_review from anon;
revoke all on function public.fn_board_review from authenticated;
revoke all on function public.fn_action_invoke_rpc from public;
revoke all on function public.fn_action_invoke_rpc from anon;
revoke all on function public.fn_action_invoke_rpc from authenticated;
revoke all on function public.fn_supplier_exception_open from public;
revoke all on function public.fn_supplier_exception_open from anon;
revoke all on function public.fn_supplier_exception_open from authenticated;
revoke all on function public.fn_write_decision_trace from public;
revoke all on function public.fn_write_decision_trace from anon;
revoke all on function public.fn_write_decision_trace from authenticated;
revoke all on function public.recompute_supplier_rating from public;
revoke all on function public.recompute_supplier_rating from anon;
revoke all on function public.recompute_supplier_rating from authenticated;

commit;
