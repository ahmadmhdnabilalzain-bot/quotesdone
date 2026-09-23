-- ROUTING AND THE CEO'S DECISIONS ARE REASONED, NOT WORD-MATCHED — decision points 47-54 of
-- supabase/functions/_shared/decision_points.json.
-- Seats: ceo (fn_should_escalate, fn_decide, fn_ceo_refund_checklist, fn_task_review) and sales_engineer
-- (fn_resolve_cat_agent, fn_category_expert_ref, trg_inquiry_enrich, fn_supplier_document_home).
-- 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
--
-- WHY. Eight SQL routines decided what text MEANS by spotting words, and several of those meanings act:
--   * fn_should_escalate: a legal_triggers entry appearing inside the text escalated (position()), and an
--     earlier failure "repeated" when three of its long words did — "is a refund dispute legal?" escalated,
--     "the supplier sued us" did not;
--   * fn_ceo_refund_checklist: reason_note ~* off-platform was a signed-terms EXCLUSION, which declines the
--     refund — "they never used the platform to pay" matched nothing, "not off-platform" matched;
--   * fn_decide: the invite pool took any supplier whose category text CONTAINED the slug;
--   * fn_task_review: the owner was the longest responsibility whose words were in the task, and a
--     collaboration rule (possibly blocking) applied when two of its words were;
--   * fn_supplier_document_home: a regex on the supplier's label decided ISO / insurance / authorisation;
--   * trg_inquiry_enrich: a repeat request was an ilike of the first 40 characters;
--   * fn_resolve_cat_agent / fn_category_expert_ref: a substring or regex chose the category desk.
--
-- WHAT.
--   1. fn_reason_route_ask files a meaning question into the owning seat's queue (reasoning_held_question)
--      with the exact think() request (seat, surface, question, named options, subject, dedupe key), and
--      fn_reason_route_answer reads the reasoned choice back by that key. replayHeld (think.ts, run by
--      resilience_ping each tick) reasons the question the moment a model may run; fn_reason_held_resolve
--      then calls the surface's own fn_reason_apply_<surface> below, which re-runs the waiting step.
--      The questions of this file never expire (expires_at null): what waits on them is money, an
--      escalation or an owner, not a chat that goes stale. A row that expired or failed (five model
--      failures) is reopened the next time the waiting step asks, so nothing waits on a dead question.
--   2. Each routine reads the reasoned answer and never the text: escalation (ceo.escalation_meaning),
--      refund exclusion (ceo.refund_off_platform), task ownership (ceo.task_responsibility,
--      ceo.task_collaboration_rule), supplier document (supplier_documents.subject), repeat request
--      (inquiry.same_request). The option ids are the ones in supabase/functions/_shared/reasoned_routing.ts
--      (reasoned_routing.test.ts fails on drift).
--   3. The category routines keep only DECLARED mappings (slug, trade map, exact catalogue name); a
--      category nobody declared resolves to no desk, which every caller already reads as unmatched.
--   4. Exact list membership replaces the substring in fn_decide's invite pool (a list is parsed, not read).
--
-- UNDER THE MODEL HOLD (measured 23 Sep 2026: fn_kernel_paid_provider_gate answers founder_hold) nothing
-- here is decided on a word: an escalation returns 'awaiting_reasoning' and records nothing; a refund whose
-- notes are unread is neither approved nor declined and pages nobody (fn_ceo_refund_review
-- 'waiting_on_reasoning', no cycle spent); a task's owner is not recorded yet; a supporting document fills
-- no slot yet; a differently worded repeat is not flagged yet. Every one waits, visible, in its seat's queue.
--
-- MEASURED 23 Sep 2026 (read-only): collaboration_rule 0 rows, os_responsibility 84, refunds with a
-- reason_note 0, supplier_response_watch.close_reason 0, decision_log rows in the last 7 days 0 (fn_decide
-- and fn_should_escalate have no caller in supabase/functions or in any other routine but each other),
-- supplier_supporting documents 7 (6 live, each asked about once by this file), inquiries
-- flagged possible_duplicate 0 and no reader of that flag. Each routine's body is the production
-- definition of that date (pg_get_functiondef), changed only where marked 23 Sep 2026.
--
-- Follows every_seat_reasons_before_it_answers.sql, meaning_is_decided_by_reasoning_not_by_word_lists.sql
-- and a_reasoned_answer_is_applied_by_its_own_surface.sql.
-- Applies after fn_decide_reads_its_prior_outcomes_inline.sql (#896) and a_held_question_never_expires_it_is_escalated_at_48_hours.sql.
-- Pending: scripts/sql/pending/routing_and_ceo_decisions_are_reasoned_not_word_matched.txt.
-- Proved in one aborted transaction: scripts/checks/decision_points_are_reasoned.test.mjs.

-- ── 1. the question, and its answer ─────────────────────────────────────────────────────────────────
create or replace function public.fn_reason_route_ask(p_seat text, p_surface text, p_question text, p_options jsonb,
  p_subject jsonb, p_dedupe_key text)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint; v_q text := left(btrim(coalesce(p_question, '')), 8000);
begin
  -- Nothing to reason about (no text, or fewer than two options): no question, and the caller says so.
  if v_q = '' or coalesce(btrim(p_dedupe_key), '') = '' or jsonb_typeof(p_options) is distinct from 'array'
     or jsonb_array_length(p_options) < 2 then
    return null;
  end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, expires_at)
  values (p_seat, p_surface, v_q,
          jsonb_build_object('seat', p_seat, 'surface', p_surface, 'question', v_q,
                             'context', jsonb_build_object('audience', 'internal'),
                             'decision', jsonb_build_object('name', p_surface, 'options', p_options),
                             'subject', p_subject, 'dedupeKey', p_dedupe_key),
          jsonb_build_object('pending', jsonb_build_array('decompose', 'resolve', 'retrieve', 'decide'), 'filed_by', 'sql'),
          p_subject, 'awaiting_reasoning', p_dedupe_key, null)
  on conflict (dedupe_key) do update set status = 'held', attempts = 0, last_attempt_at = null, expires_at = null
   where reasoning_held_question.status = 'expired'
      -- a failed question (five model failures) reopens at most once a day, so a broken model is not paid for on every tick
      or (reasoning_held_question.status = 'failed' and coalesce(reasoning_held_question.last_attempt_at, reasoning_held_question.created_at) < now() - interval '24 hours')
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.reasoning_held_question where dedupe_key = p_dedupe_key;
  end if;
  return v_id;
end $fn$;
revoke execute on function public.fn_reason_route_ask(text, text, text, jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_reason_route_ask(text, text, text, jsonb, jsonb, text) to service_role;

create or replace function public.fn_reason_route_answer(p_dedupe_key text)
returns text
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select h.result->'decision'->>'choice' from public.reasoning_held_question h
   where h.dedupe_key = p_dedupe_key and h.status in ('reasoned', 'applied')
     and coalesce(h.result->'decision'->>'choice', '') <> '';
$fn$;
revoke execute on function public.fn_reason_route_answer(text) from public, anon, authenticated;
grant execute on function public.fn_reason_route_answer(text) to service_role;

-- ── 2. the category desk: declared mappings only (sql.fn_resolve_cat_agent, sql.fn_category_expert_ref) ──
create or replace function public.fn_resolve_cat_agent(cat text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
declare k text; c text := lower(trim(coalesce(cat,'')));
begin
  if c = '' then return null; end if;

  -- Hop 1 and 2, unchanged: the caller already holds a catalogue slug.
  if exists(select 1 from category_agents where slug=c and coalesce(active,true)) then return 'cat:'||c; end if;
  if exists(select 1 from agent_knowledge where agent_key='cat:'||c limit 1) then return 'cat:'||c; end if;

  -- Hop 3, NEW: the declared trade -> catalogue bridge, the same one fn_category_knowledge walks.
  -- Before the name LIKE, because a mapping somebody decided beats a substring that happens to hit.
  select 'cat:'||m.catalog_slug into k
    from lead_trade_map m
   where m.trade_key = c
     and exists (select 1 from agent_knowledge a where a.agent_key = 'cat:'||m.catalog_slug)
   limit 1;
  if k is not null then return k; end if;

  -- Hop 4: the catalogue's own display name, EXACTLY (23 Sep 2026, founder_instruction 886-903). This was
  -- a substring match both ways (name contains the category, or the category contains a slug), which
  -- decided the desk by which letters happened to overlap: 'tile' found 'textile', 'ac' found every name
  -- with those two letters. A category nothing declares resolves to NO desk (null); every caller already
  -- reads null as unmatched (fn_decide 'unmatched', trg_ingest_case_lessons '_global'). Nothing is guessed.
  select 'cat:'||slug into k from category_agents
    where coalesce(active,true) and lower(btrim(name)) = c
    order by slug limit 1;
  return k;
end $function$;
revoke execute on function public.fn_resolve_cat_agent(text) from public, anon, authenticated;
grant execute on function public.fn_resolve_cat_agent(text) to service_role;

-- The expert reference follows the same declared mapping. A fifteen-branch regex on the category chose the
-- knowledge slug; fn_resolve_cat_agent (exact slug, the trade map, the exact catalogue name) now does, and a
-- category nothing declares has no expert reference — which is what the old `else` branch returned too.
create or replace function public.fn_category_expert_ref(p_category text)
returns text
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_key text; v_txt text;
begin
  v_key := public.fn_resolve_cat_agent(p_category);
  if v_key is null then return ''; end if;
  select string_agg('## '||topic||E'\n'||content, E'\n\n' order by topic, content)
    into v_txt from agent_knowledge
    where agent_key = v_key
      and topic in ('Pricing benchmarks & red flags','Quote analysis & comparison',
                    'Standards, materials & specifications','Field expertise — UAE codes, standards & specs');
  return left(coalesce(v_txt,''), 4500);
end $fn$;
revoke execute on function public.fn_category_expert_ref(text) from public, anon, authenticated;
grant execute on function public.fn_category_expert_ref(text) to service_role;


-- ── 1b. a supplier's trade, reasoned from its own record (sql.leads_categories_keyword_v1) ───────────
-- leads.categories is free text (measured 23 Sep 2026: 22,234 of 22,272 leads carry it, and it holds company
-- names such as "MAPEI" as often as trades), and lead_category was filled by keyword_v1. Neither decides a
-- supplier's trade any more. Each lead is classified onto the 195-trade taxonomy (taxonomy_trade) by the
-- sales engineer seat's REASONING over its licence authority, stated categories, description and website;
-- the nearest trades by meaning (gte-small, free, over taxonomy_trade_service) are given to the reasoning as
-- a hint and recorded beside the answer, and never decide it. Each answer is stored with its evidence and
-- confidence. Until a lead is classified it is in NO trade's pool (fn_decide invite, fn_twin category).
create table if not exists public.lead_trade_class (
  lead_id     bigint primary key references public.leads(id) on delete cascade,
  trade_code  text,                       -- a taxonomy_trade.code, or null when the reasoning says none applies
  confidence  numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  evidence    text not null check (btrim(evidence) <> ''),
  shortlist   jsonb not null default '[]'::jsonb,
  shortlist_agreed boolean,               -- did the reasoned trade appear in the embedding shortlist (corroboration)
  held_id     bigint,
  decided_by  text not null default 'reasoning' check (decided_by = 'reasoning'),
  decided_at  timestamptz not null default now()
);
create index if not exists lead_trade_class_trade_idx on public.lead_trade_class (trade_code);
alter table public.lead_trade_class enable row level security;
drop policy if exists lead_trade_class_service_role_only on public.lead_trade_class;
create policy lead_trade_class_service_role_only on public.lead_trade_class
  as permissive for all to public using (false) with check (false);
revoke all on public.lead_trade_class from anon, authenticated;

-- THE BACKFILL IS A SPEND, SO IT IS GATED, CAPPED AND PRICED BEFORE IT RUNS (founder: quote the cost first).
--   gate:  app_secrets.lead_reclassify_backfill = 'go'  — absent or anything else: the tick files nothing.
--   cap:   app_secrets.lead_reclassify_daily_cap (default 95 leads per Dubai day).
--   price: 1 lead = 1 held question = ~3 model calls when replayed (decompose + up to 2 decide passes), ~12k in /
--          0.7k out tokens on agent_reasoning (openai/gpt-5.6-sol, priced here at USD 2 / 10 per million, the
--          class's own quoted band) = ~USD 0.031 = ~AED 0.114 per lead; 22,272 leads = ~AED 2,540 in total;
--          the default cap of 95 a day = ~AED 10.8 a day = ~AED 325 a month, 25 % of the marketplace
--          department's AED 1,300 monthly ceiling (department_budget, measured 23 Sep 2026); ~235 days.
-- The estimate is written next to the gate so whoever says 'go' reads it first. Nothing here sets the gate.
insert into public.app_secrets (key, value) values
  ('lead_reclassify_daily_cap', '95'),
  ('lead_reclassify_cost_estimate', 'AED ~0.114 per lead (~3 calls, ~12k in / 0.7k out tokens, agent_reasoning at USD 2/10 per M); 22,272 leads = ~AED 2,540; cap 95/day = ~AED 10.8/day, ~AED 325/month (25% of the marketplace AED 1,300 ceiling). Gate: lead_reclassify_backfill = go.')
on conflict (key) do nothing;

-- The earlier one-argument shape is dropped so exactly one signature exists (none is live yet).
drop function if exists public.fn_lead_reclassify_tick(integer);
create or replace function public.fn_lead_reclassify_tick(p_limit integer default 20, p_only bigint[] default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_gate text; v_cap int; v_today int; v_room int; v_n int := 0; l record; v_short jsonb; v_opts jsonb; v_day timestamptz;
begin
  select value into v_gate from public.app_secrets where key = 'lead_reclassify_backfill';
  if coalesce(btrim(v_gate), '') <> 'go' then
    return jsonb_build_object('ran', false, 'reason', 'gate_off', 'gate_key', 'lead_reclassify_backfill');
  end if;
  -- Nothing is filed while the model hold is on: a question filed under the hold would only wait 48 hours and
  -- land in the sales engineer's queue as a pending item, 95 a day. The backfill runs only when it can reason.
  if coalesce(public.fn_kernel_paid_provider_gate('hold-probe/not-a-model')->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return jsonb_build_object('ran', false, 'reason', 'model_hold');
  end if;
  begin select btrim(value)::int into v_cap from public.app_secrets where key = 'lead_reclassify_daily_cap';
  exception when others then v_cap := null; end;
  v_cap := greatest(0, coalesce(v_cap, 95));
  v_day := date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  select count(*) into v_today from public.reasoning_held_question where surface = 'lead_trade.classify' and created_at >= v_day;
  v_room := greatest(0, least(greatest(coalesce(p_limit, 20), 0), v_cap - v_today));
  if v_room = 0 then
    return jsonb_build_object('ran', false, 'reason', 'daily_cap', 'cap', v_cap, 'filed_today', v_today);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', t.code, 'meaning', t.label) order by t.sort, t.code), '[]'::jsonb)
         || jsonb_build_array(jsonb_build_object('id', 'none', 'meaning', 'no trade in this list is what the company supplies or performs'))
    into v_opts from public.taxonomy_trade t where t.active;
  for l in
    select x.* from public.leads x
     where (p_only is null or x.id = any (p_only))   -- p_only: a named set (the probe's ZZ DEMO leads); null = every lead
       and not exists (select 1 from public.lead_trade_class c where c.lead_id = x.id)
       -- a question still waiting, or one that failed within the day, is not asked again; one whose answer could not be
       -- stored (fn_reason_apply_lead_trade__classify puts it back to held) is waiting again, so it is skipped here too
       and not exists (select 1 from public.reasoning_held_question h where h.dedupe_key = 'lead_trade:' || x.id
                         and (h.status = 'held' or (h.status = 'failed' and coalesce(h.last_attempt_at, h.created_at) > now() - interval '24 hours')))
     order by (coalesce(x.approval_status, '') = 'approved') desc, x.id   -- approved suppliers first: they are the live pools
     limit v_room
  loop
    v_short := '[]'::jsonb;
    if l.embedding_gte is not null then
      select coalesce(jsonb_agg(distinct z.trade_code), '[]'::jsonb) into v_short
        from (select s.trade_code from public.taxonomy_trade_service s
               where s.active and s.embedding_gte is not null
               order by s.embedding_gte <=> l.embedding_gte limit 8) z;
    end if;
    perform public.fn_reason_route_ask('sales_engineer', 'lead_trade.classify',
      concat_ws(E'\n',
        'Company: ' || l.company_name,
        'Licence authority: ' || nullif(btrim(coalesce(l.license_authority, '')), ''),
        'Stated categories (the supplier''s or a directory''s free text; may name the company, not its trade): ' || nullif(btrim(coalesce(l.categories, '')), ''),
        'Sub type: ' || nullif(btrim(coalesce(l.sub_type, '')), ''),
        'Description: ' || left(nullif(btrim(coalesce(l.description, '')), ''), 1500),
        'Website: ' || nullif(btrim(coalesce(l.website, '')), ''),
        case when jsonb_array_length(v_short) > 0
             then 'Nearest trades by meaning (a hint to check, never the answer): ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_short) x) end,
        'Which trade in the taxonomy does this company supply or perform? Answer none if the record does not say.'),
      v_opts, jsonb_build_object('lead_id', l.id, 'shortlist', v_short), 'lead_trade:' || l.id);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ran', true, 'filed', v_n, 'cap', v_cap, 'filed_today', v_today + v_n);
end $fn$;
revoke execute on function public.fn_lead_reclassify_tick(integer, bigint[]) from public, anon, authenticated;
grant execute on function public.fn_lead_reclassify_tick(integer, bigint[]) to service_role;

create or replace function public.fn_reason_apply_lead_trade__classify(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_code text; v_conf numeric;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if nullif(r.subject->>'lead_id', '') is null or coalesce(v_choice, '') = '' then return null; end if;
  select t.code into v_code from public.taxonomy_trade t where t.code = v_choice;
  if v_code is null and v_choice <> 'none' then
    -- an option that does not exist is not stored. The row keeps its (invalid) result for the record, and its dedupe
    -- key is released so the next tick asks again, within the daily cap.
    update public.reasoning_held_question set dedupe_key = dedupe_key || ':invalid:' || p_id where id = p_id;
    return jsonb_build_object('lead_id', (r.subject->>'lead_id')::bigint, 'stored', false, 'invalid_choice', v_choice);
  end if;
  begin v_conf := least(1, greatest(0, (p_result->>'confidence')::numeric)); exception when others then v_conf := null; end;
  insert into public.lead_trade_class (lead_id, trade_code, confidence, evidence, shortlist, shortlist_agreed, held_id)
  values ((r.subject->>'lead_id')::bigint, v_code, v_conf,
          left(coalesce(nullif(btrim(p_result->>'answer'), ''), 'reasoned without a stated reason'), 2000),
          coalesce(r.subject->'shortlist', '[]'::jsonb),
          case when v_code is null or jsonb_array_length(coalesce(r.subject->'shortlist', '[]'::jsonb)) = 0 then null
               else r.subject->'shortlist' ? v_code end, p_id)
  on conflict (lead_id) do update set trade_code = excluded.trade_code, confidence = excluded.confidence, evidence = excluded.evidence,
        shortlist = excluded.shortlist, shortlist_agreed = excluded.shortlist_agreed, held_id = excluded.held_id, decided_at = now();
  return jsonb_build_object('lead_id', (r.subject->>'lead_id')::bigint, 'trade_code', v_code);
end $fn$;
revoke execute on function public.fn_reason_apply_lead_trade__classify(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_lead_trade__classify(bigint, jsonb) to service_role;

-- ── 1c. the catalogue key of a trade word, declared or reasoned (sql.fn_category_key_for_slug) ────────
-- Rungs 3 and 4 matched the slug inside catalogue slugs and names (like '%-'||slug||'-%', name like
-- '%'||slug||'%'); measured 23 Sep 2026 they resolved 40 of the 56 vocabulary words. Those words are now asked
-- once each (category.key_for_slug, sales engineer) and the reasoned key is read back by its dedupe key.
-- Until answered the word has no key (null), which its callers already read as "no category".
create or replace function public.fn_category_key_for_slug(p_slug text)
returns text
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select i.category_key
    from (
      select m.catalog_num, 1 as pri from public.category_route_map m where m.category = lower(btrim(p_slug))
      union all
      select c.num, 2 from public.catalog_supplier_categories c where c.slug = lower(btrim(p_slug))
      union all
      select o.catalog_num, 3 from public.org_category_identity o
       where o.category_key = public.fn_reason_route_answer('category_key:' || lower(btrim(p_slug)))
    ) r
    join public.org_category_identity i on i.catalog_num = r.catalog_num
   where coalesce(btrim(p_slug), '') <> ''
   order by r.pri, i.category_key
   limit 1;
$fn$;
revoke execute on function public.fn_category_key_for_slug(text) from public, anon, authenticated;
grant execute on function public.fn_category_key_for_slug(text) to service_role;

create or replace function public.fn_category_key_ask(p_word text)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_w text := lower(btrim(coalesce(p_word, '')));
begin
  if v_w = '' or exists (select 1 from public.category_route_map m where m.category = v_w)
     or exists (select 1 from public.catalog_supplier_categories c where c.slug = v_w) then
    return null;
  end if;
  return public.fn_reason_route_ask('sales_engineer', 'category.key_for_slug',
    'The marketplace names a trade "' || v_w || '". Which catalogue category is that trade?',
    (select coalesce(jsonb_agg(jsonb_build_object('id', i.category_key, 'meaning', c.name) order by i.category_key), '[]'::jsonb)
       from public.org_category_identity i join public.catalog_supplier_categories c on c.num = i.catalog_num)
      || jsonb_build_array(jsonb_build_object('id', 'none', 'meaning', 'no catalogue category is that trade')),
    jsonb_build_object('word', v_w), 'category_key:' || v_w);
end $fn$;
revoke execute on function public.fn_category_key_ask(text) from public, anon, authenticated;
grant execute on function public.fn_category_key_ask(text) to service_role;

-- A key the reasoning names that the catalogue does not hold is not kept, and the word can be asked again.
create or replace function public.fn_reason_apply_category__key_for_slug(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_choice text := p_result->'decision'->>'choice';
begin
  if v_choice = 'none' or exists (select 1 from public.org_category_identity i where i.category_key = v_choice) then
    return jsonb_build_object('key', v_choice);
  end if;
  -- released for a later ask (fn_category_key_ask on the next category_specs insert), the invalid answer kept for the record
  update public.reasoning_held_question set dedupe_key = dedupe_key || ':invalid:' || p_id where id = p_id;
  return jsonb_build_object('key', null, 'invalid_choice', v_choice);
end $fn$;
revoke execute on function public.fn_reason_apply_category__key_for_slug(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_category__key_for_slug(bigint, jsonb) to service_role;

create or replace function public.trg_category_key_asked()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  perform public.fn_category_key_ask(NEW.category);
  return NEW;
end $fn$;
revoke execute on function public.trg_category_key_asked() from public, anon, authenticated;
grant execute on function public.trg_category_key_asked() to service_role;
create or replace trigger category_key_asked after insert on public.category_specs
  for each row execute function public.trg_category_key_asked();

-- The 40 vocabulary words no declared rung resolves (measured 23 Sep 2026) are asked once: ~AED 5 at the
-- per-question price above, a one-off, not a bulk backfill.
do $backfill$
begin
  perform public.fn_category_key_ask(w)
     from (select distinct lower(btrim(category)) w from public.category_specs
           union select distinct lower(btrim(category)) from public.inquiries where category is not null) s;
end $backfill$;

-- The category twin counts suppliers by their REASONED trade (sql.fn_twin).
create or replace function public.fn_twin(p_kind text, p_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  if p_kind='customer' then
    select jsonb_build_object('kind','customer','id',c.id,'name',c.full_name,'email',c.email,
      'industry',c.industry,
      'rfqs',(select count(*) from inquiries where customer_id=c.id),
      'deals',(select count(*) from transactions where customer_id=c.id),
      'spend_aed',(select coalesce(sum(reveal_fee),0) from transactions where customer_id=c.id and coalesce(fee_status,'')='paid'),
      'categories',(select coalesce(jsonb_agg(distinct category),'[]') from inquiries where customer_id=c.id),
      -- BUYING PATTERNS (§2) — categories ORDERED BY how often the customer actually buys them,
      -- with the count beside each. `categories` above is a set and a set is not a pattern.
      'preferred_categories',(select coalesce(jsonb_agg(jsonb_build_object('category',k.category,'rfqs',k.n) order by k.n desc),'[]')
         from (select category, count(*) n from inquiries where customer_id=c.id and category is not null
               group by category order by count(*) desc limit 8) k),
      'projects_active',(select count(*) from projects
         where customer_id=c.id and coalesce(status,'') not in ('closed','cancelled','completed','done')),
      'projects_total',(select count(*) from projects where customer_id=c.id),
      -- PREFERRED SUPPLIERS (§2) — the suppliers this customer has actually paid to reveal. A
      -- preference the customer demonstrated, not one they were asked to declare.
      'preferred_suppliers',(select count(distinct supplier_id) from transactions
         where customer_id=c.id and coalesce(fee_status,'')='paid' and supplier_id is not null),
      -- (No approval_chain key since 14 Sep 2026: the Approvals tab and the organisation/policy
      -- tables it read were removed — a company buys exactly like an individual. See
      -- a_company_buys_like_an_individual_so_the_approval_chain_is_dropped.sql.)
      'last_active',(select max(created_at) from inquiries where customer_id=c.id),
      -- AI UNDERSTANDING (§2) — the share of eight profile facts held, and ONLY once the customer
      -- has raised a request. Before that there is no buying behaviour to understand, and a tally of
      -- sign-up fields is not understanding (see the header of this file).
      'understanding_pct',(case when exists (select 1 from inquiries where customer_id=c.id) then
         (select round(100.0 * (
             (c.full_name is not null and c.full_name <> '')::int
           + (c.phone is not null and c.phone <> '')::int
           + coalesce(c.email_verified,false)::int
           + (c.tos_accepted_at is not null)::int
           + (c.locale is not null)::int
           + (c.industry is not null and c.industry <> '')::int
           + 1
           + (exists (select 1 from customer_preference cp where cp.customer_id=c.id))::int
         ) / 8.0)) end),
      'banned',c.banned) into res from customers c where c.id::text=p_id;

  elsif p_kind='rfq' then
    select jsonb_build_object('kind','rfq','id',i.id,'category',i.category,'emirate',i.emirate,'status',i.status,
      'completeness',i.completeness,'ready',i.rfq_ready,'budget',i.budget,
      'quotes',(select count(*) from quotes where inquiry_id=i.id),
      'avg_quote_quality',(select round(avg(nullif(quality->>'score','')::numeric),1) from quotes where inquiry_id=i.id),
      'matched_suppliers',(select count(*) from inquiry_matches where inquiry_id=i.id),
      'created',i.created_at,'completed',i.completed_at,'outcome',i.outcome) into res from inquiries i where i.id::text=p_id;

  elsif p_kind='category' then
    res := jsonb_build_object('kind','category','category',p_id,
      'demand_rfqs',(select count(*) from inquiries where category=p_id),
      -- The supplier's trade as REASONED from its own record (lead_trade_class, 23 Sep 2026), never a substring of
      -- the free-text categories column (which holds company names as often as trades, measured 23 Sep 2026).
      'approved_suppliers',(select count(*) from leads l join lead_trade_class c on c.lead_id = l.id
         where coalesce(l.approval_status,'')='approved' and c.trade_code = lower(btrim(p_id))),
      'supplier_pool_total',(select count(*) from lead_trade_class c where c.trade_code = lower(btrim(p_id))),
      'supplier_pool_unclassified',(select count(*) from leads l where not exists (select 1 from lead_trade_class c where c.lead_id = l.id)),
      'avg_quote_quality',(select round(avg(nullif(q.quality->>'score','')::numeric),1) from quotes q join inquiries i on i.id=q.inquiry_id where i.category=p_id),
      'agent',public.fn_resolve_cat_agent(p_id));

  elsif p_kind='company' then
    res := jsonb_build_object('kind','company','name','QuotesDone',
      'health',public.fn_health_index(),
      'suppliers_total',(select count(*) from leads),'suppliers_approved',(select count(*) from leads where coalesce(approval_status,'')='approved'),
      'customers',(select count(*) from customers),'rfqs',(select count(*) from inquiries),'quotes',(select count(*) from quotes),
      'revenue_paid_aed',(select coalesce(sum(reveal_fee),0) from transactions where coalesce(fee_status,'')='paid'),
      'eval',public.fn_eval_snapshot(30));
  else
    res := jsonb_build_object('error','kind must be customer|rfq|category|company');
  end if;
  return coalesce(res, jsonb_build_object('error','not found','kind',p_kind,'id',p_id));
end $function$;
revoke execute on function public.fn_twin(text, text) from public, anon, authenticated;
grant execute on function public.fn_twin(text, text) to service_role;

-- ── 3. a repeat request (sql.trg_inquiry_enrich) ────────────────────────────────────────────────────────
create or replace function public.trg_inquiry_enrich()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
declare dup int; v_prev_id uuid; v_prev text;
begin
  if NEW.urgency is null and NEW.spec is not null and (NEW.spec ? 'urgency') then NEW.urgency := NEW.spec->>'urgency'; end if;
  if NEW.plausibility is null and NEW.spec is not null and (NEW.spec ? 'plausibility') then NEW.plausibility := NEW.spec->'plausibility'; end if;
  if NEW.provenance is null and NEW.spec is not null and (NEW.spec ? 'provenance') then NEW.provenance := NEW.spec->'provenance'; end if;

  -- REMEMBERED PREFERENCE. Only fills a GAP — an emirate the customer stated on this RFQ always
  -- wins. `stated` beats `inferred`, and consent is re-checked on the read as well as the write.
  if NEW.emirate is null and NEW.customer_id is not null then
    select coalesce(p.preferences->'stated'->'emirates'->>0,
                    p.preferences->'inferred'->'emirates'->>0)
      into NEW.emirate
      from customer_preference p
      join customers c on c.id = p.customer_id
     -- Consent is read from customers.tos_accepted_at, where it actually lives, not from the copy
     -- on the preference row. A stale copy would keep a withdrawn profile readable.
     where p.customer_id = NEW.customer_id and c.tos_accepted_at is not null;
  end if;

  -- A REPEAT REQUEST (23 Sep 2026, founder_instruction 886-903). The very same summary is the same
  -- request: that is identity, not meaning, and is flagged at once. A DIFFERENTLY WORDED one used to be
  -- judged by whether its first 40 characters appeared inside the other — meaning by substring. Whether
  -- it asks for the same job is now the sales engineer seat's reasoning (inquiry.same_request); the answer
  -- sets the flag later (fn_reason_apply_inquiry__same_request). Under the hold no flag is guessed.
  select count(*) into dup from inquiries i
    where i.customer_id = NEW.customer_id and i.created_at > now() - interval '30 minutes'
      and coalesce(i.category,'') = coalesce(NEW.category,'')
      and i.summary = NEW.summary;
  if dup > 0 then
    NEW.plausibility := coalesce(NEW.plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true);
  elsif NEW.id is not null and btrim(coalesce(NEW.summary, '')) <> '' then
    select i.id, i.summary into v_prev_id, v_prev from inquiries i
     where i.customer_id = NEW.customer_id and i.created_at > now() - interval '30 minutes'
       and coalesce(i.category,'') = coalesce(NEW.category,'')
       and btrim(coalesce(i.summary, '')) <> '' and i.id <> NEW.id
     order by i.created_at desc limit 1;
    if v_prev_id is not null then
      perform public.fn_reason_route_ask('sales_engineer', 'inquiry.same_request',
        'Earlier request: ' || left(v_prev, 3000) || E'\nNew request: ' || left(NEW.summary, 3000),
        jsonb_build_array(
          jsonb_build_object('id', 'same_request', 'meaning', 'the new request asks for the same job as the earlier one, however differently it is worded'),
          jsonb_build_object('id', 'different_request', 'meaning', 'the new request is a different job')),
        jsonb_build_object('inquiry_id', NEW.id, 'earlier_id', v_prev_id), 'inquiry_dup:' || NEW.id);
    end if;
  end if;
  return NEW;
end $function$;
revoke execute on function public.trg_inquiry_enrich() from public, anon, authenticated;
grant execute on function public.trg_inquiry_enrich() to service_role;

-- ── 4. the supplier's documents: the reasoned subject (sql.fn_supplier_document_home; asked in section 8) ───
create or replace function public.fn_supplier_document_home(p_lead_id bigint)
 RETURNS TABLE(key text, path text, name text, expiry date, source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
  with me as (select * from public.leads where id = p_lead_id),
  -- A live supporting document whose LABEL names the subject. The label is the supplier's own
  -- words for the file ("ISO 9001:2015", "شهادة الأيزو", "Public liability insurance"). WHICH subject it
  -- names is the sales engineer seat's reasoning (supplier_documents.subject, filed when the label is
  -- saved by trg_supplier_document_subject_asked), read back by its key — 23 Sep 2026, founder_instruction
  -- 886-903; a pattern list on the label decided it before. Until it is answered the file fills no slot.
  supp as (
    select d.path, d.file_name, d.created_at,
           nullif(public.fn_reason_route_answer('supdoc:' || d.id || ':' || md5(coalesce(d.file_name, ''))), 'none') as subject
    from public.documents d
    where d.ref_table = 'supplier_supporting' and d.ref_id = p_lead_id::text
      and coalesce(d.status, '') <> 'withdrawn'
  ),
  best as (
    select distinct on (subject) subject, path, file_name from supp
    where subject is not null order by subject, created_at desc
  ),
  fixed(key, path, name, expiry) as (
    select 'trade_licence',     (select license_doc_path from me),           (select license_doc_name from me), (select license_expiry from me)::date
    union all select 'company_profile',   (select company_profile_doc_path from me),   null, null::date
    union all select 'insurance',         (select insurance_doc_path from me),         null, (select insurance_expiry from me)::date
    union all select 'iso',               (select iso_doc_path from me),               null, (select iso_expiry from me)::date
    union all select 'manufacturer_auth', (select manufacturer_auth_doc_path from me), null, (select manufacturer_auth_expiry from me)::date
    union all select 'establishment',     (select egr_doc_path from me),               (select egr_doc_name from me), null::date
  )
  select f.key,
         coalesce(f.path, b.path)                                  as path,
         coalesce(f.name, case when f.path is null then b.file_name end, regexp_replace(coalesce(f.path, b.path, ''), '^.*/', '')) as name,
         case when f.path is not null then f.expiry end            as expiry,
         case when f.path is not null then 'leads' when b.path is not null then 'supporting' end as source
  from fixed f left join best b on b.subject = f.key;
$function$;
revoke execute on function public.fn_supplier_document_home(bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_document_home(bigint) to service_role;

-- ── 5. escalation (sql.fn_should_escalate, sql.fn_decide) ───────────────────────────────────────────────
create or replace function public.fn_should_escalate(ctx jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
declare
  reasons text[] := '{}';
  conf_min numeric; fin_review numeric; auto_max numeric; fraud_max numeric;
  legal jsonb; sens jsonb; owner text;
  c_conf numeric := nullif(ctx->>'confidence','')::numeric;
  c_amt  numeric := nullif(ctx->>'amount_aed','')::numeric;
  c_fraud numeric := nullif(ctx->>'fraud_score','')::numeric;
  c_cat  text := lower(coalesce(ctx->>'category',''));
  c_txt  text := lower(coalesce(ctx->>'text',''));
  c_kind text := lower(coalesce(ctx->>'kind',''));
  REPORTING_KINDS constant text[] := array['handoff','incident','report_task'];
  c_money boolean := coalesce((ctx->>'moves_money')::boolean,false);
  trg text;
  c_actor text := nullif(btrim(coalesce(ctx->>'actor', ctx->>'agent_key', '')), '');
  v_route text; v_basis text; v_note text;
  v_mgr text; v_mgr_dept text; v_pick jsonb;
  v_actor_res text;
  v_apex_backup text;   -- D11: the named deputy-apex
  v_key text; v_choice text; v_cands jsonb; v_needs jsonb;   -- the reasoned meaning of ctx.text (23 Sep 2026)
begin
  select value::numeric into conf_min   from decision_policy where key='confidence_min';
  select value::numeric into fin_review  from decision_policy where key='financial_review_aed';
  select value::numeric into auto_max    from decision_policy where key='auto_action_max_aed';
  select value::numeric into fraud_max   from decision_policy where key='fraud_score_max';
  select value into legal                from decision_policy where key='legal_triggers';
  select value into sens                 from decision_policy where key='sensitive_categories';
  select value #>> '{}' into owner       from decision_policy where key='review_owner';

  if c_conf is not null and c_conf < conf_min then
     reasons := array_append(reasons, 'confidence '||round(c_conf,2)::text||' < min '||round(conf_min,2)::text); end if;
  if c_amt is not null and c_amt >= fin_review then
     reasons := array_append(reasons, 'amount AED '||c_amt::text||' >= review threshold '||fin_review::text); end if;
  if c_money and (c_amt is null or c_amt > auto_max) then
     reasons := array_append(reasons, 'action moves money beyond autonomous limit'); end if;
  if c_fraud is not null and c_fraud >= fraud_max then
     reasons := array_append(reasons, 'fraud score '||round(c_fraud,2)::text||' >= max '||round(fraud_max,2)::text); end if;
  if c_cat <> '' and sens ? c_cat and (c_conf is null or c_conf < conf_min) then
     reasons := array_append(reasons, 'sensitive category "'||c_cat||'" with low/absent confidence'); end if;
  -- WHAT THE TEXT MEANS IS REASONED, NEVER SPOTTED (23 Sep 2026, founder_instruction 886-903). This read
  -- the legal_triggers list as substrings of the text and matched earlier failures by shared long words,
  -- so "is a refund dispute legal?" escalated and "the supplier sued us" did not. The question — does the
  -- matter carry a legal exposure, or repeat an attempt that ended worse? — is now filed for the CEO seat's
  -- reasoning (fn_decide files it) and read back here by its key. Until it is answered this routine says
  -- so ('needs_reasoning') and its caller waits; nothing is escalated on a word guess.
  if c_txt <> '' then
    -- One question per (decision kind, actor, text): stable fields only, never a per-call id or timestamp the
    -- caller may add to the context, so asking again never files (and pays for) a second question.
    v_key := 'ceo.escalation:' || md5(coalesce(ctx->>'decide_kind', '') || '|' || coalesce(c_actor, '') || '|' || c_txt);
    v_choice := public.fn_reason_route_answer(v_key);
    if v_choice is null then
      select coalesce(jsonb_agg(jsonb_build_object('id', 'repeats_failure_' || m.id,
               'meaning', 'it repeats this earlier attempt, which ended worse: ' || left(m.headline, 300)) order by m.created_at desc), '[]'::jsonb)
        into v_cands
        from (select * from institutional_memory m
               where m.outcome = 'worse' and coalesce(m.headline,'') <> '' and not (c_kind = any (REPORTING_KINDS))
               order by m.created_at desc limit 5) m;
      v_needs := jsonb_build_object('surface', 'ceo.escalation_meaning', 'dedupe_key', v_key,
        'question', left(ctx->>'text', 4000),
        'options', jsonb_build_array(jsonb_build_object('id', 'legal_matter',
                     'meaning', 'the matter itself carries a legal exposure for the company - for example '
                                || coalesce((select string_agg(x, ', ') from jsonb_array_elements_text(legal) x), 'a dispute or a liability')
                                || ' - however it is worded, in any language; merely mentioning such a word as a topic is not enough'))
                   || v_cands
                   || jsonb_build_array(jsonb_build_object('id', 'neither',
                     'meaning', 'neither a legal exposure nor a repeat of an attempt that ended worse')));
    elsif v_choice = 'legal_matter' then
      reasons := array_append(reasons, 'legal matter (reasoned by the CEO seat)');
    elsif left(v_choice, 16) = 'repeats_failure_' then
      select m.headline into trg from institutional_memory m where m.id::text = substr(v_choice, 17);
      reasons := array_append(reasons, 'a prior attempt on record ended worse (reasoned): "' || left(coalesce(trg, v_choice), 120) || '"');
    end if;
  end if;

  -- THE APEX ESCALATES TO THE FOUNDER. Resolved FIRST: the active agent with no manager_key (the CEO)
  -- reports to the founder, not to another agent.
  if c_actor is not null then
    v_actor_res := coalesce(public.fn_org_agent_resolve(c_actor), c_actor);
    perform 1 from org_agents a where a.agent_key = v_actor_res and a.active and a.manager_key is null;
    if found then
      v_route := 'founder'; v_basis := 'apex_to_founder';
      v_note  := 'the company apex ('||v_actor_res||') has no manager; the only party above it is the '
              || 'founder, whose major-issue channel is the single human signal the design allows';
    end if;
  end if;

  -- RESOLVE THE PARTY. The configured review_owner (employee / staffed department / title).
  if v_route is null and owner is not null and btrim(owner) <> '' then
    select a.agent_key into v_route from org_agents a
     where a.active and a.agent_key = owner limit 1;
    if v_route is not null then v_basis := 'employee'; end if;

    if v_route is null then
      select d.dept_key into v_route from org_departments d
       where d.dept_key = owner
         and exists (select 1 from org_agents a where a.department = d.dept_key and a.active)
       limit 1;
      if v_route is not null then v_basis := 'staffed_department'; end if;
    end if;

    if v_route is null then
      select a.agent_key into v_route from org_agents a
       where a.active and lower(btrim(a.title)) = lower(btrim(owner))   -- the configured title, exactly (23 Sep 2026: was a substring)
       order by a.agent_key limit 1;
      if v_route is not null then v_basis := 'employee_by_title'; end if;
    end if;
  end if;

  -- THE REPORTING LINE. The actor's manager (active AND available), else the standing deputy.
  if v_route is null and c_actor is not null then
    select a.manager_key into v_mgr from org_agents a where a.agent_key = c_actor and a.active;
    if v_mgr is not null and v_mgr <> c_actor then
      select a.agent_key into v_route from org_agents a
       where a.agent_key = v_mgr and a.active and a.available
         and (a.unavailable_until is null or a.unavailable_until < current_date);
      if v_route is not null then v_basis := 'reporting_line'; end if;

      if v_route is null then
        select a.department into v_mgr_dept from org_agents a where a.agent_key = v_mgr;
        begin v_pick := public.fn_pick_reviewer(v_mgr_dept);
        exception when others then v_pick := null; end;
        v_route := public.fn_route_party(v_pick->>'reviewer');
        if v_route = c_actor then v_route := null; end if;
        if v_route is not null then
          v_basis := 'reporting_line_delegated';
          v_note  := 'manager '||v_mgr||' is unavailable; '
                  || coalesce(v_pick->>'basis','delegation_rule standing deputy');
        end if;
      end if;
    end if;
  end if;

  -- D11: THE APEX BACKUP. Before the generic executive fallback, a named deputy-apex (the COO) takes
  -- an escalation that did not resolve up the line, so an apex-level item reaches a designated backup
  -- rather than whichever exec member the fallback names. Configured in decision_policy.apex_backup.
  if v_route is null then
    select value #>> '{}' into v_apex_backup from decision_policy where key='apex_backup';
    if v_apex_backup is not null and btrim(v_apex_backup) <> '' then
      select a.agent_key into v_route from org_agents a
       where a.active and a.agent_key = coalesce(public.fn_org_agent_resolve(v_apex_backup), v_apex_backup)
       limit 1;
      if v_route is not null then
        v_basis := 'apex_backup';
        v_note := 'no manager or configured owner resolved; the designated apex backup ('||v_route
               || ') stands in before the generic executive fallback';
      end if;
    end if;
  end if;

  -- The configured owner names nobody and no apex backup resolved. Escalate to the executive
  -- department's own head, recorded as a fallback so the configuration gap stays visible.
  if v_route is null then
    select coalesce(
             (select d.brain_agent from org_departments d where d.dept_key='exec'
               and exists (select 1 from org_agents a where a.agent_key=d.brain_agent and a.active)),
             (select d.lead_agent  from org_departments d where d.dept_key='exec'
               and exists (select 1 from org_agents a where a.agent_key=d.lead_agent and a.active)),
             (select a.agent_key from org_agents a where a.active and a.department='exec'
               order by a.agent_key limit 1))
      into v_route;
    if v_route is not null then
      v_basis := 'fallback_exec';
      v_note := 'configured review_owner "'||coalesce(owner,'(unset)')||'" names no active employee '
             || 'and no staffed department; escalation addressed to '||v_route||' instead';
    end if;
  end if;

  if v_route is null then
    v_route := owner; v_basis := 'unresolved';
    v_note := 'configured review_owner "'||coalesce(owner,'(unset)')||'" resolves to no party in the '
           || 'org model, and no active executive employee was available to take it';
  end if;

  return jsonb_build_object(
    'escalate', array_length(reasons,1) is not null,
    'reasons', to_jsonb(reasons),
    'route_to', v_route,
    'route_basis', v_basis,
    'route_note', v_note,
    'route_owner_configured', owner,
    'needs_reasoning', v_needs);
end $function$;
revoke execute on function public.fn_should_escalate(jsonb) from public, anon, authenticated;
grant execute on function public.fn_should_escalate(jsonb) to service_role;

create or replace function public.fn_decide(p_kind text, p_ctx jsonb, p_actor text DEFAULT 'agent'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
declare
  res jsonb; conf numeric; reasons jsonb := '[]'::jsonb; route text; decision text;
  sources jsonb := '[]'::jsonb;
  v_alt text; v_alt_why text; v_alt_score numeric;
  v_ctx jsonb := coalesce(p_ctx, '{}'::jsonb);
  v_q text; v_cands text[]; v_hits jsonb := '[]'::jsonb; v_evidence jsonb;
  v_options jsonb; v_amount numeric; v_dept text;
  v_problem text; v_imp_bus text; v_imp_fin text; v_imp_leg text; v_imp_cus text;
  v_escalates boolean; v_status text; v_approver text; v_authorised boolean;
  v_actor_tier text;   -- reputation tier of the acting agent (gap 8)
  v_dr_id bigint; v_dr_status text; v_verdict text; v_gate_reason text;
  v_corr uuid; v_trace uuid; v_prior jsonb;
  v_held bigint;   -- the CEO seat's held question when the text is not yet reasoned (23 Sep 2026)
begin
  begin v_amount := nullif(coalesce(v_ctx->>'amount_aed', v_ctx->>'amount'), '')::numeric;
  exception when others then v_amount := null; end;
  v_dept := nullif(v_ctx->>'dept_key', '');

  -- A MEANING NOT YET REASONED IS NOT DECIDED (23 Sep 2026, founder_instruction 886-903). When the
  -- context carries text, whether it is a legal matter or repeats a failure is the CEO seat's reasoning,
  -- not a word list (fn_should_escalate). Until it is reasoned the question waits, visible, in the CEO
  -- seat's queue (reasoning_held_question) and NOTHING is recorded, routed or escalated — to the founder
  -- least of all. fn_reason_apply_ceo__escalation_meaning re-runs this decision once it is answered.
  if p_kind in ('escalate', 'approve') then
    res := public.fn_should_escalate(v_ctx || jsonb_build_object('actor', p_actor, 'decide_kind', p_kind));
    if jsonb_typeof(res->'needs_reasoning') = 'object' then
      v_held := public.fn_reason_route_ask('ceo', 'ceo.escalation_meaning',
                  'The ' || p_kind || ' decision requested by ' || p_actor || ' concerns: ' || (res->'needs_reasoning'->>'question'),
                  res->'needs_reasoning'->'options',
                  jsonb_build_object('kind', p_kind, 'ctx', v_ctx, 'actor', p_actor),
                  res->'needs_reasoning'->>'dedupe_key');
      return jsonb_build_object('kind', p_kind, 'decision', 'awaiting_reasoning', 'status', 'held', 'held_id', v_held,
                                'route_to', 'ceo', 'reasons', jsonb_build_array('the meaning of the text is being reasoned by the CEO seat; nothing is decided on a word'),
                                'detail', res);
    end if;
  end if;

  if p_kind='escalate' then
    -- p_actor goes IN. Without it the router has no line to send the escalation up and answers
    -- every caller with the same company-wide owner; see fn_should_escalate's reporting-line rung.
    res := public.fn_should_escalate(v_ctx || jsonb_build_object('actor', p_actor, 'decide_kind', p_kind));
    decision := case when (res->>'escalate')::boolean then 'escalate' else 'proceed' end;
    reasons := res->'reasons'; route := res->>'route_to';
    conf := case when (res->>'escalate')::boolean then 0.9 else 0.8 end;
    -- WHY THIS PARTY, NOT JUST WHICH. 'decision_policy' was a label naming a table; the router's
    -- own verdict — route_basis, route_note and the reasons it fired on — is the retrieval this
    -- decision was actually taken on, and it is what makes the routing auditable after the fact.
    sources := to_jsonb(array['decision_policy'])
      || jsonb_build_array(jsonb_build_object('kind','policy_check','ref','fn_should_escalate','result',res));
    v_alt := case when decision='escalate' then 'proceed' else 'escalate' end;
    v_alt_why := 'the opposite verdict from fn_should_escalate on the same context';

  elsif p_kind='price' then
    res := public.fn_price_confidence(coalesce(v_ctx->>'category','default'), nullif(v_ctx->>'amount_aed','')::numeric);
    decision := 'priced'; conf := coalesce((res->>'confidence')::numeric, 0.5);
    reasons := jsonb_build_array(coalesce(res->>'band', 'price band computed')); sources := to_jsonb(array['price_confidence']);
    route := null;   -- a price band hands off to nobody; 'none' was a name that named nobody
    v_alt := 'quote_manually'; v_alt_why := 'refer the price to a human estimator instead of the band';

  elsif p_kind='route_category' then
    route := public.fn_resolve_cat_agent(coalesce(v_ctx->>'category',''));
    decision := coalesce(route,'unmatched'); conf := case when route is null then 0.3 else 0.85 end;
    reasons := jsonb_build_array('mapped category "'||coalesce(v_ctx->>'category','')||'" to agent '||coalesce(route,'(none)'));
    sources := to_jsonb(array['category_agents']);
    v_alt := 'Secretary'; v_alt_why := 'the unrouted-work fallback, which is slower but never drops the item';

  elsif p_kind='invite' then
    -- rank approved suppliers for a category (+ optional emirate)
    with pool as (
      select id, company_name, coalesce(capability_score,0) cap, coalesce(app_rating,rating,0) rat, coalesce(rv_response_rate,0) resp
      from leads
      where coalesce(approval_status,'')='approved'
        -- The supplier's trade as REASONED from its own record (lead_trade_class), exactly (23 Sep 2026). A
        -- substring of the free-text categories column decided it before ('tile' matched 'textile'), and that
        -- column holds company names as often as trades (measured 23 Sep 2026), so it decides nothing now.
        and (coalesce(v_ctx->>'category','')=''
             or exists (select 1 from lead_trade_class c where c.lead_id = leads.id and c.trade_code = lower(btrim(v_ctx->>'category'))))
        and (coalesce(v_ctx->>'emirate','')='' or coalesce(v_ctx->>'emirate')= any(coalesce(service_emirates,array[emirate])))
      order by (coalesce(capability_score,0)*0.5 + coalesce(app_rating,rating,0)*8 + coalesce(rv_response_rate,0)*0.3) desc
      limit coalesce((v_ctx->>'n')::int, 5))
    select jsonb_agg(jsonb_build_object('id',id,'name',company_name,'cap',cap,'rating',rat,'response',resp)) into res from pool;
    decision := 'invite_ranked'; conf := case when res is null then 0.2 when jsonb_array_length(res)>=3 then 0.8 else 0.5 end;
    reasons := jsonb_build_array('ranked by capability_score, rating and response rate');
    sources := to_jsonb(array['leads','supplier_capability','response_rate']);
    res := jsonb_build_object('suppliers', coalesce(res,'[]'));
    v_alt := 'broadcast_to_all_approved';
    v_alt_why := 'invite every approved supplier instead of the ranked shortlist — more coverage, worse response rate';

  elsif p_kind='approve' then
    res := public.fn_should_escalate(v_ctx || jsonb_build_object('actor', p_actor, 'decide_kind', p_kind));
    if (res->>'escalate')::boolean then decision:='human_review'; conf:=0.9; reasons:=res->'reasons';
    else decision:='auto_approve'; conf:=0.85; reasons:=jsonb_build_array('within autonomous thresholds'); end if;
    route := res->>'route_to';
    sources := to_jsonb(array['decision_policy'])
      || jsonb_build_array(jsonb_build_object('kind','policy_check','ref','fn_should_escalate','result',res));
    v_alt := case when decision='human_review' then 'auto_approve' else 'human_review' end;
    v_alt_why := 'the opposite side of the autonomous threshold in decision_policy';

  else
    decision := 'unsupported_kind'; conf := 0; reasons := jsonb_build_array('no handler for kind '||p_kind); route:='Secretary';
    v_alt := 'add_a_handler'; v_alt_why := 'teach fn_decide this kind rather than routing it to a person every time';
  end if;

  -- ROUTE_TO NAMES A PARTY, OR IT NAMES NOBODY AND IS NULL.
  --
  -- MEASURED DEFECT, production, 6 Aug 2026: every routed decision this engine has ever written
  -- names something the org model does not contain. route_category wrote 'cat:signage' (9 rows) —
  -- a knowledge persona in category_agents, not an employee; price wrote the literal string
  -- 'none'; the unsupported-kind branch wrote 'Secretary', which matches no agent_key, no title
  -- and no dept_key across all 67 employees. The requirement is "Should I escalate? routes to a
  -- NAMED PARTY", and a column that is merely non-null answers it with a string.
  --
  -- The ladder resolves whatever the branch above chose, and it invents nobody: each rung returns
  -- a party the org model already contains, and if none does, the value is whatever
  -- fn_should_escalate itself answers — so a configuration gap stays visible as an unresolvable
  -- route rather than being papered over here.
  --   1. the name is already an active employee or a staffed department -> keep it
  --   2. 'cat:x' is a knowledge persona; the party is 'x' if 'x' is one  -> cat:it -> it
  --   3. the deciding actor's own department, if staffed — the work stays where it arose
  --   4. the escalation resolver's answer, which is the same one every other kind gets
  -- A decision that hands off to nobody carries NULL, which is what `invite` already did. The
  -- category agent itself is not lost: it is already the value of `decision` and is quoted in
  -- `reasons`, which is where "which persona holds this knowledge" belongs.
  route := nullif(btrim(coalesce(route, '')), '');
  if route in ('none', 'unmatched') then route := null; end if;
  if route is not null then
    route := coalesce(
      public.fn_route_party(route),
      public.fn_route_party(regexp_replace(route, '^cat:', '')),
      public.fn_route_party((select a.department from public.org_agents a
                              where a.agent_key = p_actor and a.active limit 1)),
      public.fn_should_escalate(jsonb_build_object('actor', p_actor)) ->> 'route_to');
  end if;

  -- STEP 3, KNOWLEDGE RETRIEVAL. fn_memory_search had zero callers, which is the whole defect:
  -- the engine decided without consulting anything the company already knew.
  --
  -- NARROW FIRST, THEN WIDER. fn_memory_search builds its query with plainto_tsquery, which ANDs
  -- every lexeme, so handing it a whole sentence retrieves NOTHING: 'Which agent owns Printing /
  -- Packaging / Signage work when an RFQ arrives' returned 0 hits on production while 'signage'
  -- returned 5. The candidates are therefore tried shortest-first and the first one that retrieves
  -- wins. A failed search must not lose the decision, so it degrades to "searched, no hits".
  v_cands := array_remove(array[
      nullif(btrim(coalesce(v_ctx->>'category','')), ''),
      nullif(array_to_string((regexp_split_to_array(
        btrim(coalesce(v_ctx->>'question', v_ctx->>'problem','')), '\s+'))[1:4], ' '), ''),
      nullif(btrim(coalesce(v_ctx->>'question', v_ctx->>'problem','')), ''),
      p_kind], null);

  foreach v_q in array v_cands loop
    begin
      select coalesce(jsonb_agg(jsonb_build_object(
               'kind', m.kind, 'ref', m.ref, 'snippet', left(m.snippet, 180),
               'score', round(m.score::numeric, 4))), '[]'::jsonb)
        into v_hits
        from public.fn_memory_search(v_q, null::text[], 5) m;
    exception when others then v_hits := '[]'::jsonb; end;
    exit when jsonb_array_length(v_hits) > 0;
  end loop;

  sources := sources || jsonb_build_array(jsonb_build_object(
               'kind', 'memory_search', 'q', v_q, 'hits', jsonb_array_length(v_hits))) || v_hits;

  -- HOW THE LAST DECISIONS OF THIS KIND TURNED OUT. decision_trace.outcome_status was written by
  -- fn_execution_sweep and read by nobody; it is retrieved here, recorded as a source, and it
  -- BITES: a kind whose executions have failed more often than they succeeded loses the confidence
  -- it needs to be taken autonomously and escalates instead. That is the difference between a
  -- measured outcome and a stored one.
  -- Read inline (23 Sep 2026): retire_the_routines_no_seat_can_reach.sql dropped fn_decision_outcomes on
  -- 8 Sep 2026 while this call to it survived, so every fn_decide raised 42883 here (measured 23 Sep 2026
  -- in the batch probe). The same count, 'cancelled' reported and not a failure, as that routine made it.
  select jsonb_build_object('decision_type', p_kind, 'window_days', 90, 'traced', count(*),
           'graded', count(*) filter (where t.outcome_status is not null),
           'succeeded', count(*) filter (where t.outcome_status = 'succeeded'),
           'failed', count(*) filter (where t.outcome_status in ('failed','stalled')),
           'cancelled', count(*) filter (where t.outcome_status = 'cancelled'),
           'last_evaluated_at', max(t.evaluated_at))
    into v_prior
    from public.decision_trace t
   where t.decision_type = p_kind and t.created_at > now() - interval '90 days';
  sources := sources || jsonb_build_array(jsonb_build_object(
               'kind', 'prior_outcomes', 'ref', 'decision_trace', 'result', v_prior));
  if coalesce((v_prior->>'graded')::int, 0) >= 3
     and coalesce((v_prior->>'failed')::int, 0) > coalesce((v_prior->>'succeeded')::int, 0) then
    conf := least(conf, 0.65);
    reasons := coalesce(reasons,'[]'::jsonb) || jsonb_build_array(format(
      'the last %s graded %s decisions went %s failed against %s succeeded, so this one is not taken autonomously',
      v_prior->>'graded', p_kind, v_prior->>'failed', v_prior->>'succeeded'));
  end if;

  v_evidence := sources;

  -- STEP 6. Two scored alternatives, always. One "option" is a conclusion, not a choice.
  v_options := jsonb_build_array(
    jsonb_build_object('option', decision, 'score', conf, 'selected', true, 'rationale', reasons),
    jsonb_build_object('option', coalesce(v_alt,'no_action'),
                       'score', coalesce(v_alt_score, round(1 - conf, 2)), 'selected', false,
                       'rationale', jsonb_build_array(coalesce(v_alt_why, 'the alternative the engine scored lower'))));

  -- STEP 1 and STEP 4. The problem in words, and the four impacts derived from what was computed.
  v_problem := format('Decision requested (%s) by %s: %s', p_kind, p_actor,
                 left(coalesce(nullif(btrim(concat_ws(' ', nullif(v_ctx->>'question',''), nullif(v_ctx->>'problem',''))), ''),
                               v_ctx::text), 400));
  v_imp_bus := format('Business: the engine selected "%s" over "%s" for %s. %s',
                 decision, coalesce(v_alt,'no_action'), p_actor, coalesce(v_alt_why,''));
  v_imp_fin := case when coalesce(v_amount,0) > 0
                 then format('Financial: AED %s is committed by this decision and is checked against %s spend authority before the gate lets it through.',
                             v_amount, coalesce(v_dept,'company'))
                 else format('Financial: no money moves. A %s decision consumes no spend authority and financial_aed stays null.', p_kind) end;
  v_imp_leg := case when p_kind in ('price','approve','invite')
                 then format('Legal: %s decisions are visible to a counterparty, so the record is retained for audit and PDPL subject access.', p_kind)
                 else format('Legal: internal routing only; a %s decision creates no counterparty obligation.', p_kind) end;
  v_imp_cus := case when coalesce(route,'none') in ('none','')
                 then format('Customer: no customer-facing step changes; the %s decision stays inside the operating system.', p_kind)
                 else format('Customer: the work moves to %s, which sets who answers the customer next and how quickly.', route) end;

  -- STEP 7. Whether this is the engine's to take. Escalating decisions stay 'proposed' and never
  -- reach the gate; autonomous ones are written as 'approved' so trg_decision_gate must inspect
  -- them, and it is free to refuse — 'blocked_by_gate' coming back out is a working gate, not a bug.
  --
  -- THE ACTOR MUST HAVE AUTHORITY ON FILE. This is now belt AND braces: fn_decision_gate consults
  -- the register itself for every writer (scripts/sql/fn_decision_gate_authority_register.sql), and
  -- the engine declines to even propose an autonomous decision for an actor it cannot find there —
  -- an escalation is a better answer than a refusal for something the engine could see coming.
  -- 'founder' is the one identity the gate treats as top authority without an employee_authority
  -- row, so it resolves here too; every other actor must be on the list.
  v_authorised := p_actor = 'founder'
                  or exists (select 1 from public.employee_authority ea where ea.agent_key = p_actor);
  if not v_authorised then
    reasons := coalesce(reasons,'[]'::jsonb) || jsonb_build_array(
      format('%s has no employee_authority record, so this decision is escalated rather than taken autonomously', p_actor));
  end if;

  -- Reputation is load-bearing beyond spend: an agent on probation does not take a decision
  -- autonomously, whatever its kind. This is the demotion signal the spend check already reads.
  select r.tier into v_actor_tier from public.agent_reputation r where r.agent_key = p_actor;
  if v_actor_tier = 'probation' then
    reasons := coalesce(reasons,'[]'::jsonb) || jsonb_build_array(
      format('%s is on probation in the reputation system, so this decision is escalated to a person rather than taken autonomously', p_actor));
  end if;

  v_escalates := decision in ('escalate','human_review','unsupported_kind')
                 or conf < 0.7
                 or jsonb_array_length(v_evidence) = 0
                 or not v_authorised
                 or v_actor_tier = 'probation';
  v_status   := case when v_escalates then 'proposed' else 'approved' end;
  v_approver := case when v_escalates then null else p_actor end;

  insert into public.decision_record(
      decided_by, dept_key, problem, context, options, risks, benefits, recommendation,
      confidence, expected_outcome, rollback_plan, approved_by, status,
      impact_business, impact_financial, financial_aed, impact_legal, impact_customer,
      evidence, reversible)
  values (
      p_actor, v_dept, v_problem, left(v_ctx::text, 2000), v_options,
      format('Risk: if "%s" is the wrong call, %s. Scored %s against %s for the alternative.',
             decision, coalesce(v_alt_why,'the rejected alternative was the better one'),
             conf, coalesce(v_alt_score, round(1 - conf, 2))),
      format('Benefit: the %s step is taken now instead of waiting for a person, on %s retrieved reference(s).',
             p_kind, jsonb_array_length(v_hits)),
      -- recommendation is the ONE decision_record field fn_agent_context actually emits to an
      -- employee ('# DECISIONS ALREADY ON RECORD FOR YOUR DEPARTMENT', left(...,150)). The step-3
      -- retrieval was landing on evidence, which travels nowhere, so the count of references the
      -- engine consulted is carried here instead of being computed and thrown away.
      format('%s (confidence %s, route %s, %s reference(s) retrieved)',
             decision, conf, coalesce(route,'none'), jsonb_array_length(v_hits)),
      conf,
      format('Expected: %s is carried out and the outcome recorded against decision_record.', decision),
      case when v_escalates then 'Rollback: nothing executed; the decision sits at proposed and is routed to the accountable department''s lead through the org_task lane (fn_decision_record_route). Only a Stripe refund reaches the founder.'
           else format('Rollback: set status back to proposed and re-run fn_decide(%L, ...) with corrected context.', p_kind) end,
      v_approver, v_status,
      v_imp_bus, v_imp_fin, v_amount, v_imp_leg, v_imp_cus,
      v_evidence, coalesce(v_amount,0) = 0)
  returning id, status, gate_verdict, gate_reason
       into v_dr_id, v_dr_status, v_verdict, v_gate_reason;

  insert into public.decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to)
  values (p_actor,p_kind,v_ctx,decision,conf,reasons,sources,route);

  -- STEP 9. Execution linked BACK to the decision. One correlation_id ties the trace to the
  -- action, and the action carries the decision_record id it came from, so
  -- v_executions_without_decision_trace stays empty for anything this engine produced.
  -- The row is written 'queued' and public.fn_execution_run (cron execution_run_hourly) performs
  -- it: it delivers the decision to the actor the decision named and settles the row against the
  -- artefact it created. Claiming 'succeeded' here would be claiming an outcome before the act.
  if v_verdict = 'passed' then
    begin v_corr := nullif(current_setting('app.correlation_id', true), '')::uuid;
    exception when others then v_corr := null; end;
    v_corr := coalesce(v_corr, gen_random_uuid());

    insert into public.decision_trace(
        correlation_id, entity_type, entity_id, decision_type, proposed_by, decided_by,
        policy_keys, knowledge_refs, evidence_refs, alternatives, assumptions, risk,
        confidence, authority_result, decision)
    values (v_corr, 'decision_record', v_dr_id::text, p_kind, p_actor, coalesce(v_approver, p_actor),
        array['decision_policy'], v_hits, v_evidence, v_options,
        jsonb_build_array(format('context supplied by %s is current', p_actor)),
        jsonb_build_object('escalated', v_escalates, 'route_to', route, 'financial_aed', v_amount),
        conf,
        jsonb_build_object('gate_verdict', v_verdict, 'approved_by', v_approver, 'status', v_dr_status),
        jsonb_build_object('kind', p_kind, 'decision', decision, 'decision_record_id', v_dr_id,
                           'confidence', conf))
    returning id into v_trace;

    insert into public.action_execution(
        correlation_id, action_class, executor, idempotency_key, risk_tier, reversible, request, status)
    values (v_corr, 'decision.'||p_kind, p_actor, 'decision_record:'||v_dr_id::text,
        case when coalesce(v_amount,0) >= 1000 then 'high'
             when coalesce(v_amount,0) > 0 then 'medium' else 'low' end,
        coalesce(v_amount,0) = 0,
        jsonb_build_object('decision_record_id', v_dr_id, 'decision_trace_id', v_trace,
                           'kind', p_kind, 'decision', decision, 'route_to', route, 'ctx', v_ctx),
        'queued');
  end if;


  -- A PROPOSED DECISION HAS AN OWNER WHO IS NOT THE FOUNDER (5 Sep 2026). An escalating decision used
  -- to sit at 'proposed' with nobody routed to it and the OS showed it to the founder as his. It is now
  -- handed to the accountable department through the org_task lane in the same transaction. The routing
  -- must never lose the decision it routes, so a failure is a warning on the record, not an abort.
  if v_escalates and v_dr_id is not null then
    begin
      perform public.fn_decision_record_route(v_dr_id);
    exception when others then
      -- recorded where it can be read (a warning prints nowhere through the management API)
      insert into public.error_events(source, kind, severity, detail) values ('fn_decide', 'decision_record_route', 'medium', jsonb_build_object('decision_record_id', v_dr_id, 'error', sqlerrm));
    end;
  end if;

  -- BOARD BEFORE A MAJOR DECISION (spec #3 s24). Every active advisor gives an independent opinion
  -- on the problem this decision answers, keyed to the decision_record by id -- so the link is a
  -- foreign key and not the text match the scorer had to fall back on when subject_ref was null on
  -- all 28 rows. fn_challenge underneath is pure SQL, so this costs no model call.
  -- Guarded twice: only when a record was actually written, and an advisor that throws must not
  -- lose the decision it was advising on. The failure is raised as a warning rather than swallowed.
  if v_dr_id is not null then
    begin
      perform public.fn_board_review(
        coalesce((select d.problem from public.decision_record d where d.id = v_dr_id), p_kind),
        v_dr_id::text);
    exception when others then
      insert into public.error_events(source, kind, severity, detail) values ('fn_decide', 'board_review', 'medium', jsonb_build_object('decision_record_id', v_dr_id, 'error', sqlerrm));
    end;
  end if;

  return jsonb_build_object('kind',p_kind,'decision',decision,'confidence',conf,'reasons',reasons,
                            'route_to',route,'sources',sources,'detail',res,
                            'decision_record_id',v_dr_id,'status',v_dr_status,
                            'gate_verdict',v_verdict,'gate_reason',v_gate_reason,
                            'options',v_options,'knowledge_hits',jsonb_array_length(v_hits),
                            'prior_outcomes',v_prior);
end $function$;
revoke execute on function public.fn_decide(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_decide(text, jsonb, text) to service_role;

-- ── 6. the refund exclusion (sql.fn_ceo_refund_checklist) and the review that waits for it ──────────────
create or replace function public.fn_ceo_refund_checklist(p_transaction_id uuid, p_phase text, p_record boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; r public.refunds; rs public.refunds; ap public.ceo_approval; du public.supplier_dues;
  e_chase public.refund_ladder_evidence; e_final public.refund_ladder_evidence;
  v_items jsonb := '[]'::jsonb; v_failed jsonb; v_ok boolean; v_cust text; v_total numeric; v_reason text; v_unresp boolean;
  v_complaint timestamptz; v_in_time boolean; v_cc boolean; v_attached boolean; v_proofs int; v_live boolean; v_proof_ev jsonb;
  v_prior boolean; v_hired boolean; v_rated boolean; v_offp boolean; v_excl text[] := '{}'; v_exp bigint;
  v_succ int; v_succ_fils bigint; v_extra int; v_actual numeric; v_approved numeric; v_loss numeric; v_charge jsonb; v_sent boolean;
  v_told boolean; v_sup_told boolean; v_kind text; v_rid bigint;
  v_offp_text text; v_offp_key text; v_offp_choice text; v_offp_held bigint;   -- item 5, reasoned (23 Sep 2026)
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'phase', p_phase, 'transaction_id', p_transaction_id,
      'failed', jsonb_build_array(jsonb_build_object('item', 'transaction_exists', 'passed', false, 'reason', 'no such transaction', 'remediable', false)));
  end if;
  select * into r from public.refunds where transaction_id = t.id and status not in ('rejected', 'cancelled', 'failed')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by id desc limit 1;
  select lower(email) into v_cust from public.customers where id = t.customer_id;
  v_total := coalesce(t.total_charged, t.reveal_fee);
  v_reason := coalesce(r.reason_code, t.refund_reason, 'supplier_unresponsive');
  v_unresp := v_reason = 'supplier_unresponsive';
  select * into e_chase from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'chase' order by e.id desc limit 1;
  select * into e_final from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'final_call' order by e.id desc limit 1;

  if p_phase = 'approve' then
    v_rid := r.id;
    -- 1. THE CUSTOMER'S COMPLAINT, ON RECORD OR NOT -- NEVER A CONDITION (14 Sep 2026). This item was
    -- complaint_within_7_days_with_proof and refused every refund where the customer did not complain
    -- within 7 days with proof. Terms v7 §5 and Refund Policy v1.5 §3/§5 say the opposite: "you do not
    -- need to do anything for the clock to start", a complaint may come "at any time", and proof "is
    -- never a condition of the refund". So it now records the evidence and always passes; the conditions
    -- the terms DO set are items 2 to 6.
    v_complaint := least(t.customer_notified_at,
                         (select min(x.requested_at) from public.refunds x where x.transaction_id = t.id and lower(coalesce(x.requested_by, '')) = 'customer'));
    v_cc := exists (select 1 from public.inbound_messages im
                     where v_cust is not null and lower(im.from_email) = v_cust and im.created_at > t.revealed_at
                       and (im.to_email ilike 'supplier@%' or im.raw::text ilike '%supplier@mail.quotesdone.com%'));
    v_attached := exists (select 1 from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'customer_proof');
    v_items := v_items || jsonb_build_object('item', 'customer_complaint_on_record',
      'passed', true,
      'evidence', jsonb_build_object('revealed_at', t.revealed_at, 'complaint_at', v_complaint,
        'customer_emailed_supplier_with_supplier_at_in_copy', v_cc, 'formal_notice_through_portal_at', t.customer_notified_at,
        'proof_attached_by_sales_engineer', v_attached,
        'basis', 'Terms v7 section 5, Refund Policy v1.5 sections 3 and 5: no complaint or proof is required; the ladder runs from payment'),
      'reason', null, 'remedy', 'none needed', 'owner', 'sales_engineer', 'remedy_key', 'customer_proof', 'remediable', true, 'kind', 'information');

    -- 2 and 3. The day-3 chase and the day-5 final call, as support reported them.
    v_items := v_items || jsonb_build_object('item', 'day3_chase_happened',
      'passed', e_chase.id is not null and e_chase.delivered,
      'evidence', case when e_chase.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_chase.id, 'result', e_chase.result, 'delivered', e_chase.delivered, 'delivery', e_chase.evidence) end,
      'reason', case when e_chase.id is null then 'support has returned no result for a day-3 chase' else 'the day-3 chase was not delivered' end,
      'remedy', 'the sales engineer has support deliver the chase again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'chase', 'remediable', true, 'kind', 'process');
    v_items := v_items || jsonb_build_object('item', 'day5_final_call_happened',
      'passed', e_final.id is not null and e_final.delivered,
      'evidence', case when e_final.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_final.id, 'result', e_final.result, 'delivered', e_final.delivered, 'delivery', e_final.evidence) end,
      'reason', case when e_final.id is null then 'support has returned no result for the day-5 final call' else 'the day-5 final call was not delivered' end,
      'remedy', 'the sales engineer has support deliver the final call again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', true, 'kind', 'process');

    -- 4. The supplier did not respond to either party, on any channel.
    select count(*), (array_agg(e.evidence order by e.id desc))[1] into v_proofs, v_proof_ev
      from public.refund_ladder_evidence e where e.transaction_id = t.id and e.result = 'proof_of_response';
    v_live := coalesce((public.fn_refund_state(t.id)->>'supplier_responded')::boolean, false)
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and w.first_response_at is not null);
    v_items := v_items || jsonb_build_object('item', 'supplier_never_responded',
      'passed', v_proofs = 0 and not v_live
                and coalesce(e_chase.result, '') = 'no_response_confirmation' and coalesce(e_chase.delivered, false)
                and coalesce(e_final.result, '') = 'no_response_confirmation' and coalesce(e_final.delivered, false),
      'evidence', jsonb_build_object('proofs_of_response', v_proofs, 'latest_proof', v_proof_ev, 'responded_by_live_record', v_live,
                                     'chase_result', e_chase.result, 'final_call_result', e_final.result),
      'reason', case when v_proofs > 0 or v_live then 'the supplier responded' || coalesce(': ' || (v_proof_ev->'reply')::text, '')
                     else 'silence is not confirmed on both steps: a result is missing, or the delivery behind it failed' end,
      'remedy', 'the sales engineer has support make the final call again and return proof or a confirmed no-response',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', v_proofs = 0 and not v_live, 'kind', 'process');

    -- 5. None of the exclusions in the signed terms applies.
    v_prior := exists (select 1 from public.transactions x where x.customer_id = t.customer_id and x.supplier_id = t.supplier_id
                         and x.id <> t.id and x.revealed_at < t.revealed_at);
    v_hired := exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id);
    v_rated := exists (select 1 from public.reviews v where v.transaction_id = t.id);
    -- OFF-PLATFORM ENGAGEMENT IS REASONED FROM WHAT WAS WRITTEN, NEVER SPOTTED (23 Sep 2026,
    -- founder_instruction 886-903). A pattern on the note decided this exclusion, and an exclusion DECLINES
    -- the refund: "they did not use the platform" matched nothing, "not off-platform" matched. The notes are
    -- now read by the CEO seat's reasoning (ceo.refund_off_platform) and the answer is read back by its key.
    -- The platform's own default note is our text, not the customer's, so it asks nothing. Until the
    -- reasoning answers, v_offp stays null: no exclusion is assumed, and item 7 below keeps the refund
    -- waiting (fn_ceo_refund_review neither approves nor declines it, and pages nobody).
    v_offp_text := nullif(concat_ws(E'\n',
        case when btrim(coalesce(r.reason_note, '')) not in ('', 'The customer reported that the revealed supplier has not responded.')
             then 'Refund note: ' || btrim(r.reason_note) end,
        (select string_agg('Support note on the supplier''s response: ' || btrim(w.close_reason), E'\n' order by w.id)
           from public.supplier_response_watch w where w.transaction_id = t.id and btrim(coalesce(w.close_reason, '')) <> '')), '');
    if v_offp_text is null then
      v_offp := false;
    else
      v_offp_key := 'refund_offp:' || t.id || ':' || md5(v_offp_text);
      v_offp_choice := public.fn_reason_route_answer(v_offp_key);
      if v_offp_choice is null then
        v_offp := null;
        v_offp_held := public.fn_reason_route_ask('ceo', 'ceo.refund_off_platform', v_offp_text,
          jsonb_build_array(
            jsonb_build_object('id', 'engaged_off_platform', 'meaning', 'the note records that the customer dealt with or hired the supplier outside QuotesDone'),
            jsonb_build_object('id', 'not_off_platform', 'meaning', 'the note does not record any dealing with the supplier outside QuotesDone')),
          jsonb_build_object('transaction_id', t.id, 'refund_id', r.id), v_offp_key);
      else
        v_offp := v_offp_choice = 'engaged_off_platform';
      end if;
    end if;
    if not v_unresp then v_excl := v_excl || ('the reason is ' || v_reason || ', not supplier non-response (price dissatisfaction and a change of mind are not refundable)'); end if;
    if v_prior then v_excl := v_excl || 'the customer revealed this same supplier before'::text; end if;
    if v_hired then v_excl := v_excl || 'the customer completed the job with this supplier'::text; end if;
    if v_rated then v_excl := v_excl || 'the customer already rated this supplier'::text; end if;
    if coalesce(v_offp, false) then v_excl := v_excl || 'the customer engaged the supplier off the platform (reasoned by the CEO seat)'::text; end if;
    v_items := v_items || jsonb_build_object('item', 'no_refund_exclusion_applies',
      'passed', cardinality(v_excl) = 0,
      'evidence', jsonb_build_object('reason_code', v_reason, 'same_supplier_revealed_before', v_prior, 'job_completed_with_supplier', v_hired,
                                     'supplier_rated', v_rated, 'off_platform_engagement_recorded', v_offp,
                                     'supplier_responded', 'checked by supplier_never_responded'),
      'reason', array_to_string(v_excl, '; '), 'remedy', 'none: an exclusion in the signed terms means the refund is declined',
      'owner', 'sales_engineer', 'remedy_key', 'decline', 'remediable', false, 'kind', 'process');
    -- 7. The notes on record have been READ (reasoned), so item 5 is a finding and not an assumption.
    if v_offp is null then
      v_items := v_items || jsonb_build_object('item', 'off_platform_engagement_reasoned',
        'passed', false,
        'evidence', jsonb_build_object('held_question_id', v_offp_held, 'dedupe_key', v_offp_key),
        'reason', 'the CEO seat is still reasoning whether the notes on record say the customer dealt with the supplier off the platform',
        'remedy', 'none by hand: the answer arrives through the reasoning queue and the review re-runs itself',
        'owner', 'ceo', 'remedy_key', 'reasoning', 'remediable', true, 'kind', 'needs_reasoning');
    end if;

    -- 6. The amount is exactly what the customer paid.
    v_exp := round(coalesce(v_total, 0) * 100)::bigint;
    v_items := v_items || jsonb_build_object('item', 'amount_equals_total_charged',
      'passed', r.id is not null and r.amount_fils = v_exp and v_exp > 0,
      'evidence', jsonb_build_object('refund_id', r.id, 'refund_fils', r.amount_fils, 'total_charged_fils', v_exp,
                                     'total_charged_recorded', t.total_charged is not null, 'stripe_reference', t.payment_ref),
      'reason', case when r.id is null then 'there is no open refund request on this payment' else 'the refund amount is not what the customer paid' end,
      'remedy', 'the accountant sets the refund to the payment''s total_charged',
      'owner', 'accountant', 'remedy_key', 'amount', 'remediable', r.id is not null, 'kind', 'money');

  elsif p_phase = 'verify' then
    select count(*), coalesce(sum(x.amount_fils), 0) into v_succ, v_succ_fils
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
    -- A top-up the playbook issued is not a duplicate: its Stripe id is on the incident fix.
    select count(*) into v_extra
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
       and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                        and a.evidence->>'stripe_refund_id' = x.stripe_refund_id);
    -- The platform refund the CEO approved, whatever state it reached. An external row Stripe reported
    -- (a top-up, a dashboard refund) is never it.
    select * into rs from public.refunds x where x.transaction_id = t.id
       and lower(coalesce(x.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by x.id desc limit 1;
    v_rid := rs.id;
    select * into ap from public.ceo_approval a where a.decision_id = rs.refund_decision_id;
    v_actual := case when v_succ > 0 then round(v_succ_fils / 100.0, 2)
                     when t.refund_status in ('refunded', 'succeeded') then t.refund_amount_aed end;
    v_approved := coalesce(ap.amount_aed, v_total);
    v_loss := coalesce((select sum(l.debit) from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
                         where g.source = 'refund_over_loss' and g.source_ref like t.id::text || ':%' and l.account_code = '6900'), 0);

    v_items := v_items || jsonb_build_object('item', 'ceo_approved_this_refund',
      'passed', ap.decision_id is not null and ap.decision = 'approved' and ap.subject_id = v_rid::text and ap.superseded_by is null,
      'evidence', jsonb_build_object('decision_id', ap.decision_id, 'decision', ap.decision, 'subject_id', ap.subject_id, 'refund_id', v_rid),
      'reason', 'money moved without a CEO approval naming this refund', 'kind', 'moved_without_ceo_approval', 'remediable', false);

    v_items := v_items || jsonb_build_object('item', 'stripe_refund_succeeded',
      'passed', (v_succ > 0 and exists (select 1 from public.refunds x
                                         where (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
                                           and x.status = 'succeeded' and x.stripe_refund_id is not null))
                or (v_succ = 0 and t.refund_stripe_id is not null and t.refund_status in ('refunded', 'succeeded')),
      'evidence', jsonb_build_object('refund_status', rs.status, 'stripe_refund_id', coalesce(rs.stripe_refund_id, t.refund_stripe_id), 'failure_reason', rs.failure_reason),
      'reason', 'Stripe has not settled the refund (' || coalesce(rs.status, t.refund_status, 'unknown') || ')', 'kind', 'stripe_failed_or_pending', 'remediable', true);

    v_kind := case when coalesce(v_actual, 0) = 0 then 'stripe_failed_or_pending'
                   when v_approved is distinct from v_total then 'approved_amount_is_not_total_charged'
                   when v_actual < v_approved then 'under_refund'
                   when v_actual > v_approved then 'over_refund' end;
    v_items := v_items || jsonb_build_object('item', 'money_moved_as_approved',
      'passed', v_actual is not null and v_approved = v_total
                and (v_actual = v_approved or (v_actual > v_approved and v_loss >= v_actual - v_approved)),
      'evidence', jsonb_build_object('approved_aed', v_approved, 'actual_aed', v_actual, 'total_charged_aed', v_total,
                                     'difference_aed', v_actual - v_approved, 'over_refund_loss_booked_aed', v_loss, 'settled_refunds', v_succ),
      'reason', 'approved AED ' || coalesce(v_approved::text, '?') || ', refunded AED ' || coalesce(v_actual::text, 'nothing') || ', total charged AED ' || coalesce(v_total::text, '?'),
      'kind', v_kind, 'remediable', true);

    v_items := v_items || jsonb_build_object('item', 'no_duplicate_refund',
      'passed', v_extra <= 1 or v_loss >= coalesce(v_actual - v_approved, 0),
      'evidence', jsonb_build_object('settled_refunds_not_issued_by_a_fix', v_extra),
      'reason', v_extra || ' refunds settled on one payment', 'kind', 'duplicate_refund', 'remediable', true);

    -- What follows the money (the supplier's charge, the two messages) is checked only once money
    -- actually moved; a refund Stripe has not settled is the retry's business, not a missed message.
    if coalesce(v_actual, 0) > 0 and v_unresp then
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      v_charge := public.fn_accountant_nonresponse_charge(t.id, null);
      v_sent := du.id is not null and exists (
        select 1 from public.agent_actions a join public.notifications n on n.id = (a.evidence->>'notification_id')::bigint
         where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || du.id
           and (n.status = 'sent' or n.sent_at is not null));
      v_items := v_items || jsonb_build_object('item', 'supplier_charge_raised_correctly',
        'passed', du.id is not null and coalesce((v_charge->>'ok')::boolean, false)
                  and du.amount_due = (v_charge->>'refunded_aed')::numeric and du.admin_fee = (v_charge->>'admin_fee_aed')::numeric
                  and du.due_date = (v_charge->>'due_date')::date,
        'evidence', jsonb_build_object('due_id', du.id, 'charged', jsonb_build_object('amount_due', du.amount_due, 'admin_fee', du.admin_fee, 'due_date', du.due_date),
                                       'expected', v_charge, 'charge_message_sent', v_sent),
        'reason', case when du.id is null then 'no supplier charge was raised' else 'the supplier charge does not match the refund record' end,
        'kind', case when du.id is null then 'charge_missing' when v_sent then 'wrong_charge_sent' else 'wrong_charge_unsent' end, 'remediable', true);
    end if;

    if coalesce(v_actual, 0) > 0 then
    v_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                        and a.target_id = 'refund.paid:' || t.id and a.status = 'done')
              and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                            and a.target_id = 'delivery.request:refund_issued:' || t.id and a.status = 'done'
                            and coalesce((a.evidence->>'delivered')::boolean, false));
    v_items := v_items || jsonb_build_object('item', 'customer_told',
      'passed', v_told, 'evidence', jsonb_build_object('handoff', 'refund.paid:' || t.id, 'delivery', 'delivery.request:refund_issued:' || t.id),
      'reason', 'the customer''s refund message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    if v_unresp and du.id is not null then
      v_sup_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                              and a.target_id in ('nonresponse.charge_raised:' || du.id, 'charge.corrected:' || du.id) and a.status = 'done')
                    and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                                  and a.target_id in ('delivery.request:nonresponse_charge:' || du.id, 'delivery.request:charge_corrected:' || du.id)
                                  and a.status = 'done' and coalesce((a.evidence->>'delivered')::boolean, false));
      v_items := v_items || jsonb_build_object('item', 'supplier_told',
        'passed', v_sup_told, 'evidence', jsonb_build_object('handoff', 'nonresponse.charge_raised:' || du.id),
        'reason', 'the supplier''s charge message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    end if;
    end if;
  else
    raise exception 'phase is approve or verify, not %', p_phase;
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_failed from jsonb_array_elements(v_items) i where not coalesce((i->>'passed')::boolean, false);
  v_ok := jsonb_array_length(v_failed) = 0;
  if p_record then
    insert into public.refund_ceo_check (transaction_id, refund_id, phase, item, passed, reason, evidence)
    select t.id, v_rid, p_phase, i->>'item', coalesce((i->>'passed')::boolean, false),
           case when coalesce((i->>'passed')::boolean, false) then null else i->>'reason' end, coalesce(i->'evidence', '{}'::jsonb)
      from jsonb_array_elements(v_items) i;
  end if;
  return jsonb_build_object('ok', v_ok, 'phase', p_phase, 'transaction_id', t.id, 'refund_id', v_rid, 'items', v_items, 'failed', v_failed);
end $function$;
revoke execute on function public.fn_ceo_refund_checklist(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_ceo_refund_checklist(uuid, text, boolean) to service_role;

create or replace function public.fn_ceo_refund_review(p_refund_id bigint, p_trigger text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
declare
  r public.refunds; v jsonb; v_cycle int; v_nonrem jsonb; v_rev bigint; v_dec bigint; x record; v_task bigint;
  v_tasks jsonb := '[]'::jsonb; v_rat text; v_deadline timestamptz; v_chase int; v_adv jsonb;
  v_wait boolean := false;   -- a check still being reasoned (23 Sep 2026)
begin
  select * into r from public.refunds where id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'reason', 'refund is ' || r.status || '; the CEO reviews only an open request'); end if;
  if r.refund_decision_id is not null then return jsonb_build_object('ok', true, 'outcome', 'already_approved', 'decision_id', r.refund_decision_id); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.remediate'
               and a.detail->>'refund_id' = r.id::text and a.status = 'pending') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_remediation');
  end if;

  select coalesce(max(cycle), 0) + 1 into v_cycle from public.refund_ceo_review where refund_id = r.id;
  v := public.fn_ceo_refund_checklist(r.transaction_id, 'approve', true);

  if (v->>'ok')::boolean then
    v_rat := 'Cycle ' || v_cycle || ': every pre-approval check passed ('
          || (select string_agg(i->>'item', ', ') from jsonb_array_elements(v->'items') i) || '). Evidence: refund_ceo_check for this transaction.';
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', r.id::text, 'approved', 'ceo', round(r.amount_fils / 100.0, 2), v_rat) returning decision_id into v_dec;
    update public.refunds set refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now(), decision_note = v_rat where id = r.id;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, decision_id, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'approved', v_dec, p_trigger, true);
    return jsonb_build_object('ok', true, 'outcome', 'approved', 'cycle', v_cycle, 'decision_id', v_dec);
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_nonrem from jsonb_array_elements(v->'failed') i where not coalesce((i->>'remediable')::boolean, false);
  if jsonb_array_length(v_nonrem) > 0 then
    v_rat := 'Declined: ' || (select string_agg((i->>'item') || ' — ' || coalesce(i->>'reason', ''), '; ') from jsonb_array_elements(v_nonrem) i);
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', r.id::text, 'refused', 'ceo', round(r.amount_fils / 100.0, 2), left(v_rat, 2000)) returning decision_id into v_dec;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, decision_id, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'declined', v->'failed', v_dec, p_trigger, true);
    perform public.fn_refund_decide(r.id, false, 'ceo', left(v_rat, 900));
    return jsonb_build_object('ok', true, 'outcome', 'declined', 'cycle', v_cycle, 'reason', v_rat);
  end if;

  -- A CHECK THAT IS STILL BEING REASONED IS NOT A FAILURE (23 Sep 2026, founder_instruction 886-903).
  -- Under the model hold the off-platform notes wait in the CEO seat's reasoning queue. Counting that as a
  -- rejected cycle would hand work to nobody who can do it and, after three cycles, page the founder over a
  -- question no person needs to answer. So the refund rests, visible, with no cycle spent; the reasoned
  -- answer re-runs this review (fn_reason_apply_ceo__refund_off_platform).
  -- Only the unread note fails: the refund rests. Other remediable failures still go to their owners below
  -- (the day-3 chase, the final call, the amount), but no founder page is raised while reasoning is pending.
  v_wait := exists (select 1 from jsonb_array_elements(v->'failed') i where i->>'kind' = 'needs_reasoning');
  if v_wait and not exists (select 1 from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_reasoning',
      'held', (select jsonb_agg(i->'evidence') from jsonb_array_elements(v->'failed') i where i->>'kind' = 'needs_reasoning'));
  end if;

  if v_cycle > 3 and not v_wait then
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'escalated', v->'failed', p_trigger, true);
    perform public.fn_ceo_founder_summary('Refund approval loop stuck: refund #' || r.id,
      'The CEO rejected refund #' || r.id || ' three times and these checks still fail: '
        || (select string_agg((i->>'item') || ' (' || coalesce(i->>'reason', '') || ')', '; ') from jsonb_array_elements(v->'failed') i)
        || '. No money moves until they pass. Refunds and supplier charges are ' || case when public.fn_refunds_paused() then 'PAUSED' else 'running' end || '.',
      'refund_loop_stuck:' || r.id);
    return jsonb_build_object('ok', false, 'outcome', 'escalated', 'cycle', v_cycle);
  end if;

  insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger)
  values (r.id, r.transaction_id, v_cycle, 'rejected', v->'failed', p_trigger) returning id into v_rev;
  select chase_after_working_days into v_chase from public.pricing_config order by id limit 1;
  v_deadline := public.fn_add_working_days(now(), coalesce(v_chase, 3));
  for x in
    select i->>'owner' as owner, i->>'remedy_key' as rk, jsonb_agg(i->>'item') as checks, jsonb_agg(i) as items
      from jsonb_array_elements(v->'failed') i where coalesce(i->>'kind', '') <> 'needs_reasoning' group by 1, 2 order by 1, 2
  loop
    v_task := public.fn_seat_handoff('ceo', x.owner, 'refund.remediate', 'refunds', r.id || ':c' || v_cycle || ':' || x.rk,
      jsonb_build_object('refund_id', r.id, 'transaction_id', r.transaction_id, 'cycle', v_cycle, 'review_id', v_rev,
                         'remedy_key', x.rk, 'checks', x.checks, 'items', x.items, 'deadline', v_deadline));
    v_tasks := v_tasks || jsonb_build_object('handoff_id', v_task, 'owner', x.owner, 'checks', x.checks);
  end loop;
  update public.refund_ceo_review set sealed = true, tasks = v_tasks where id = v_rev;
  v_adv := public.fn_ceo_refund_loop_advance(r.id);
  return jsonb_build_object('ok', false, 'outcome', 'rejected', 'cycle', v_cycle, 'tasks', v_tasks, 'advance', v_adv);
end $function$;
revoke execute on function public.fn_ceo_refund_review(bigint, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_refund_review(bigint, text) to service_role;

-- ── 7. who owns a task, and which collaboration rule applies (sql.fn_task_review) ───────────────────────
create or replace function public.fn_task_review(p_task_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 set search_path to 'public', 'pg_temp'
AS $function$
declare
  t             record;
  v_text        text;
  v_deliverable text;
  v_author      text;
  v_chain       jsonb;
  v_outcome     text;
  v_rule        record;
  v_ch          jsonb;
  v_dept        text;
  v_blocked     boolean := false;
  v_blocker     text;
  v_dissents    jsonb := '[]'::jsonb;
  v_involved    jsonb := '[]'::jsonb;
  v_rules_hit   int := 0;
  v_own_resp    text;
  v_own_os      text;
  v_own_agent   text;
  v_own jsonb; v_resp_key text; v_resp_choice text; v_rule_key text; v_rule_choice text; v_held bigint;
  v_block_wait boolean := false;
  v_awaiting jsonb := '[]'::jsonb;   -- meaning questions filed with the CEO seat (23 Sep 2026)
begin
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.result, o.tier, o.assigned_agent
    into t from org_tasks o where o.id = p_task_id;
  if t.id is null then
    return jsonb_build_object('error', 'no such task', 'task_id', p_task_id);
  end if;

  v_deliverable := coalesce(t.result->>'deliverable', '');
  if v_deliverable = '' then
    return jsonb_build_object('task_id', p_task_id, 'outcome', 'no_deliverable',
      'reason', 'The task carries no deliverable to review.');
  end if;

  -- WHO ACTUALLY WROTE IT (4 Sep 2026). This was `coalesce(d.brain_agent, d.lead_agent, dept_key)` —
  -- the department head, whoever performed the work. fn_pick_reviewer then correctly refuses to let a
  -- head approve its own output, and for the Office of the CEO there is nobody above the ceo, so every
  -- exec task escalated on an authorship nobody claimed. The row records its worker; read it.
  select coalesce(nullif(t.result->>'employee',''), nullif(t.assigned_agent,''),
                  d.brain_agent, d.lead_agent, t.dept_key)
    into v_author
    from org_departments d where d.dept_key = t.dept_key;
  if v_author is null then
    v_author := coalesce(nullif(t.result->>'employee',''), nullif(t.assigned_agent,''), t.dept_key);
  end if;

  -- STAGE 1+2: department head, then Chief of Staff. This is fn_review_submit unchanged — the
  -- reviewer is resolved live through delegation_rule and seniority, so a head who is unavailable
  -- delegates rather than silently approving.
  v_chain   := fn_review_submit('org_task', p_task_id::text, t.dept_key, v_author, v_deliverable);
  v_outcome := v_chain->>'outcome';

  -- STAGE 3: the challenge. Deterministic, so it runs on every task rather than being rationed.
  v_text := coalesce(t.title,'') || ' ' || coalesce(t.detail,'') || ' ' || coalesce(t.action_class,'');

  -- STAGE 0 OF THE RECORD, WRITTEN HERE: WHO OWNS THIS PROCESS.
  -- WHICH RESPONSIBILITY THE WORK IS, REASONED (23 Sep 2026, founder_instruction 886-903). The
  -- responsibility was the longest one whose words appeared in the task text; it is now the CEO seat's
  -- reasoning over the declared responsibilities (ceo.task_responsibility), read back by its key. Until it
  -- is answered no owner is recorded — the ownership row is written by fn_task_ownership_record when the
  -- answer arrives (fn_reason_apply_ceo__task_responsibility), never on a word.
  v_resp_key := 'task_resp:' || p_task_id || ':' || md5(v_text);
  v_resp_choice := public.fn_reason_route_answer(v_resp_key);
  if v_resp_choice is null then
    v_held := public.fn_reason_route_ask('ceo', 'ceo.task_responsibility', v_text,
      coalesce((select jsonb_agg(jsonb_build_object('id', r.responsibility,
                  'meaning', 'the work is ' || replace(r.responsibility, '_', ' ') || ' (owned by the ' || r.os_key || ' operating system)')
                  order by r.responsibility) from os_responsibility r), '[]'::jsonb)
        || jsonb_build_array(jsonb_build_object('id', 'none', 'meaning', 'none of these responsibilities is what the work is')),
      jsonb_build_object('task_id', p_task_id, 'dept_key', t.dept_key, 'author', v_author), v_resp_key);
    -- No declared responsibility to choose between (and no text): nothing to reason, the department's OS owns it.
    if v_held is null then v_resp_choice := 'none';
    else v_awaiting := v_awaiting || jsonb_build_object('surface', 'ceo.task_responsibility', 'held_id', v_held); end if;
  end if;
  if v_resp_choice is not null then
    v_own := public.fn_task_ownership_record(p_task_id, t.dept_key, v_author, nullif(v_resp_choice, 'none'));
    v_own_os := v_own->>'owned_by_os'; v_own_agent := v_own->>'owner_agent'; v_own_resp := v_own->>'owns_responsibility';
  end if;

  for v_rule in
    select c.* from collaboration_rule c where c.owner_dept = t.dept_key
  loop
    -- WHETHER THE RULE'S SITUATION IS THIS TASK, REASONED (23 Sep 2026). Two shared long words decided it
    -- before. Measured 23 Sep 2026: collaboration_rule holds 0 rows, so this loop runs for nobody today.
    -- A rule reasoned to apply AFTER this review ran is recorded, with its challenges, by its apply routine;
    -- a BLOCKING one still waiting holds publication (v_block_wait below).
    v_rule_key := 'task_rule:' || p_task_id || ':' || v_rule.id || ':' || md5(v_text);
    v_rule_choice := public.fn_reason_route_answer(v_rule_key);
    if v_rule_choice is null then
      v_held := public.fn_reason_route_ask('ceo', 'ceo.task_collaboration_rule', v_text,
        jsonb_build_array(jsonb_build_object('id', 'applies', 'meaning', 'the task is the situation this rule governs: ' || v_rule.situation),
                          jsonb_build_object('id', 'does_not_apply', 'meaning', 'the task is not that situation')),
        jsonb_build_object('task_id', p_task_id, 'rule_id', v_rule.id, 'dept_key', t.dept_key, 'author', v_author), v_rule_key);
      v_awaiting := v_awaiting || jsonb_build_object('surface', 'ceo.task_collaboration_rule', 'rule_id', v_rule.id, 'held_id', v_held);
      if v_rule.blocking then v_block_wait := true; end if;
      continue;
    end if;
    if v_rule_choice <> 'applies' then continue; end if;
    v_rules_hit := v_rules_hit + 1;

    -- Who the rule says must take part, recorded as its own reviewable stage so that "this needed
    -- legal and legal never saw it" is answerable after the fact.
    v_involved := v_involved || jsonb_build_object(
      'situation', v_rule.situation, 'must_involve', to_jsonb(v_rule.must_involve),
      'must_review', to_jsonb(v_rule.must_review), 'blocking', v_rule.blocking);

    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                              stage, decision, reason, confidence)
    values ('org_task', p_task_id::text, t.dept_key, v_author,
            coalesce((v_rule.must_review)[1], 'exec'), 'collaboration',
            case when v_rule.blocking then 'required' else 'advisory' end,
            'collaboration_rule #' || v_rule.id || ' applies ("' || v_rule.situation || '"): '
              || 'involve ' || coalesce(array_to_string(v_rule.must_involve, ', '), '(none)')
              || '; review by ' || coalesce(array_to_string(v_rule.must_review, ', '), '(none)')
              || '; may be challenged by ' || coalesce(array_to_string(v_rule.may_challenge, ', '), '(none)')
              || '. Why this rule exists: ' || v_rule.reason, 1.0);

    -- Each department the rule permits to challenge actually challenges.
    foreach v_dept in array coalesce(v_rule.may_challenge, array[]::text[]) loop
      v_ch := fn_challenge(v_text, t.dept_key, v_dept);
      if (v_ch->>'stance') <> 'support' then
        v_dissents := v_dissents || jsonb_build_object(
          'by', v_dept, 'stance', v_ch->>'stance', 'confidence', v_ch->>'confidence',
          'reasoning', v_ch->>'reasoning', 'blocking', v_rule.blocking);

        insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                                  stage, decision, reason, violated_rule, confidence)
        values ('org_task', p_task_id::text, t.dept_key, v_author, v_dept, 'challenge',
                case when v_rule.blocking and (v_ch->>'stance') = 'recommend_against'
                     then 'reject' else 'dissent' end,
                upper(v_ch->>'stance') || ' from ' || v_dept || ': ' || coalesce(v_ch->>'reasoning','')
                  || case when v_ch->'alternatives' <> '[]'::jsonb
                          then ' Alternative offered: ' || (v_ch->'alternatives'->>0) else '' end,
                v_ch->>'conflicts_with', (v_ch->>'confidence')::numeric);

        -- THE FOUNDER'S RULE, 6 Aug 2026: the blocking flag decides whether a rejection stops the
        -- work or is recorded against it. The reason is written either way.
        if v_rule.blocking and (v_ch->>'stance') = 'recommend_against' then
          v_blocked := true;
          v_blocker := v_dept || ' — ' || left(coalesce(v_ch->>'reasoning',''), 200);
        end if;
      end if;
    end loop;
  end loop;

  -- A BLOCKING rule whose situation is still being reasoned holds publication: the task rests until the
  -- answer (fn_reason_apply_ceo__task_collaboration_rule) records the rule and its challenges.
  if v_block_wait and not v_blocked and v_outcome in ('published', 'approve') then
    v_outcome := 'awaiting_reasoning';
  end if;

  if v_blocked and v_outcome in ('published', 'approve') then
    v_outcome := 'request_revision';
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                              stage, decision, reason, confidence)
    values ('org_task', p_task_id::text, t.dept_key, v_author, 'brief', 'cos_review',
            'request_revision',
            'Returned for revision by the Chief of Staff: a BLOCKING collaboration rule was '
            || 'challenged and the challenge recommended against it. ' || v_blocker, 1.0);
  end if;

  -- "Every completed task should generate learning." Written here, by the reviewer, at the moment
  -- the verdict is known — the review already establishes what was wrong, so the lesson costs
  -- nothing. Never let recording the lesson fail the review itself.
  begin
    perform fn_task_lesson(p_task_id, v_outcome,
      jsonb_build_object('violations', coalesce(v_chain->'violations','[]'::jsonb),
                         'dissents',   v_dissents,
                         'reviewer',   v_chain->>'reviewer'));
  exception when others then null;
  end;

  return jsonb_build_object(
    'task_id',        p_task_id,
    'outcome',        v_outcome,
    'stopped_at',     v_chain->>'stopped_at',
    'author',         v_author,
    'reviewer',       v_chain->>'reviewer',
    'delegated_from', v_chain->>'delegated_from',
    'violations',     coalesce(v_chain->'violations', '[]'::jsonb),
    'unenforceable',  coalesce(v_chain->'unenforceable', '[]'::jsonb),
    'rules_applied',  v_rules_hit,
    'collaboration',  v_involved,
    'dissents',       v_dissents,
    'owned_by_os',    v_own_os,
    'owner_agent',    v_own_agent,
    'owns_responsibility', v_own_resp,
    'blocked',        v_blocked,
    'awaiting_reasoning', v_awaiting);
end
$function$;
revoke execute on function public.fn_task_review(bigint) from public, anon, authenticated;
grant execute on function public.fn_task_review(bigint) to service_role;

-- ── 8. the supplier's document is asked about when its label is saved (sql.fn_supplier_document_home) ──
-- The question is filed once per label (the key carries the label's md5), so a rename asks again and a
-- replace of the bytes alone does not.
create or replace function public.fn_supplier_document_subject_ask(p_id bigint, p_file_name text, p_kind text, p_ref_id text)
returns bigint
language sql security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select public.fn_reason_route_ask('sales_engineer', 'supplier_documents.subject',
    'A supplier uploaded a company document and labelled it: "' || p_file_name || '" (the type they chose: '
      || coalesce(p_kind, 'none') || '). Which document is it?',
    jsonb_build_array(
      jsonb_build_object('id', 'iso', 'meaning', 'an ISO management-system certificate (ISO 9001, 14001, 45001 ...)'),
      jsonb_build_object('id', 'insurance', 'meaning', 'an insurance policy or certificate (public liability, contractor all-risk, workmen compensation ...)'),
      jsonb_build_object('id', 'manufacturer_auth', 'meaning', 'a manufacturer, brand or distributor authorisation / agency letter'),
      jsonb_build_object('id', 'none', 'meaning', 'any other document')),
    jsonb_build_object('document_id', p_id, 'lead_id', p_ref_id),
    'supdoc:' || p_id || ':' || md5(coalesce(p_file_name, '')));
$fn$;
revoke execute on function public.fn_supplier_document_subject_ask(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_document_subject_ask(bigint, text, text, text) to service_role;

create or replace function public.trg_supplier_document_subject_asked()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if NEW.ref_table = 'supplier_supporting' and coalesce(NEW.status, '') <> 'withdrawn' and btrim(coalesce(NEW.file_name, '')) <> '' then
    perform public.fn_supplier_document_subject_ask(NEW.id, NEW.file_name, NEW.kind, NEW.ref_id);
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_supplier_document_subject_asked() from public, anon, authenticated;
grant execute on function public.trg_supplier_document_subject_asked() to service_role;
-- CREATE OR REPLACE (not drop + create): SHARE ROW EXCLUSIVE, so reads of documents never wait on this apply.
create or replace trigger supplier_document_subject_asked after insert or update of file_name, status on public.documents
  for each row execute function public.trg_supplier_document_subject_asked();

-- The live supporting documents already on file are asked about once (6 on 23 Sep 2026). Called directly,
-- not through an UPDATE, so no other trigger on documents fires for them.
do $backfill$
begin
  perform public.fn_supplier_document_subject_ask(d.id, d.file_name, d.kind, d.ref_id)
     from public.documents d
    where d.ref_table = 'supplier_supporting' and coalesce(d.status, '') <> 'withdrawn' and btrim(coalesce(d.file_name, '')) <> '';
end $backfill$;

-- ── 9. the replay effects: each surface applies its own reasoned answer ──────────────────────────────
-- Called by fn_reason_held_resolve (a_reasoned_answer_is_applied_by_its_own_surface.sql) AFTER it has
-- marked the row reasoned, so fn_reason_route_answer already returns the choice the step waited for.

-- The escalation that waited is decided now, on the reasoned meaning.
create or replace function public.fn_reason_apply_ceo__escalation_meaning(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if r.subject is null or coalesce(r.subject->>'kind', '') = '' then return null; end if;
  return jsonb_build_object('choice', p_result->'decision'->>'choice',
    'decided', public.fn_decide(r.subject->>'kind', coalesce(r.subject->'ctx', '{}'::jsonb), coalesce(r.subject->>'actor', 'agent')));
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__escalation_meaning(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__escalation_meaning(bigint, jsonb) to service_role;

-- The refund that waited is reviewed again, now that its notes have been read.
create or replace function public.fn_reason_apply_ceo__refund_off_platform(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_rid bigint;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_rid := nullif(r.subject->>'refund_id', '')::bigint;
  if v_rid is null or not exists (select 1 from public.refunds f where f.id = v_rid and f.status = 'requested') then
    return jsonb_build_object('refund_id', v_rid, 'choice', p_result->'decision'->>'choice', 'review', 'not_open');
  end if;
  return jsonb_build_object('refund_id', v_rid, 'choice', p_result->'decision'->>'choice',
                            'review', public.fn_ceo_refund_review(v_rid, 'reasoned'));
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__refund_off_platform(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__refund_off_platform(bigint, jsonb) to service_role;

-- The owner of a task, recorded from the reasoned responsibility (or its department's OS when the answer
-- is that none of them is what the work is). One ownership row per task, as before.
create or replace function public.fn_task_ownership_record(p_task_id bigint, p_dept text, p_author text, p_resp text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_os text; v_agent text; v_resp text := p_resp;
begin
  if v_resp is not null then
    select r.os_key into v_os from os_responsibility r where r.responsibility = v_resp order by r.os_key limit 1;
    if v_os is null then v_resp := null; end if;
  end if;
  if v_os is null then
    select d.os_key into v_os from os_department d where d.dept_key = p_dept order by d.os_key limit 1;
  end if;
  select o.owner_agent into v_agent from operating_system o
   where o.os_key = v_os and o.active
     and exists (select 1 from org_agents a where a.agent_key = o.owner_agent and a.active);
  if v_agent is not null and v_agent is distinct from p_author then   -- an owner who authored it is already accountable; a self-review row is refused by the chain guard
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                              stage, decision, reason, confidence)
    select 'org_task', p_task_id::text, p_dept, p_author, v_agent, 'ownership', 'owned',
           'os_responsibility routes this work to the ' || v_os || ' OS'
             || case when v_resp is null
                     then ', taken from the owning OS of the ' || p_dept || ' department because '
                          || 'the CEO seat reasoned that no declared responsibility is what the task is'
                     else ', which is the declared owner of the responsibility "' || v_resp || '" (reasoned by the CEO seat)'
                end
             || '. Accountable to the company for it: ' || v_agent || '.', 1.0
     where not exists (select 1 from review_chain rc
                        where rc.subject_type = 'org_task' and rc.subject_id = p_task_id::text
                          and rc.stage = 'ownership');
  end if;
  return jsonb_build_object('owned_by_os', v_os, 'owner_agent', v_agent, 'owns_responsibility', v_resp);
end $fn$;
revoke execute on function public.fn_task_ownership_record(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_task_ownership_record(bigint, text, text, text) to service_role;

create or replace function public.fn_reason_apply_ceo__task_responsibility(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if nullif(r.subject->>'task_id', '') is null then return null; end if;
  return public.fn_task_ownership_record((r.subject->>'task_id')::bigint, r.subject->>'dept_key', r.subject->>'author',
                                         nullif(p_result->'decision'->>'choice', 'none'));
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__task_responsibility(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__task_responsibility(bigint, jsonb) to service_role;

-- A collaboration rule reasoned to apply is recorded against the task, and its challenges are replayed.
-- A task the lane parked while the rule waited is unparked here, so the lane reviews it again on the answer.
create or replace function public.fn_reason_apply_ceo__task_collaboration_rule(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; c public.collaboration_rule; v_text text; v_dept text; v_ch jsonb; v_n int := 0;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  select * into c from public.collaboration_rule where id::text = r.subject->>'rule_id';
  if c.id is null or coalesce(p_result->'decision'->>'choice', '') <> 'applies' then
    update public.org_tasks set status = 'assigned', updated_at = now(),
           result = coalesce(result, '{}'::jsonb) || jsonb_build_object('unparked', jsonb_build_object('at', now(), 'by', 'reasoning', 'held_id', p_id))
     where id::text = r.subject->>'task_id' and status = 'blocked' and (result ? 'parked');
    return jsonb_build_object('rule_id', r.subject->>'rule_id', 'applies', false);
  end if;
  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage, decision, reason, confidence)
  select 'org_task', r.subject->>'task_id', r.subject->>'dept_key', r.subject->>'author',
         coalesce((c.must_review)[1], 'exec'), 'collaboration', case when c.blocking then 'required' else 'advisory' end,
         'collaboration_rule #' || c.id || ' applies ("' || c.situation || '", reasoned by the CEO seat): '
           || 'involve ' || coalesce(array_to_string(c.must_involve, ', '), '(none)')
           || '; review by ' || coalesce(array_to_string(c.must_review, ', '), '(none)')
           || '. Why this rule exists: ' || c.reason, 1.0
;
  -- Each department the rule permits to challenge challenges, as fn_task_review does; never the author, once.
  select coalesce(o.title,'') || ' ' || coalesce(o.detail,'') || ' ' || coalesce(o.action_class,'') into v_text
    from org_tasks o where o.id::text = r.subject->>'task_id';
  foreach v_dept in array coalesce(c.may_challenge, array[]::text[]) loop
    continue when v_dept is not distinct from r.subject->>'author'
      or exists (select 1 from review_chain rc where rc.subject_type = 'org_task' and rc.subject_id = r.subject->>'task_id'
                   and rc.stage = 'challenge' and rc.reviewer_agent = v_dept);
    v_ch := fn_challenge(coalesce(v_text, ''), r.subject->>'dept_key', v_dept);
    if (v_ch->>'stance') <> 'support' then
      insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage, decision, reason, violated_rule, confidence)
      values ('org_task', r.subject->>'task_id', r.subject->>'dept_key', r.subject->>'author', v_dept, 'challenge',
              case when c.blocking and (v_ch->>'stance') = 'recommend_against' then 'reject' else 'dissent' end,
              upper(v_ch->>'stance') || ' from ' || v_dept || ': ' || coalesce(v_ch->>'reasoning',''),
              v_ch->>'conflicts_with', (v_ch->>'confidence')::numeric);
      v_n := v_n + 1;
    end if;
  end loop;
  update public.org_tasks set status = 'assigned', updated_at = now(),
         result = coalesce(result, '{}'::jsonb) || jsonb_build_object('unparked', jsonb_build_object('at', now(), 'by', 'reasoning', 'held_id', p_id))
   where id::text = r.subject->>'task_id' and status = 'blocked' and (result ? 'parked');
  return jsonb_build_object('rule_id', c.id, 'applies', true, 'task_id', r.subject->>'task_id', 'challenges', v_n);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__task_collaboration_rule(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__task_collaboration_rule(bigint, jsonb) to service_role;

-- A differently worded repeat request is flagged when the reasoning says it is the same job.
create or replace function public.fn_reason_apply_inquiry__same_request(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_n int := 0;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if coalesce(p_result->'decision'->>'choice', '') = 'same_request' then
    update public.inquiries
       set plausibility = coalesce(plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true,
             'duplicate_of', r.subject->>'earlier_id', 'duplicate_by', 'reasoning', 'held_id', p_id)
     where id::text = r.subject->>'inquiry_id';
    get diagnostics v_n = row_count;
  end if;
  return jsonb_build_object('inquiry_id', r.subject->>'inquiry_id', 'choice', p_result->'decision'->>'choice', 'flagged', v_n > 0);
end $fn$;
revoke execute on function public.fn_reason_apply_inquiry__same_request(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_inquiry__same_request(bigint, jsonb) to service_role;
