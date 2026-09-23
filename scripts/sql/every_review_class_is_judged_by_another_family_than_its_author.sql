-- EVERY REVIEW CLASS IS JUDGED BY ANOTHER FAMILY THAN ITS AUTHOR.
-- it_engineer. 23 September 2026. Founder instruction (ledger ~891), generalising 873:
--   whenever two agents debate, or one reviews / judges / verifies / approves another's output, they
--   must NEVER be on the same LLM family, so decisions are fair. It must hold 100%, universally.
--
-- MEASURED BEFORE THIS FILE (read-only, production htdblwldjkcgjvmqkbeh, 23 Sep 2026):
--   a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql (#877) enforces the rule for the two
--   seat_deliberation_* classes only. Every other review-shaped call carried no counterpart_model, so
--   fn_ai_route_review never ran for it:
--     ceo_judgement (ceo_agent)        Sol -> Opus   judges seat output written on Sol       SAME FAMILY
--     identity_redaction_verify        Sol -> Opus   verifies the drawing_redact find, which
--       (drawing_redact_verify)                      runs document_extraction Sol -> Opus    SAME FAMILY
--     quote_comparison (quote_compare) Sol -> Opus   over quotes read by quote_extract,
--                                                    document_extraction Sol -> Opus          SAME FAMILY
--     drawing_boq_confirm              GLM -> Gemini over the BoQ draft (Sol, or code)       different by config only
--     knowledge_validation             Sol -> Opus   over knowledge_ingestion GLM -> Gemini  different by config only; no caller yet
--     ceo_approval_decision            Sol -> Opus   over accountant / sales_engineer Sol    no caller yet
--   Nothing in the data said which class is a review, so nothing could enforce it.
--
-- WHAT THIS FILE CHANGES
--   1. model_policy.reviews_class text[]: the author task classes a review class judges. A class with a
--      non-empty reviews_class IS a review class. ai_gateway refuses (400 review_needs_counterpart) any
--      call of such a class that does not name counterpart_model, and routes every one that does through
--      fn_ai_route_review. The seat_deliberation_ prefix rule of #877 stays as well.
--   2. fn_ai_route_review, redefined (same signature, supersedes #877's body):
--      * counterpart_model may name SEVERAL models, comma-separated (a CEO judging the output of several
--        seats; a drawing page touched by a find and a retry). The reviewer avoids every one of their
--        families. Any name not in model_registry => no independent reviewer (fail closed).
--      * 'deterministic' names an author that is code, not a model (a BoQ counted from the drawing's
--        text, a quote read with no model). With no model author there is no family to avoid, so the
--        class routes normally; the route says so.
--      * candidates are: the class's own primary, then review_pool by rank, then the class's own
--        fallback. #877 read only review_pool, so a class's configured model (GLM for drawing_boq_confirm,
--        a third family for the redaction verify) could never be picked. For the two seat_deliberation
--        classes (Sol/Opus = the pool) the result is identical to #877's.
--   3. The DB backstop on ai_cost_log: trg_ai_cost_log_review_family reads the counterpart the gateway
--      writes into model_selected_because (" | counterpart_model=<list>") into the new counterpart_model
--      column, and writes review_violation on a review-class row whose model shares a family with a
--      counterpart (SAME_FAMILY_REVIEW) or that names no counterpart at all (REVIEW_WITHOUT_COUNTERPART).
--      It FLAGS, it does not refuse: refusing the insert would drop the spend record of a call already
--      paid for, which is worse than the violation. The refusal is upstream, in the gateway and in the
--      router; the flag is the proof that nothing got past them, and the check
--      scripts/checks/no_review_class_can_route_to_its_authors_family.test.mjs fails on any flagged row.
--   4. Rebalance: identity_redaction_verify's fallback moves from anthropic/claude-opus-5.5 to
--      google/gemini-3.8-flash, a THIRD family. The find runs on Sol or Opus; whichever it ran on, the
--      verify is routed to the other, with gemini behind it, so independence holds on the fallback too.
--      (Before: find on Sol, verify Sol; find on Opus, verify fell to Opus.) Cost: the primary verify on the
--      normal path moves Sol -> Opus (USD 2/10 -> 4/20 per Mtok); one verify is ~2,000 image tokens in and
--      ~700 out, so ~USD 0.011 -> ~USD 0.022 a page. The gemini fallback is USD 0.75/3.75.
--      Every other pair already has at least one other-family option through the router (Sol <-> Opus);
--      no other policy row moves. Measured costs per review below.
--   5. The authors' models are recorded where the review can read them:
--      * quotes.extracted_by_model + quote_extraction_model(supplier:inquiry -> model): quote_extract
--        returns the model that read the file; supplier_api records it against the supplier and inquiry and
--        copies it onto the quote the supplier submits from it. quote_compare passes the distinct models
--        of the quotes it compares ('deterministic' for typed / code-read quotes; an upload with no record
--        passes 'unknown', which fails closed to the deterministic ranking).
--      * fn_ceo_judgement_counterparts(): every model the five non-CEO seats wrote on in the last 7 days
--        (ai_cost_log.seat, ok, a real model), or 'deterministic'. Conservative on purpose: the CEO's
--        judgement input carries the marketing report and every open directive reply, and a log row does
--        not say which of them it produced, so the CEO avoids every family any seat used.
--   6. NEVER UNREVIEWED (coordinator ruling on #880). When the authors span both judgement families (Sol and Opus),
--      the router's last resort is a third family: google/gemini-3.8-flash, then z-ai/glm-5.3-flash, returned with
--      reviewer_tier 'third_family_fallback' and kept on ai_cost_log.reviewer_tier. If no third family is healthy
--      either, the gateway HOLDS the call (review_hold) and fn_it_review_independence_watch raises a CEO-owned
--      finding (duty:review_independence:*, sent to the founder's report). Same rule for every review class.
--
-- COST: no new model call anywhere. Only which model answers changes. Opus reviewing a Sol author costs
--   USD 4/20 per Mtok against Sol's 2/10: a ceo_judgement (~6k in / 1.5k out) USD 0.039 -> 0.054;
--   a quote_comparison (~8k in / ~5k out) USD 0.066 -> 0.132. Every route stays HELD until OpenRouter is
--   funded; this file does not touch the hold.
--
-- WHAT THIS FILE DOES NOT DO: it does not lift the hold, call a model, change fn_ai_route, or give the
--   unwired classes (knowledge_validation, ceo_approval_decision) a caller. When one is wired, the gateway
--   refuses it until it names its author's model. Legacy upload quotes (before this file) carry no
--   extraction model and fail closed to the deterministic ranking.
--
--   node scripts/apply_sql.mjs scripts/sql/every_review_class_is_judged_by_another_family_than_its_author.sql --apply --ddl
--   (after a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql; it redefines that file's router)
--
-- Idempotent and without begin/commit: the check replays it inside an aborted transaction before apply.

-- ── 1. WHICH CLASS JUDGES WHICH ─────────────────────────────────────────────────────────────────
alter table public.model_policy add column if not exists reviews_class text[];
comment on column public.model_policy.reviews_class is
  'The author task classes this class reviews, judges, verifies, compares or approves. Non-empty => a review class: '
  'ai_gateway refuses it without counterpart_model and routes it through fn_ai_route_review '
  '(every_review_class_is_judged_by_another_family_than_its_author.sql).';

update public.model_policy set reviews_class = v.authors
  from (values
    ('ceo_judgement',             array['marketing_copy','sales_engineer_reasoning','customer_communication','support_ai',
                                        'accountant_weekly_report','accountant_expense_classification','finance_analysis',
                                        'engineering_reasoning','routine_employee_reasoning']),
    ('ceo_approval_decision',     array['accountant_expense_classification','accountant_receipt_extraction','finance_analysis',
                                        'sales_engineer_reasoning','support_ai']),
    ('identity_redaction_verify', array['document_extraction']),
    ('quote_comparison',          array['document_extraction']),
    ('drawing_boq_confirm',       array['document_extraction','drawing_and_boq_analysis']),
    ('knowledge_validation',      array['knowledge_ingestion','knowledge_research']),
    ('seat_deliberation_blind',   array['marketing_copy','sales_engineer_reasoning','ceo_strategic_planning']),
    ('seat_deliberation_compare', array['marketing_copy','sales_engineer_reasoning','ceo_strategic_planning'])
  ) as v(task_class, authors)
 where model_policy.task_class = v.task_class;

-- ── 4. THE THIRD FAMILY BEHIND THE REDACTION VERIFY ─────────────────────────────────────────────
update public.model_policy
   set model_fallback = 'google/gemini-3.8-flash',
       rationale = rationale || ' | 23 Sep 2026 (it_engineer, founder instruction ~891): fallback opus-5.5 -> gemini-3.8-flash, '
                   || 'a third family. The find (document_extraction) runs on Sol or Opus; fn_ai_route_review sends the verify to '
                   || 'the other one, and gemini keeps the fallback independent of both.'
 where task_class = 'identity_redaction_verify' and model_fallback is distinct from 'google/gemini-3.8-flash';

-- ── 2. THE ROUTER, GENERALISED ──────────────────────────────────────────────────────────────────
create or replace function public.fn_ai_route_review(p_task_class text, p_counterpart_model text,
  p_agent_key text default null, p_fn text default null, p_dept_key text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_names text[];
  v_fams  text[] := '{}';
  v_unknown text[] := '{}';
  v_n text; v_f text;
  v_base jsonb;
  v_rej  jsonb := '[]'::jsonb;
  v_pick text; v_pick_fam text; v_fb text; v_tier text;
  c record;
begin
  select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}') into v_names
    from unnest(string_to_array(coalesce(p_counterpart_model, ''), ',')) x;
  foreach v_n in array v_names loop
    continue when v_n = 'deterministic';
    select lower(btrim(r.provider)) into v_f from public.model_registry r where r.model_id = v_n;
    if v_f is null then v_unknown := v_unknown || v_n; else v_fams := array(select distinct unnest(v_fams || v_f)); end if;
  end loop;

  if cardinality(v_names) = 0 or cardinality(v_unknown) > 0 then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true, 'task_class', p_task_class,
      'author_model', p_counterpart_model,
      'why', 'NO INDEPENDENT REVIEWER: the author''s model ' || coalesce(nullif(array_to_string(v_unknown, ', '), ''), '(none given)')
             || ' is not in model_registry, so its family is unknown and independence cannot be proved.');
  end if;

  v_base := public.fn_ai_route(p_task_class, p_dept_key, null, p_fn, false, null, p_agent_key);
  if not coalesce((v_base->>'use_llm')::boolean, false) then
    return v_base || jsonb_build_object('author_model', p_counterpart_model, 'author_family', to_jsonb(v_fams));
  end if;

  -- Every author is code: there is no family to keep away from, and the class routes as configured.
  if cardinality(v_fams) = 0 then
    return v_base || jsonb_build_object('author_model', 'deterministic', 'author_family', '[]'::jsonb, 'independent', true,
      'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: the author is deterministic code, not a model');
  end if;

  for c in
    with pol as (select model_primary, model_fallback from public.model_policy where task_class = v_base->>'task_class'),
    cand as (
      select pol.model_primary model_id, 0 ord from pol
      union all select p.model_id, p.rank from public.review_pool p where p.active
      union all select pol.model_fallback, 1000000 from pol
      -- LAST RESORT, THIRD FAMILY (coordinator ruling on #880): when every candidate above shares an author's
      -- family (authors on both Sol and Opus), a review goes to a third family rather than unreviewed.
      union all select 'google/gemini-3.8-flash', 2000000
      union all select 'z-ai/glm-5.3-flash', 2000001)
    select d.model_id, d.ord, lower(btrim(r.provider)) provider, coalesce(r.active and r.approved, false) reg_ok,
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
    elsif not c.measured then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'no llm_route_health row: unmeasured is not healthy');
    elsif c.tripped then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'breaker tripped by real failures');
    elsif v_pick is null then
      v_pick := c.model_id; v_pick_fam := c.provider;
      v_tier := case when c.ord >= 2000000 then 'third_family_fallback' else 'standard' end;
    elsif v_fb is null and (c.ord < 2000000 or v_tier = 'third_family_fallback') then
      -- the third family is a last resort for the PICK, not a routine fallback behind a healthy reviewer
      v_fb := c.model_id;
    end if;
  end loop;

  if v_pick is null then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true,
      'task_class', v_base->>'task_class', 'author_model', p_counterpart_model, 'author_family', to_jsonb(v_fams),
      'pool_rejected', v_rej,
      'why', 'NO INDEPENDENT REVIEWER: no active, healthy candidate outside the ' || array_to_string(v_fams, '/')
             || ' family. The review does not fall back to an author''s family (founder instructions 873, ~891).');
  end if;

  return v_base || jsonb_build_object(
    'model', v_pick, 'fallback', v_fb,
    'in_per_mtok_usd', (select in_per_mtok_usd from public.model_registry where model_id = v_pick),
    'out_per_mtok_usd', (select out_per_mtok_usd from public.model_registry where model_id = v_pick),
    'reviewer_family', v_pick_fam, 'reviewer_tier', v_tier, 'author_model', p_counterpart_model, 'author_family', to_jsonb(v_fams),
    'independent', true, 'pool_rejected', v_rej,
    'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: author wrote on ' || p_counterpart_model
           || ' (' || array_to_string(v_fams, '/') || '), reviewer routed to ' || v_pick || ' (' || v_pick_fam || ')'
           || coalesce(', fallback ' || v_fb, ', no fallback outside ' || array_to_string(v_fams, '/')));
end $fn$;
revoke execute on function public.fn_ai_route_review(text, text, text, text, text) from public, anon, authenticated;

-- ── 3. THE BACKSTOP ON EVERY LOGGED CALL ────────────────────────────────────────────────────────
alter table public.ai_cost_log add column if not exists counterpart_model text;
alter table public.ai_cost_log add column if not exists review_violation text;
comment on column public.ai_cost_log.review_violation is
  'Set by trg_ai_cost_log_review_family on a review-class call that ran on an author''s family or named no author. '
  'Must stay null; scripts/checks/no_review_class_can_route_to_its_authors_family.test.mjs fails on any row.';

create or replace function public.trg_ai_cost_log_review_family()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fam text; v_hit text;
begin
  if new.counterpart_model is null then
    new.counterpart_model := substring(coalesce(new.model_selected_because, '') from 'counterpart_model=([^ |]+)');
  end if;
  if coalesce(new.model_used, 'none') = 'none'
     or not exists (select 1 from public.model_policy p
                     where p.task_class = new.task_class and cardinality(coalesce(p.reviews_class, '{}')) > 0) then
    return new;
  end if;
  if new.counterpart_model is null then
    new.review_violation := 'REVIEW_WITHOUT_COUNTERPART: ' || new.task_class || ' ran on ' || new.model_used || ' naming no author model';
    return new;
  end if;
  select lower(btrim(provider)) into v_fam from public.model_registry where model_id = new.model_used;
  select string_agg(x, ',') into v_hit
    from unnest(string_to_array(new.counterpart_model, ',')) x
    join public.model_registry r on r.model_id = btrim(x)
   where lower(btrim(r.provider)) = v_fam;
  if v_hit is not null then
    new.review_violation := 'SAME_FAMILY_REVIEW: ' || new.task_class || ' ran on ' || new.model_used || ' over ' || v_hit;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_ai_cost_log_review_family() from public, anon, authenticated;
drop trigger if exists trg_ai_cost_log_review_family on public.ai_cost_log;
create trigger trg_ai_cost_log_review_family before insert on public.ai_cost_log
  for each row execute function public.trg_ai_cost_log_review_family();

-- ── 5a. WHICH MODEL READ A SUPPLIER'S QUOTATION ─────────────────────────────────────────────────
create table if not exists public.quote_extraction_model (
  subject_key  text primary key,   -- "<supplier lead id>:<inquiry id>", the latest reading for that pair
  model        text not null check (btrim(model) <> ''),
  extracted_at timestamptz not null default now()
);
alter table public.quote_extraction_model enable row level security;
drop policy if exists quote_extraction_model_service_role_only on public.quote_extraction_model;
create policy quote_extraction_model_service_role_only on public.quote_extraction_model
  as permissive for all to public using (false) with check (false);
revoke all on public.quote_extraction_model from anon, authenticated;
comment on table public.quote_extraction_model is
  'supplier_api writes the model quote_extract read an uploaded quotation with (or ''deterministic''); the submitted quote copies it '
  'to quotes.extracted_by_model so quote_compare can name its author (every_review_class_is_judged_by_another_family_than_its_author.sql).';
alter table public.quotes add column if not exists extracted_by_model text;

-- ── 5b. THE MODELS THE CEO'S JUDGEMENT INPUT WAS WRITTEN ON ─────────────────────────────────────
create or replace function public.fn_ceo_judgement_counterparts()
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(string_agg(distinct l.model_used, ',' order by l.model_used), 'deterministic')
    from public.ai_cost_log l
   where l.seat in ('marketing', 'sales_engineer', 'customer_support', 'accountant', 'it_engineer')
     and l.ok and coalesce(l.model_used, 'none') not in ('none', '')
     and l.occurred_at > now() - interval '7 days';
$fn$;
revoke execute on function public.fn_ceo_judgement_counterparts() from public, anon, authenticated;

-- ── 6. NEVER UNREVIEWED: THE THIRD-FAMILY RECORD, THE HOLD, AND THE CEO'S FINDING ───────────────
-- Coordinator ruling on #880: a judgement must never go unreviewed nor be reviewed on an author's family.
-- The router's last resort is a third family (gemini-3.8-flash, then glm-5.3-flash), returned with
-- reviewer_tier 'third_family_fallback'; the gateway writes it into the log line and this column keeps it.
-- When no third family is healthy either, the gateway HOLDS the call (no model runs) and records a
-- review_hold; fn_it_review_independence_watch turns open holds into a CEO-owned finding, and reports every
-- third-family review of the last 7 days so the agreement monitor and the founder's brief can see it.
alter table public.ai_cost_log add column if not exists reviewer_tier text;

create or replace function public.trg_ai_cost_log_reviewer_tier()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.reviewer_tier is null then
    new.reviewer_tier := substring(coalesce(new.model_selected_because, '') from 'reviewer_tier=([a-z_]+)');
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_ai_cost_log_reviewer_tier() from public, anon, authenticated;
drop trigger if exists trg_ai_cost_log_reviewer_tier on public.ai_cost_log;
create trigger trg_ai_cost_log_reviewer_tier before insert on public.ai_cost_log
  for each row execute function public.trg_ai_cost_log_reviewer_tier();

create table if not exists public.review_hold (
  id                bigserial primary key,
  task_class        text not null,
  fn                text,
  agent_key         text,
  counterpart_model text not null,
  why               text not null,
  held_at           timestamptz not null default now(),
  last_held_at      timestamptz not null default now(),
  times_held        integer not null default 1,
  closed_at         timestamptz,
  close_note        text
);
create unique index if not exists review_hold_one_open
  on public.review_hold (task_class, coalesce(fn, ''), counterpart_model) where closed_at is null;
alter table public.review_hold enable row level security;
drop policy if exists review_hold_service_role_only on public.review_hold;
create policy review_hold_service_role_only on public.review_hold as permissive for all to public using (false) with check (false);
revoke all on public.review_hold from anon, authenticated;

create or replace function public.fn_review_hold_record(p_task_class text, p_fn text, p_agent_key text,
  p_counterpart_model text, p_why text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  insert into public.review_hold (task_class, fn, agent_key, counterpart_model, why)
  values (coalesce(p_task_class, '(unresolved)'), p_fn, p_agent_key, coalesce(nullif(btrim(p_counterpart_model), ''), '(none)'),
          left(coalesce(p_why, 'no independent reviewer'), 2000))
  on conflict (task_class, coalesce(fn, ''), counterpart_model) where closed_at is null
  do update set last_held_at = now(), times_held = review_hold.times_held + 1, why = excluded.why
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_review_hold_record(text, text, text, text, text) from public, anon, authenticated;

create or replace function public.fn_it_review_independence_items()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with held as (
    select jsonb_build_object(
             'item', 'review_held:' || task_class, 'owner_seat', 'ceo', 'subject', 'review_independence',
             'title', count(*) || ' ' || task_class || ' review(s) HELD: no healthy reviewer outside the authors'' families, '
                      || 'not even a third family. Nothing ran unreviewed or same-family; restore a reviewer or decide the held work.',
             'blast', 'agent_facing', 'affected', sum(times_held),
             'evidence', jsonb_build_object('review_hold_ids', jsonb_agg(id order by id), 'authors', jsonb_agg(distinct counterpart_model))) x
      from public.review_hold where closed_at is null group by task_class
  ), third as (
    select jsonb_build_object(
             'item', 'third_family_review:' || task_class, 'owner_seat', 'ceo', 'subject', 'review_independence',
             'title', count(*) || ' ' || task_class || ' review(s) in 7 days ran on the THIRD-FAMILY last resort ('
                      || string_agg(distinct model_used, ', ') || ') because the authors spanned both judgement families.',
             'blast', 'agent_facing', 'affected', count(*),
             'evidence', jsonb_build_object('ai_cost_log_ids', jsonb_agg(id order by id))) x
      from public.ai_cost_log
     where reviewer_tier = 'third_family_fallback' and occurred_at > now() - interval '7 days'
     group by task_class
  )
  select coalesce((select jsonb_agg(x) from held), '[]'::jsonb) || coalesce((select jsonb_agg(x) from third), '[]'::jsonb);
$fn$;
revoke execute on function public.fn_it_review_independence_items() from public, anon, authenticated;

create or replace function public.fn_it_review_independence_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_closed int; v_items jsonb;
begin
  -- a hold closes itself once the same class, over the same authors, has since been reviewed independently
  update public.review_hold h set closed_at = now(), close_note = 'reviewed independently after the hold: ai_cost_log '
         || (select min(l.id) from public.ai_cost_log l
              where l.task_class = h.task_class and l.counterpart_model = h.counterpart_model and l.ok
                and l.review_violation is null and l.occurred_at > h.last_held_at)
   where h.closed_at is null
     and exists (select 1 from public.ai_cost_log l
                  where l.task_class = h.task_class and l.counterpart_model = h.counterpart_model and l.ok
                    and l.review_violation is null and l.occurred_at > h.last_held_at);
  get diagnostics v_closed = row_count;
  v_items := public.fn_it_review_independence_items();
  return jsonb_build_object('closed_holds', v_closed, 'items', jsonb_array_length(v_items),
                            'settle', public.fn_it_duty_settle('review_independence', v_items));
end $fn$;
revoke execute on function public.fn_it_review_independence_watch() from public, anon, authenticated;

insert into public.it_founder_decision_class (issue_key_like, to_founder, why) values
  ('duty:review_independence:%', true,
   'Coordinator ruling on #880 (founder instruction ~891): a review held for want of an independent model, or run on the '
   || 'third-family last resort, is his to see in the regular report.')
on conflict (issue_key_like) do nothing;

-- ── PROBE: returns a verdict row; cleans up nothing because it writes nothing ───────────────────
select case
  when (select count(*) from public.model_policy where cardinality(coalesce(reviews_class, '{}')) > 0) < 8
    then 'PROBE FAILED: fewer than 8 review classes declared'
  when public.fn_ai_route_review('identity_redaction_verify', 'openai/gpt-5.6-sol')->>'model' = 'openai/gpt-5.6-sol'
    then 'PROBE FAILED: the redaction verify routed onto the find''s family'
  else 'PROBE OK' end as verdict;
