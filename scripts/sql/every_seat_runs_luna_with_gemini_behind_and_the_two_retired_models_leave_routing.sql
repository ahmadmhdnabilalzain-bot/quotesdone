-- EVERY SEAT RUNS LUNA WITH GEMINI BEHIND IT, AND THE TWO RETIRED MODELS LEAVE ROUTING (matrix v2).
-- Seat: it_engineer. 5 Oct 2026. The founder's ruling of 5 Oct 2026, amending founder_instruction 1056.
--
-- THE RULING
--   * Main model everywhere: openai/gpt-6-luna, google/gemini-3.8-flash behind it - every seat's routine work, the
--     CEO's easy work, the sales engineer (except the comparison report) and every other seat.
--   * Audio stays on Gemini with no backup: speech_transcription and marketing_watch (video+audio). gpt-6-luna takes
--     text, image and file input but no audio, and no other live model hears.
--   * The comparison report (quote_comparison) stays Opus with luna behind; the CEO's hard work stays Opus with luna.
--   * deepseek/deepseek-v4.1-flash and qwen/qwen3.7-plus leave routing: no policy, seat catch-all, review pool row or
--     last-resort family names either; both registry rows are switched off (active = false, approved = false) and
--     kept, with their rate and route-health rows, as history.
--   * Every review stays cross-family, recomputed for the new authors: an author on luna (OpenAI) is reviewed by Gemini
--     (Google) with Opus behind; an author on Opus by Gemini or luna; an author on Gemini by Opus or luna.
--   gpt-6-luna is priced at its standard list price, USD 0.10 in / 0.50 out per Mtok (registry already holds it).
--
-- CAPABILITIES (model_registry, read 5 Oct 2026): gpt-6-luna vision=true, tools=true, audio=false, context 1,050,000;
-- ai_gateway sends a file part down the vision path (caps 'vision'), which luna serves. So every class moves except the
-- two that hear. The file-reading classes that kept Gemini as primary because their old plan B could not read a file
-- (document_extraction, document_extraction_multimodal, ocr, vision, accountant_receipt_extraction) now run on luna
-- outright, and their backup Gemini reads files too: no route needs a file-capable exception any more.
-- max_tokens: unchanged. Every ceiling (32 .. 10000) is far inside luna's window, and luna is not a thinking model,
-- so a ceiling written for Gemini leaves luna the same headroom; every row with Opus in its pair keeps >= 4000.
--
-- Applied at merge only. No transaction lines: apply_sql.mjs runs the file as one transaction.
-- Proved by every_seat_runs_the_founders_model_matrix_probe.sql replayed after this file in one aborted transaction.

-- 1. Every class that ran Gemini (or DeepSeek) with any backup, and is not a review and does not hear: luna > Gemini.
update public.model_policy
   set model_primary = 'openai/gpt-6-luna', model_fallback = 'google/gemini-3.8-flash',
       rationale = '5 Oct 2026, matrix v2 (founder ruling amending 1056): openai/gpt-6-luna with google/gemini-3.8-flash behind it. Before: '
                   || model_primary || ' > ' || coalesce(model_fallback, 'none') || '.'
 where active
   and model_primary = 'google/gemini-3.8-flash'
   and model_fallback in ('deepseek/deepseek-v4.1-flash', 'openai/gpt-6-luna')
   and cardinality(coalesce(reviews_class, '{}')) = 0
   and task_class not in ('speech_transcription', 'marketing_watch');

-- 2. The review classes whose authors now write on luna: Gemini reviews, Opus behind it (Opus keeps 4000 tokens).
update public.model_policy
   set model_primary = 'google/gemini-3.8-flash', model_fallback = 'anthropic/claude-opus-5.5',
       max_tokens = greatest(coalesce(max_tokens, 0), 4000),
       rationale = '5 Oct 2026, matrix v2: its authors write on openai/gpt-6-luna (Gemini on their fallback), so the review '
                   || 'runs on google/gemini-3.8-flash with anthropic/claude-opus-5.5 behind it; over a Gemini author '
                   || 'fn_ai_route_review_for takes Opus, then luna. Before: '
                   || model_primary || ' > ' || coalesce(model_fallback, 'none') || '.'
 where active
   and task_class in ('knowledge_validation', 'ceo__knowledge_validation', 'sales_engineer__knowledge_validation',
                      'identity_redaction_verify', 'drawing_boq_confirm');

-- 3. The seat catch-alls (a call no class covers): luna > Gemini for every seat; the CEO and the sales engineer keep
--    Opus as their escalation.
update public.model_policy_by_identity
   set primary_model = 'openai/gpt-6-luna', fallback_model = 'google/gemini-3.8-flash',
       note = '5 Oct 2026, matrix v2 (founder ruling amending 1056): openai/gpt-6-luna > google/gemini-3.8-flash. Before: '
              || primary_model || ' > ' || coalesce(fallback_model, 'none') || '. Catch-all for a call from this seat that no '
              || 'model_policy class covers (fn_ai_route applies it only when v_generic).'
 where scope = 'current_agent'
   and identity_key in ('sales_engineer', 'ceo', 'customer_support', 'marketing', 'accountant', 'it_engineer');

-- 4. The review pool: Gemini is now the matrix's reviewer of every luna author, so it is in rotation, first; Opus, then
--    luna behind it. DeepSeek leaves (row kept, inactive).
--    (ranks are moved in an order that never puts two rows on one rank)
update public.review_pool set active = false, rank = 6,
       note = 'Retired from routing 5 Oct 2026 (founder ruling, matrix v2). Kept as history. Before: ' || note
 where model_id = 'deepseek/deepseek-v4.1-flash';
update public.review_pool set rank = 7 where model_id = 'google/gemini-3.8-flash';
update public.review_pool set rank = 3,
       note = '5 Oct 2026, matrix v2: the reviewer of every author on Gemini or Opus, after them in the pool. Before: ' || note
 where model_id = 'openai/gpt-6-luna';
update public.review_pool set rank = 2 where model_id = 'anthropic/claude-opus-5.5';
update public.review_pool set active = true, rank = 1,
       note = '5 Oct 2026, matrix v2: the reviewer of every author on openai/gpt-6-luna. First in the pool. Before: ' || note
 where model_id = 'google/gemini-3.8-flash';

-- 5. The two retired models: switched off, never deleted (their rate and health rows price and explain old log lines).
update public.model_registry set active = false, approved = false, updated_at = now(),
       note = 'Retired from routing 5 Oct 2026 (founder ruling, matrix v2): openai/gpt-6-luna replaced it everywhere. Before: ' || coalesce(note, '')
 where model_id = 'deepseek/deepseek-v4.1-flash';
update public.model_registry set active = false, approved = false, updated_at = now(),
       note = 'Retired from routing 5 Oct 2026 (founder ruling, matrix v2): openai/gpt-6-luna replaced it everywhere. Before: ' || coalesce(note, '')
 where model_id = 'qwen/qwen3.7-plus';

-- 5b. The founder's one paid-route exception (drawing_boq_confirm, founder_instruction 216) names the model the confirm
--     runs on; the confirm now runs on Gemini, so the pin follows it. Its switch is not touched (still OFF).
update public.paid_route_exception
   set model_id = 'google/gemini-3.8-flash',
       note = coalesce(note, '') || ' | 5 Oct 2026 (matrix v2): model gpt-6-luna -> gemini-3.8-flash, the confirm''s new primary; '
              || 'the BoQ draft it confirms is read on luna, so the confirm must be another family. Still OFF.',
       updated_at = now()
 where route = 'drawing_boq_confirm' and model_id is distinct from 'google/gemini-3.8-flash';

-- 6. The review router's last-resort families: the two retired models leave the list (CREATE OR REPLACE keeps the ACL).
create or replace function public.fn_ai_route_review_for(p_task_class text, p_counterpart_model text, p_agent_key text DEFAULT NULL::text, p_fn text DEFAULT NULL::text, p_dept_key text DEFAULT NULL::text, p_require_caps text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    -- 1056: the pair of the seat's own row for this review class when the seat has one ('<seat>__<class>'),
    -- otherwise the class's own - never the general_drafting row a missing class falls back to
    with pol as (select model_primary, model_fallback from public.model_policy
                  where task_class = case when right(coalesce(v_base->>'policy_class', ''), length(v_base->>'task_class') + 2)
                                                = '__' || (v_base->>'task_class')
                                          then v_base->>'policy_class' else v_base->>'task_class' end),
    cand as (
      -- 1056: the class's own pair first (primary, then its named fallback), then the pool as depth
      select pol.model_primary model_id, 0 ord from pol
      union all select pol.model_fallback, 1 from pol
      union all select p.model_id, 10 + p.rank from public.review_pool p where p.active
      -- 1068 (30 Sep 2026): the last-resort families are the matrix's live ones. 5 Oct 2026 (matrix v2): the two retired
      -- models leave the list; Gemini first, then luna, Opus last.
      union all select 'google/gemini-3.8-flash', 2000000
      union all select 'openai/gpt-6-luna', 2000001
      union all select 'anthropic/claude-opus-5.5', 2000002)
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
end $function$
;

-- 7. fn_ai_route: a seat's plan B replaces a class's fallback only where the class runs on the seat's own primary, so
--    the CEO's Opus work keeps luna behind it while its catch-all falls back to Gemini (CREATE OR REPLACE keeps the ACL).
create or replace function public.fn_ai_route(p_task_class text DEFAULT NULL::text, p_dept_key text DEFAULT NULL::text, p_confidence numeric DEFAULT NULL::numeric, p_fn text DEFAULT NULL::text, p_escalate boolean DEFAULT false, p_require_caps text[] DEFAULT NULL::text[], p_agent_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_class   text;
  v_src     text;
  v_pol     model_policy%rowtype;
  v_reg     model_registry%rowtype;
  v_fb      model_registry%rowtype;
  v_bud     department_budget%rowtype;
  v_pct     numeric := 0;
  v_model   text;
  v_why     text;
  v_min     numeric;
  v_tier    text;
  v_vis     boolean := 'vision' = any(coalesce(p_require_caps, '{}'::text[]));
  v_aud     boolean := 'audio'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_tls     boolean := 'tools'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_sub     model_registry%rowtype;
  v_want    int;
  v_idp     model_policy_by_identity%rowtype;
  v_generic boolean := false;
  v_rt      jsonb;
  v_prior   jsonb;
  v_conf    numeric;
  v_rtier   text;
  v_canon   text;
  v_seat    text;
  v_split   text;
  v_route_base text;
  v_base_pol model_policy%rowtype;
  v_seat_fb text; v_seat_p text;
begin
  if p_task_class is not null and length(btrim(p_task_class)) > 0 then
    v_class := p_task_class; v_src := 'caller-supplied task_class';
  else
    select task_class into v_class from fn_task_class where fn = p_fn and active;
    if v_class is not null then
      v_src := 'classified from calling function "' || p_fn || '"';
    else
      v_class := 'general_drafting';
      v_generic := true;
      v_src := 'UNMAPPED function "' || coalesce(p_fn,'?') || '" - defaulted to general_drafting (medium). Add a fn_task_class row to route this properly.';
    end if;
  end if;

  -- THE PACK'S FOUR-ROLE TAXONOMY REACHES THE PATH IT WAS WRITTEN FOR (14 Aug 2026).
  --
  -- All 93 employees carry org_agents.routing_tier - director 36, operations_specialist 23,
  -- analyst_controller 21, reviewer_auditor 10 - and on the main employee path it was DEAD.
  -- fn_routing_tier_model below only fires when v_generic is true, i.e. when the calling function
  -- is unmapped; agent_brain IS mapped, to agent_reasoning, so every employee from a marketing
  -- copywriter to the CEO got the same blanket large tier.
  --
  -- Meanwhile model_policy carries routine_employee_reasoning at MEDIUM, and its own rationale
  -- says: "Pack: replaces the current blanket large-tier agent_reasoning. agent_reasoning is LIVE
  -- on anthropic/claude-sonnet-5 and agent_brain is ~93% of OpenRouter spend." It had ZERO callers.
  -- A policy written to replace something, that nothing points at, is a build order nobody wired.
  --
  -- This is a ROUTING decision taken from the role, not an override of task_class routing: the
  -- class is chosen by who is asking, then the policy for that class applies normally.
  --
  -- WHO STAYS ON LARGE, AND WHY. Only operations_specialist moves. reviewer_auditor stays large
  -- deliberately - all 24 Reviewer/Auditor rows in the pack name a large model, and a reviewer on
  -- the cheap model is a green check that means nothing. director and analyst_controller stay
  -- because their work is the consequential kind the large tier exists for.
  if v_class = 'agent_reasoning' and p_agent_key is not null then
    v_canon := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
    select a.routing_tier into v_rtier from org_agents a
     where a.agent_key = v_canon and a.active;
    if v_rtier = 'operations_specialist'
       and exists (select 1 from model_policy mp
                    where mp.task_class = 'routine_employee_reasoning' and mp.active) then
      v_class := 'routine_employee_reasoning';
      v_src := v_src || ' | routing_tier "operations_specialist" for "' || v_canon
                     || '" selected the routine employee class instead of the blanket large tier';
    end if;
  end if;

  -- THE SEAT'S OWN ROUTE (29 Sep 2026, sales_engineer; founder_instruction 1056).
  -- think() and every other shared engine bill a step to a class chosen by WHAT the step is
  -- (routine_employee_reasoning, customer_communication, ...). The founder's matrix routes by WHO asks. Matrix v2
  -- (5 Oct 2026): every seat runs openai/gpt-6-luna with google/gemini-3.8-flash as its plan B, and the CEO's
  -- hard work and the comparison report run on Opus with luna behind. The seat is the caller's agent,
  -- resolved as the agent_reasoning block above resolves it (an alias of a seat is that seat).
  --   1. A policy row named '<seat>__<class>' is that seat's own route for <class>: its MODELS are taken, while
  --      the CLASS stays <class> - ai_cost_log, the response cache, the confidence prior and every author proof
  --      key on it, and ai_cost_log.seat already says who asked. The row travels as policy_class, which
  --      fn_ai_route_review_for reads for a review's pair.
  --   2. Otherwise the seat's PLAN B is its own for every class it calls: the fallback of its catch-all row in
  --      model_policy_by_identity replaces the class's, unless the class has no fallback on purpose (only Gemini
  --      hears) or is a review (its pair is chosen against its author's family). Since matrix v2 only on a class
  --      that runs on the seat's own primary: an Opus class keeps luna behind it.
  -- A '<seat>__<class>' row - reached through the seat, or named by fn_task_class for the seat's own function -
  -- never allows fewer tokens than <class>. A seat's own row is never served from the semantic cache: that cache is keyed
  -- by class, not model, so a CEO judgement on Opus could otherwise be answered by another seat's Gemini answer.
  if p_agent_key is not null then
    v_seat := coalesce(v_canon, public.fn_org_agent_resolve(p_agent_key), p_agent_key);
    select mp.task_class into v_split from model_policy mp
     where mp.task_class = v_seat || '__' || v_class and mp.active;
    if v_split is not null then
      v_src := v_src || ' | seat "' || v_seat || '" routes "' || v_class || '" on its own policy row ' || v_split;
    end if;
  end if;

  select * into v_pol from model_policy where task_class = coalesce(v_split, v_class) and active;
  if not found then
    select * into v_pol from model_policy where task_class = 'general_drafting' and active;
    v_src := v_src || ' | no policy for "' || v_class || '", fell back to general_drafting';
    v_generic := true;
  end if;

  v_route_base := case when v_split is not null then v_class
                       when position('__' in v_pol.task_class) > 0 then split_part(v_pol.task_class, '__', 2) end;
  if v_route_base is not null then
    select * into v_base_pol from model_policy where task_class = v_route_base and active;
    if found then
      v_pol.max_tokens    := greatest(coalesce(v_pol.max_tokens, 0), coalesce(v_base_pol.max_tokens, 0));
      v_pol.cache_ttl_min := 0;
    end if;
  end if;

  if v_split is null and not v_generic and v_seat is not null and v_pol.model_fallback is not null
     and cardinality(coalesce(v_pol.reviews_class, '{}')) = 0 then
    select i.fallback_model, i.primary_model into v_seat_fb, v_seat_p from model_policy_by_identity i
     where i.scope = 'current_agent' and i.identity_key = v_seat
       and exists (select 1 from org_role o where o.role_id = v_seat and o.status = 'active');  -- a live seat's row only
    if v_seat_fb is not null and v_seat_fb not in (v_pol.model_primary, v_pol.model_fallback)
       and v_pol.model_primary is not distinct from v_seat_p then  -- matrix v2: only on the seat's own routine model
      v_src := v_src || ' | seat "' || v_seat || '" falls back to its own plan B ' || v_seat_fb
                     || ' instead of ' || v_pol.model_fallback;
      v_pol.model_fallback := v_seat_fb;
    end if;
  end if;

  -- THE ROLE DEFAULT. model_policy_by_identity carries 120 rows — 96 target employees and 24
  -- current production agents — and had NO reader in the database at all. The pack states its own
  -- precedence on every row: note = 'Role default only; task_class routing overrides it.' So it
  -- applies only where the caller would otherwise get the generic general_drafting fallback:
  -- either the named class has no policy, or the calling function is unmapped in fn_task_class.
  --
  -- v_generic exists because the first version of this branch was UNREACHABLE. It hung off
  -- `if not found` on the model_policy lookup, and an unmapped function has already had v_class
  -- rewritten to 'general_drafting' by then — which IS found. Measured: fn_ai_route(...,'ceo')
  -- returned identity_policy null. Same shape as the unreachable block in
  -- fn_kb_route_activation_blocked found earlier today: a branch guarded by a condition that
  -- cannot occur.
  --
  -- 23 of the 24 current_agent keys resolve to a real org_agents row; 'cat:*' covers the
  -- category desks.
  if v_generic and p_agent_key is not null then
    select * into v_idp from model_policy_by_identity
     where scope = 'current_agent'
       and (identity_key = p_agent_key
            or (identity_key = 'cat:*' and p_agent_key like 'cat:%'))
     order by (identity_key = p_agent_key) desc
     limit 1;
    if found and v_idp.primary_model is not null then
      v_pol.model_primary  := v_idp.primary_model;
      v_pol.model_fallback := coalesce(v_idp.fallback_model, v_pol.model_fallback);
      v_pol.max_tokens     := coalesce(v_idp.max_output_tokens, v_pol.max_tokens);
      v_src := v_src || ' | role default for "' || p_agent_key || '" applied from model_policy_by_identity';
    end if;
  end if;

  -- ---- ROUTING TIER, added 11 Aug 2026 ---------------------------------------------------------
  -- The pack's four-role taxonomy carried onto the 93 real employees as org_agents.routing_tier.
  -- Fires LAST and only if the pack had nothing to say about this specific agent, so an explicit
  -- current_agent row always wins. Resolves tier -> registry tier -> cheapest active approved model
  -- AT CALL TIME: no model id is stored anywhere, so this follows the fleet instead of going stale.
  -- Measured direction against the general_drafting default (haiku, 1.00 USD/Mtok in):
  -- operations_specialist 4x cheaper, analyst/director unchanged, reviewer_auditor 2x dearer and
  -- deliberately so - all 24 Reviewer/Auditor rows in the pack name sonnet-5, and a reviewer on the
  -- cheap model is a green check that means nothing.
  if v_generic and p_agent_key is not null and v_idp.identity_key is null then
    v_rt := public.fn_routing_tier_model(p_agent_key);
    if v_rt is not null and (v_rt->>'model') is not null then
      v_pol.model_primary := v_rt->>'model';
      v_pol.tier          := v_rt->>'registry_tier';
      v_src := v_src || ' | routing_tier "' || (v_rt->>'routing_tier') || '" for "' || p_agent_key
                     || '" resolved to ' || (v_rt->>'model') || ' (' || (v_rt->>'registry_tier') || ' tier)';
    end if;
  end if;
  -- ----------------------------------------------------------------------------------------------

  if v_pol.tier = 'none' then
    return jsonb_build_object(
      'use_llm', false, 'task_class', v_class, 'tier', 'none',
      'why', 'REFUSED. ' || coalesce(v_pol.deterministic_alternative, 'This is deterministic - use code.')
             || ' [' || v_src || ']',
      'deterministic_alternative', v_pol.deterministic_alternative);
  end if;

  v_tier  := v_pol.tier;
  v_model := v_pol.model_primary;
  v_why   := coalesce(v_pol.rationale, 'policy for ' || v_class) || ' [' || v_src || ']';

  if p_escalate then
    v_model := coalesce(v_pol.model_fallback, v_model);
    v_why   := v_why || ' | ESCALATED one tier after an unsatisfactory cheaper attempt';
  end if;

  select (value #>> '{}')::numeric into v_min from decision_policy where key = 'confidence_min';
  -- THE PRIOR, 11 Aug 2026. Both arms below are original and NEITHER HAS EVER FIRED, because
  -- p_confidence is the confidence of THIS call and no caller can know that before the call.
  -- Measured the day this was written: 7 of 1,746 model calls in seven days carried a confidence at
  -- all. The only confidence that CAN exist beforehand is the agent's own recent record on this
  -- task class, so that is what a caller supplying nothing now routes on.
  --
  -- fn_ai_confidence_prior returns null unless there are at least 5 observations AND they vary.
  -- The variance guard is the important half: the two callers that emitted a confidence before
  -- tonight always emitted exactly 1.0000, and a model reporting the same number every time would
  -- otherwise downgrade itself to a cheaper tier on the strength of its own unvarying optimism.
  v_conf := p_confidence;
  if v_conf is null and p_agent_key is not null then
    v_prior := public.fn_ai_confidence_prior(p_agent_key, v_class);
    if v_prior is not null then v_conf := (v_prior->>'prior')::numeric; end if;
  end if;

  if v_conf is not null then
    -- 1056: 'xlarge' is only the founder's named hard routes (the CEO's judgement, the comparison report, on
    -- Opus); a confidence prior never moves them. 'large' keeps the 11 Aug doctrine.
    if v_conf >= 0.95 and v_tier = 'large' then
      select model_id into v_model from model_registry
       where active and approved and tier = 'medium' order by in_per_mtok_usd, model_id limit 1;  -- model_id: 1056 tie-break
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n')
                            || ' calls on ' || v_class || ', spread ' || (v_prior->>'spread') || ')' end
               || ' >= 0.95, downgraded to medium - no second opinion needed';
    elsif v_min is not null and v_conf < v_min and v_tier = 'small' then
      v_model := coalesce(v_pol.model_fallback, v_model);
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n') || ' calls)' end
               || ' below floor ' || v_min || ', escalated a tier';
    end if;
  end if;

  -- (Historical, 13 Aug 2026: the halt that used to follow needed a department.) A CALL WITH NO DEPARTMENT: the lookup below needs a
  -- dept_key to find a budget, and 59 of this month's calls arrived without one - inquiry_intake,
  -- drawing_boq, doc_extract, license_extract, supplier_onboard and eleven more, i.e. the demand
  -- path. fn_task_class already maps fn -> task_class for this same function's model choice; it now
  -- carries the owning department too, so an un-attributed call is attributed by what it IS rather
  -- than left outside every ceiling. An explicit p_dept_key from the caller still wins.
  -- CANONICAL BEFORE THE CEILING (14 Aug 2026). department_budget holds the ten canonical rows;
  -- a caller passing a merged-away key ('procurement', 'marketing', 'sales' ...) found NO budget
  -- row and skipped the ceiling entirely. fn_dept_canonical resolves the key the caller used to
  -- the department that actually owns it.
  if public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active))) is not null then
    select * into v_bud from department_budget
     where dept_key = public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active)));
    if found and v_bud.monthly_aed > 0 then
      v_pct := round(100 * coalesce(
        (select sum(cost_aed) from ai_cost_log
          where dept_key = any(public.fn_dept_scope(v_bud.dept_key))
            and occurred_at >= date_trunc('month', now())), 0)
        / v_bud.monthly_aed, 2);
      -- NO HALT AND NO DEGRADE (24 Sep 2026, founder_instruction 987: no caps on LLM spend). v_pct is still
      -- reported as budget_pct so the books can see a department's spend; it no longer refuses or downgrades a call.
    end if;
  end if;

  select * into v_reg from model_registry where model_id = v_model and active;
  if not found then
    select * into v_reg from model_registry
     where active and approved and tier = (case v_tier when 'xlarge' then 'xlarge' else v_tier end)
     order by in_per_mtok_usd, model_id limit 1;  -- model_id: 1056 tie-break
    v_why := v_why || ' | WARNING: policy model "' || v_model || '" is not in model_registry; substituted ' || coalesce(v_reg.model_id,'(none)');
    v_model := v_reg.model_id;
  end if;

  -- CAPABILITY. Price and tier chose the model above; if it cannot see, hear or call tools the
  -- provider will simply reject the payload. Substitute the nearest capable model, preferring the
  -- intended tier, then the closest tier ABOVE it, and only then below - a capability substitution
  -- must never quietly become a quality downgrade.
  v_want := fn_ai_route_tier_rank(v_tier);
  if (v_vis or v_aud or v_tls)
     and not ( (not v_vis or coalesce(v_reg.supports_vision,false))
           and (not v_aud or coalesce(v_reg.supports_audio, false))
           and (not v_tls or coalesce(v_reg.supports_tools, false)) ) then

    select * into v_sub from model_registry
     where active and approved and model_id not like '%:online'      -- 1056: never a web-grounded variant
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by (fn_ai_route_tier_rank(tier) < v_want),                 -- at-or-above the tier first
              abs(fn_ai_route_tier_rank(tier) - v_want),              -- then closest to it
              in_per_mtok_usd, model_id                                -- then cheapest (model_id: 1056 tie-break)
     limit 1;

    if found then
      v_why := v_why || ' | CAPABILITY OVERRIDE: ' || v_model || ' cannot do ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+') || '); substituted ' || v_sub.model_id
               || ' (' || v_sub.tier || ' tier, intended ' || v_tier || ')';
      v_reg := v_sub; v_model := v_sub.model_id;
    else
      return jsonb_build_object(
        'use_llm', false, 'task_class', v_class, 'tier', v_tier, 'caps', to_jsonb(p_require_caps),
        'why', 'REFUSED. No active approved model in model_registry supports ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+')
               || '). Add one, or mark the capability on an existing model.');
    end if;
  end if;

  select * into v_fb from model_registry
   where model_id = v_pol.model_fallback and active
     and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools);
  if not found and (v_vis or v_aud or v_tls) then
    select * into v_fb from model_registry
     where active and approved and model_id <> v_model and model_id not like '%:online'   -- 1056
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by (fn_ai_route_tier_rank(tier) < v_want), abs(fn_ai_route_tier_rank(tier) - v_want), in_per_mtok_usd, model_id
     limit 1;
  end if;

  return jsonb_build_object(
    'use_llm', true,
    'task_class', v_class,
    'policy_class', v_pol.task_class,   -- 1056: the policy row the models came from (a seat's own, or the class's)
    'tier', v_tier,
    'model', v_model,
    'fallback', v_fb.model_id,
    'max_tokens', v_pol.max_tokens,
    'cache_ttl_min', coalesce(v_pol.cache_ttl_min, 0),
    'cache', coalesce(v_reg.supports_cache, false),
    'stream', coalesce(v_reg.supports_streaming, true),
    'caps', to_jsonb(coalesce(p_require_caps, '{}'::text[])),
    'in_per_mtok_usd', v_reg.in_per_mtok_usd,
    'out_per_mtok_usd', v_reg.out_per_mtok_usd,
    'cache_read_per_mtok_usd', v_reg.cache_read_per_mtok_usd,
    'budget_pct', v_pct,
    'identity_policy', case when v_idp.identity_key is null then null else jsonb_build_object(
        'identity_key', v_idp.identity_key, 'deterministic_first', v_idp.deterministic_first,
        'reasoning_effort', v_idp.reasoning_effort, 'authority_tier', v_idp.authority_tier) end,
    'routing_tier', v_rt,
    'confidence_prior', v_prior,
    'confidence_used', v_conf,
    'why', v_why);
end $function$

;
