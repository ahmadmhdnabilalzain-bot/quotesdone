-- A REVIEW IS HELD RATHER THAN SKIPPED, AND ITS AUTHORS ARE THE ROWS IT JUDGES.
-- it_engineer. 23 September 2026. Follow-up to #880 (every_review_class_is_judged_by_another_family_than_its_author.sql,
-- applied at merge 91fd9f2), from the independent review of that PR. Founder instruction ~891: a review is never on its
-- author's family and never silently skipped.
--
-- WHAT THE REVIEW FOUND, AND WHAT THIS FILE CHANGES
--   1 HIGH  fn_it_review_independence_watch closed a hold on ANY later ai_cost_log row for the class and authors, and the
--           gateway's own refusal of the held call is such a row (model_used 'none', ok true). A hold closed itself the
--           moment it was written. -> Only a row that ran on a real model closes a hold.
--   3 MED   An unknown author (a model name not in model_registry, or 'unknown' where the author was not recorded) is a
--           DATA defect, not a missing reviewer. The router now says so (unknown_author true) and the gateway does not
--           record a review_hold for it; the watch reports it as its own it_engineer finding (review_author_unknown:*).
--   5 MED   fn_ceo_judgement_counterparts took every model any seat used in 7 days. It now takes the authors of the rows
--           the judgement input actually carries (fn_ceo_judgement_request): each OPEN ceo.directive reply is authored by
--           the models its seat called between the directive's creation and now, however old; the marketing report is
--           built by SQL (fn_marketing_report_*), so it has no model author. Signature: fn_ceo_judgement_counterparts(bigint).
--           qwen/qwen3.7-plus (active, measured, text only) is a fourth last-resort family after gemini and glm.
--   6 MED   A review whose chosen reviewer call fails, or whose whole ladder is open-circuit for a reason other than the
--           founder's hold, is recorded as a review_hold by the gateway (never an unrecorded skipped review).
--   7 LOW   Counterparts are normalised (trimmed, de-duplicated, sorted) in the router, the hold and the log tag, so one set
--           of authors is one hold. Vision/audio/tools reviews pass their capabilities: fn_ai_route_review_for(..., caps)
--           rejects a candidate without them (qwen3.7-plus has no vision). fn_ai_route_review keeps its signature and calls it.
--   (2 and 4 are edge-function changes: supplier_api reads the extraction record instead of trusting body.source, and a
--    confirm with no author names 'unknown', not 'deterministic'. quote_review_flow records its code reading.)
--
-- WHAT THIS FILE DOES NOT DO: lift the hold, call a model, or change which families are eligible on the normal path.
--
--   node scripts/apply_sql.mjs scripts/sql/a_review_is_held_rather_than_skipped_and_its_authors_are_the_rows_it_judges.sql --apply --ddl
-- Idempotent, no begin/commit: scripts/checks/no_review_class_can_route_to_its_authors_family.test.mjs replays it.

-- ── THE ROUTER, WITH CAPABILITIES AND A FOURTH LAST-RESORT FAMILY ───────────────────────────────
create or replace function public.fn_ai_route_review_for(p_task_class text, p_counterpart_model text,
  p_agent_key text default null, p_fn text default null, p_dept_key text default null, p_require_caps text[] default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_names text[]; v_fams text[] := '{}'; v_unknown text[] := '{}'; v_n text; v_f text; v_cp text;
  v_base jsonb; v_rej jsonb := '[]'::jsonb;
  v_pick text; v_pick_fam text; v_fb text; v_tier text;
  v_vis boolean := 'vision' = any (coalesce(p_require_caps, '{}'));
  v_aud boolean := 'audio'  = any (coalesce(p_require_caps, '{}'));
  v_tls boolean := 'tools'  = any (coalesce(p_require_caps, '{}'));
  c record;
begin
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter (where btrim(x) <> ''), '{}') into v_names
    from unnest(string_to_array(coalesce(p_counterpart_model, ''), ',')) x;
  v_cp := array_to_string(v_names, ',');
  foreach v_n in array v_names loop
    continue when v_n = 'deterministic';
    select lower(btrim(r.provider)) into v_f from public.model_registry r where r.model_id = v_n;
    if v_f is null then v_unknown := v_unknown || v_n; else v_fams := array(select distinct unnest(v_fams || v_f)); end if;
  end loop;

  if cardinality(v_names) = 0 or cardinality(v_unknown) > 0 then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true, 'unknown_author', true,
      'task_class', p_task_class, 'author_model', v_cp,
      'why', 'AUTHOR UNKNOWN: ' || coalesce(nullif(array_to_string(v_unknown, ', '), ''), '(none given)')
             || ' is not in model_registry, so its family is unknown and independence cannot be proved. A data defect in '
             || 'what the caller recorded about the author, not a missing reviewer.');
  end if;

  v_base := public.fn_ai_route(p_task_class, p_dept_key, null, p_fn, false, p_require_caps, p_agent_key);
  if not coalesce((v_base->>'use_llm')::boolean, false) then
    return v_base || jsonb_build_object('author_model', v_cp, 'author_family', to_jsonb(v_fams));
  end if;
  if cardinality(v_fams) = 0 then
    return v_base || jsonb_build_object('author_model', 'deterministic', 'author_family', '[]'::jsonb, 'independent', true,
      'reviewer_tier', 'standard', 'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: the author is deterministic code, not a model');
  end if;

  for c in
    with pol as (select model_primary, model_fallback from public.model_policy where task_class = v_base->>'task_class'),
    cand as (
      select pol.model_primary model_id, 0 ord from pol
      union all select p.model_id, p.rank from public.review_pool p where p.active
      union all select pol.model_fallback, 1000000 from pol
      union all select 'google/gemini-3.8-flash', 2000000
      union all select 'z-ai/glm-5.3-flash', 2000001
      union all select 'qwen/qwen3.7-plus', 2000002)
    select d.model_id, d.ord, lower(btrim(r.provider)) provider, coalesce(r.active and r.approved, false) reg_ok,
           (not v_vis or coalesce(r.supports_vision, false)) and (not v_aud or coalesce(r.supports_audio, false))
             and (not v_tls or coalesce(r.supports_tools, false)) caps_ok,
           h.model_id is not null measured,
           coalesce(h.open_until > now() and h.opened_class is not null, false) tripped
      from (select model_id, min(ord) ord from cand where model_id is not null and model_id <> 'none' group by model_id) d
      left join public.model_registry r on r.model_id = d.model_id
      left join public.llm_route_health h on h.model_id = d.model_id
     order by d.ord, d.model_id
  loop
    if c.provider is null then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'not in model_registry');
    elsif c.provider = any (v_fams) then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'same family as an author (' || c.provider || ')');
    elsif not c.reg_ok then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'inactive or unapproved in model_registry');
    elsif not c.caps_ok then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'lacks a required capability (' || array_to_string(p_require_caps, '+') || ')');
    elsif not c.measured then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'no llm_route_health row: unmeasured is not healthy');
    elsif c.tripped then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'breaker tripped by real failures');
    elsif v_pick is null then
      v_pick := c.model_id; v_pick_fam := c.provider;
      v_tier := case when c.ord >= 2000000 then 'third_family_fallback' else 'standard' end;
    elsif v_fb is null and (c.ord < 2000000 or v_tier = 'third_family_fallback') then
      v_fb := c.model_id;
    end if;
  end loop;

  if v_pick is null then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true,
      'task_class', v_base->>'task_class', 'author_model', v_cp, 'author_family', to_jsonb(v_fams), 'pool_rejected', v_rej,
      'why', 'NO INDEPENDENT REVIEWER: no active, healthy, capable candidate outside the ' || array_to_string(v_fams, '/')
             || ' families, not even a last-resort family. The review is HELD, never run on an author''s family.');
  end if;

  return v_base || jsonb_build_object(
    'model', v_pick, 'fallback', v_fb,
    'in_per_mtok_usd', (select in_per_mtok_usd from public.model_registry where model_id = v_pick),
    'out_per_mtok_usd', (select out_per_mtok_usd from public.model_registry where model_id = v_pick),
    'reviewer_family', v_pick_fam, 'reviewer_tier', v_tier, 'author_model', v_cp, 'author_family', to_jsonb(v_fams),
    'independent', true, 'pool_rejected', v_rej,
    'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: author wrote on ' || v_cp
           || ' (' || array_to_string(v_fams, '/') || '), reviewer routed to ' || v_pick || ' (' || v_pick_fam || ')'
           || coalesce(', fallback ' || v_fb, ', no fallback outside ' || array_to_string(v_fams, '/')));
end $fn$;
revoke execute on function public.fn_ai_route_review_for(text, text, text, text, text, text[]) from public, anon, authenticated;

-- The five-argument router of #877 / #880 keeps its signature (its callers and checks name it) and delegates.
create or replace function public.fn_ai_route_review(p_task_class text, p_counterpart_model text,
  p_agent_key text default null, p_fn text default null, p_dept_key text default null)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select public.fn_ai_route_review_for(p_task_class, p_counterpart_model, p_agent_key, p_fn, p_dept_key, null);
$fn$;
revoke execute on function public.fn_ai_route_review(text, text, text, text, text) from public, anon, authenticated;

-- ── ONE SET OF AUTHORS IS ONE HOLD ──────────────────────────────────────────────────────────────
create or replace function public.fn_review_hold_record(p_task_class text, p_fn text, p_agent_key text,
  p_counterpart_model text, p_why text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_cp text;
begin
  select coalesce(nullif(string_agg(distinct btrim(x), ',' order by btrim(x)), ''), '(none)') into v_cp
    from unnest(string_to_array(coalesce(p_counterpart_model, ''), ',')) x where btrim(x) <> '';
  insert into public.review_hold (task_class, fn, agent_key, counterpart_model, why)
  values (coalesce(p_task_class, '(unresolved)'), p_fn, p_agent_key, v_cp, left(coalesce(p_why, 'no independent reviewer'), 2000))
  on conflict (task_class, coalesce(fn, ''), counterpart_model) where closed_at is null
  do update set last_held_at = now(), times_held = review_hold.times_held + 1, why = excluded.why
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_review_hold_record(text, text, text, text, text) from public, anon, authenticated;

-- ── THE WATCH: ONLY A REAL REVIEW CLOSES A HOLD; AN UNKNOWN AUTHOR IS ITS OWN FINDING ───────────
create or replace function public.fn_it_review_independence_items()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with held as (
    select jsonb_build_object(
             'item', 'review_held:' || task_class, 'owner_seat', 'ceo', 'subject', 'review_independence',
             'title', count(*) || ' ' || task_class || ' review(s) HELD: no healthy reviewer outside the authors'' families (not even a '
                      || 'last-resort family), or the chosen reviewer failed. Nothing ran unreviewed or same-family; restore a reviewer or decide the held work.',
             'blast', 'agent_facing', 'affected', sum(times_held),
             'evidence', jsonb_build_object('review_hold_ids', jsonb_agg(id order by id), 'authors', jsonb_agg(distinct counterpart_model))) x
      from public.review_hold where closed_at is null group by task_class
  ), third as (
    select jsonb_build_object(
             'item', 'third_family_review:' || task_class, 'owner_seat', 'ceo', 'subject', 'review_independence',
             'title', count(*) || ' ' || task_class || ' review(s) in 7 days ran on a LAST-RESORT family ('
                      || string_agg(distinct model_used, ', ') || ') because the authors spanned both judgement families.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('ai_cost_log_ids', jsonb_agg(id order by id))) x
      from public.ai_cost_log
     where reviewer_tier = 'third_family_fallback' and occurred_at > now() - interval '7 days'
     group by task_class
  ), unknown_author as (
    select jsonb_build_object(
             'item', 'review_author_unknown:' || coalesce(fn, task_class), 'owner_seat', 'it_engineer', 'subject', 'review_independence',
             'title', count(*) || ' ' || coalesce(task_class, '?') || ' review(s) from ' || coalesce(fn, '?') || ' in 7 days named an author '
                      || 'model that is not in model_registry (or ''unknown''), so they could not be routed. Fix what the caller records '
                      || 'about the author; the model comparison was withheld, not skipped silently.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('ai_cost_log_ids', jsonb_agg(id order by id), 'authors', jsonb_agg(distinct counterpart_model))) x
      from public.ai_cost_log
     where coalesce(model_used, 'none') = 'none' and model_selected_because like 'AUTHOR UNKNOWN:%'
       and occurred_at > now() - interval '7 days'
     group by coalesce(fn, task_class), task_class, fn
  )
  select coalesce((select jsonb_agg(x) from held), '[]'::jsonb) || coalesce((select jsonb_agg(x) from third), '[]'::jsonb)
         || coalesce((select jsonb_agg(x) from unknown_author), '[]'::jsonb);
$fn$;
revoke execute on function public.fn_it_review_independence_items() from public, anon, authenticated;

create or replace function public.fn_it_review_independence_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_closed int; v_items jsonb;
begin
  -- A hold closes only once the same class, over the same authors, RAN ON A MODEL independently after it. The gateway's
  -- own refusal row for the held call (model_used 'none', ok true) is not a review and must not close it.
  update public.review_hold h set closed_at = now(), close_note = 'reviewed independently after the hold: ai_cost_log '
         || (select min(l.id) from public.ai_cost_log l
              where l.task_class = h.task_class and l.counterpart_model = h.counterpart_model and l.ok
                and coalesce(l.model_used, 'none') <> 'none'
                and l.review_violation is null and l.occurred_at > h.last_held_at)
   where h.closed_at is null
     and exists (select 1 from public.ai_cost_log l
                  where l.task_class = h.task_class and l.counterpart_model = h.counterpart_model and l.ok
                    and coalesce(l.model_used, 'none') <> 'none'
                    and l.review_violation is null and l.occurred_at > h.last_held_at);
  get diagnostics v_closed = row_count;
  v_items := public.fn_it_review_independence_items();
  return jsonb_build_object('closed_holds', v_closed, 'items', jsonb_array_length(v_items),
                            'settle', public.fn_it_duty_settle('review_independence', v_items));
end $fn$;
revoke execute on function public.fn_it_review_independence_watch() from public, anon, authenticated;

-- ── THE CEO'S AUTHORS ARE THE ROWS IN ITS INPUT ─────────────────────────────────────────────────
-- fn_ceo_judgement_request puts two seat outputs in input: the open ceo.directive replies (agent_actions.evidence, any age)
-- and plan.funnel->'marketing_report' (fn_marketing_report builds it in SQL: no model author). A reply's authors are the
-- models its seat called between the directive's creation and now. No model row => 'deterministic'.
drop function if exists public.fn_ceo_judgement_counterparts();
create or replace function public.fn_ceo_judgement_counterparts(p_plan_id bigint)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(string_agg(distinct l.model_used, ',' order by l.model_used), 'deterministic')
    from public.agent_actions a
    join public.ai_cost_log l
      on l.seat = a.agent and l.ok and coalesce(l.model_used, 'none') not in ('none', '')
     and l.occurred_at >= a.created_at
   where a.kind = 'handoff' and a.detail->>'type' = 'ceo.directive' and a.status = 'pending'
     and exists (select 1 from public.ceo_plan p where p.id = p_plan_id);
$fn$;
revoke execute on function public.fn_ceo_judgement_counterparts(bigint) from public, anon, authenticated;

select case
  when public.fn_ai_route_review('quote_comparison', 'unknown')->>'unknown_author' is distinct from 'true'
    then 'PROBE FAILED: an unknown author is not reported as a data defect'
  when public.fn_ai_route_review_for('identity_redaction_verify', 'openai/gpt-5.6-sol,anthropic/claude-opus-5.5', null, null, null, array['vision'])->>'model' = 'qwen/qwen3.7-plus'
    then 'PROBE FAILED: a vision review routed to a text-only model'
  else 'PROBE OK' end as verdict;
