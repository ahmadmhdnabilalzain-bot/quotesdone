-- EVERY SEAT REASONS BEFORE IT ANSWERS — the database half of the shared reasoning engine.
-- Seat: it_engineer (shared platform used by every seat). 23 Sep 2026, founder_instruction 886-903.
--
-- WHAT THE FOUNDER RULED. No word matching anywhere: what a message means is decided by reasoning,
-- never by a keyword list, a regex or an ilike. Any question from a customer or supplier about any
-- category, detail or spec (F&B excepted) is answered; "I need to check and get back to you" is not an
-- answer. Every seat thinks in steps first — which emirate, which authority, is the limit local or
-- emirate-wide — then answers, and asks back only for a missing fact that changes the answer.
--
-- WHAT THIS FILE IS. The TypeScript engine (supabase/functions/_shared/think.ts) plans, retrieves,
-- researches, writes and verifies; it needs four things from the database, and they are here:
--   1. fn_reason_retrieve — nearest knowledge by MEANING for one plan step, across every source a seat
--      reasons from. Vector distance only (gte-small, 384-d, free, in-region). HNSW where the table has
--      one (kb_chunks 150k rows, ops_knowledge, sales/accountant/it_engineer knowledge), an exact scan
--      where it is small enough not to need one (agent_knowledge 2.5k, company_faq 0.6k, research).
--      No lexical gate decides what is relevant: nothing here reads a word of the question.
--   2. reasoning_held_question — the owning seat's queue. Under the model hold there is no reasoning to
--      do and a keyword answer is forbidden, so the question is filed with its plan and re-run by
--      fn_reason_held_due / fn_reason_held_resolve the moment the gate opens.
--   3. reasoning_knowledge_candidate — what web research found, cited, PENDING review. Retrieval reads it
--      at once (marked pending_review) so the next question is answered from knowledge, and a reviewer
--      approves or rejects it.
--   4. the effect a replay applies for a surface whose effect lives in SQL (ceo.command_intent: the
--      command's intent; inquiry_intake.trade: the held intake's trade). A surface whose effect is a
--      MESSAGE is delivered on its own channel by _shared/reasoned_delivery.ts (WhatsApp free text inside
--      the 24-hour window, the support_reply template outside it; social through the platform reply path)
--      and the outcome is recorded here by fn_reason_held_delivered.
--   5. EXPIRY. A held channel question is worth answering for 7 days; after that it is marked 'expired',
--      not replayed at full model cost weeks later (review of this PR, finding 4). The CEO's commands and
--      a held intake never expire: the founder and the customer are still waiting on them.
--
-- MEASURED 23 Sep 2026 against production (read-only): vector(384) embedding_gte on accountant_knowledge
-- (113), agent_knowledge (2,556), company_faq (638), it_engineer_knowledge (79), kb_chunks (150,103),
-- ops_knowledge (9,140), sales_knowledge (1,192); HNSW on kb_chunks, ops_knowledge, sales_, accountant_
-- and it_engineer_knowledge. support_knowledge and ceo_knowledge carry NO vector column, so they are not
-- read here; the customer_support and ceo seats reason from the company-wide sources until theirs are
-- embedded (registry item). kb_chunks.source_kind: qd_kb_pack 90k, standard 32k, cert 9.8k, code 4k,
-- guide 3.1k, document 2.8k, trade 2k, regulation 1.9k — the trade packs and the authority rules.
--
-- WHAT IT DOES NOT DO. It does not call a model and it does not lift the hold. It does not decide any
-- meaning itself. The decision points that used word lists are migrated in
-- scripts/sql/meaning_is_decided_by_reasoning_not_by_word_lists.sql.
--
-- Pending: scripts/sql/pending/every_seat_reasons_before_it_answers.txt. Proved by replaying this file,
-- its sibling and a probe inside one aborted transaction: scripts/checks/decision_points_are_reasoned.test.mjs.

-- ── 1. the seat's queue of held questions ───────────────────────────────────────────────────────
create table if not exists public.reasoning_held_question (
  id              bigint generated always as identity primary key,
  seat            text not null references public.org_role(role_id),
  surface         text not null check (surface ~ '^[a-z_]+(\.[a-z_]+)*$'),
  question        text not null check (btrim(question) <> '' and length(question) <= 8000),
  request         jsonb not null check (jsonb_typeof(request) = 'object' and length(request::text) <= 60000),
  plan            jsonb not null default '{}'::jsonb check (jsonb_typeof(plan) = 'object' and length(plan::text) <= 60000),
  subject         jsonb check (subject is null or jsonb_typeof(subject) = 'object'),
  reason          text not null check (btrim(reason) <> ''),
  status          text not null default 'held' check (status in ('held', 'reasoned', 'applied', 'failed', 'expired')),
  expires_at      timestamptz,
  attempts        integer not null default 0,
  last_attempt_at timestamptz,
  result          jsonb,
  reasoned_at     timestamptz,
  applied_at      timestamptz,
  created_at      timestamptz not null default now(),
  dedupe_key      text unique
);
create index if not exists reasoning_held_question_due_idx on public.reasoning_held_question (status, last_attempt_at nulls first, created_at) where status = 'held';
alter table public.reasoning_held_question enable row level security;
drop policy if exists reasoning_held_question_service_role_only on public.reasoning_held_question;
create policy reasoning_held_question_service_role_only on public.reasoning_held_question
  as permissive for all to public using (false) with check (false);
revoke all on public.reasoning_held_question from anon, authenticated;
comment on table public.reasoning_held_question is
  'A question a seat could not reason about yet (model hold, model failure, repeated evasion). Filed by _shared/think.ts with its plan; re-run by replayHeld the moment the gate opens. Never answered by a word list meanwhile (founder_instruction 886-903).';

-- ── 2. what research found, pending review ──────────────────────────────────────────────────────
create table if not exists public.reasoning_knowledge_candidate (
  id            bigint generated always as identity primary key,
  seat          text not null references public.org_role(role_id),
  question      text not null check (btrim(question) <> ''),
  finding       text not null check (btrim(finding) <> '' and length(finding) <= 4000),
  sources       jsonb not null check (jsonb_typeof(sources) = 'array' and jsonb_array_length(sources) > 0),
  embedding_gte vector(384),
  status        text not null default 'pending_review' check (status in ('pending_review', 'approved', 'rejected')),
  reviewed_by   text,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now(),
  finding_sha   text generated always as (md5(lower(btrim(finding)))) stored unique,
  check (status = 'pending_review' or (reviewed_by is not null and reviewed_at is not null))
);
alter table public.reasoning_knowledge_candidate enable row level security;
drop policy if exists reasoning_knowledge_candidate_service_role_only on public.reasoning_knowledge_candidate;
create policy reasoning_knowledge_candidate_service_role_only on public.reasoning_knowledge_candidate
  as permissive for all to public using (false) with check (false);
revoke all on public.reasoning_knowledge_candidate from anon, authenticated;
comment on table public.reasoning_knowledge_candidate is
  'A fact web research found on a UAE authority page and a seat cited in an answer. Every row carries its URLs. Retrieval reads pending rows marked pending_review; a reviewer approves or rejects.';

-- ── 3. retrieval by meaning, per plan step ──────────────────────────────────────────────────────
-- SUPERSEDED (23 Sep 2026) by scripts/sql/every_verified_pack_has_a_home_and_every_seat_reads_its_own.sql,
-- which adds support_knowledge, ceo_knowledge and marketing_knowledge and lets customer_support read the
-- trade packs. That file's MANIFEST line is later, so its definition is the canonical one once applied.
create or replace function public.fn_reason_retrieve(p_seat text, p_embedding vector(384), p_k integer default 6)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
set "hnsw.iterative_scan" to 'relaxed_order'
set "hnsw.ef_search" to '100'
as $fn$
declare
  k   integer := greatest(1, least(coalesce(p_k, 6), 12));
  out jsonb := '[]'::jsonb;
begin
  if p_embedding is null then return out; end if;

  -- Each source is ordered by distance on its own, so each uses its own index; the union is then
  -- ranked by the same distance. Excerpts are cut, never the ranking.
  with hits as (
    (select 'kb_chunks' src, c.id::text id, c.title, left(c.content, 1200) excerpt, c.citation,
            1 - (c.embedding_gte <=> p_embedding) sim, 'reviewed' trust
       from public.kb_chunks c where c.embedding_gte is not null
      order by c.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ops_knowledge', o.record_id, o.title, left(o.content, 1200), o.source_path,
            1 - (o.embedding_gte <=> p_embedding), 'reviewed'
       from public.ops_knowledge o
      where o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
        and o.scope_type in ('company', 'external_source', 'category')
      order by o.embedding_gte <=> p_embedding limit k)
    union all
    (select 'agent_knowledge', a.id::text, a.topic, left(a.content, 1200), a.source_ref,
            1 - (a.embedding_gte <=> p_embedding), 'reviewed'
       from public.agent_knowledge a
      where a.embedding_gte is not null and a.agent_key in (p_seat, '_global')
      order by a.embedding_gte <=> p_embedding limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id,
            1 - (f.embedding_gte <=> p_embedding), 'reviewed'
       from public.company_faq f where f.embedding_gte is not null and f.status = 'approved'
      order by f.embedding_gte <=> p_embedding limit k)
    union all
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.sales_knowledge s
      where p_seat = 'sales_engineer' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.accountant_knowledge s
      where p_seat = 'accountant' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.it_engineer_knowledge s
      where p_seat = 'it_engineer' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url',
            1 - (r.embedding_gte <=> p_embedding), case when r.status = 'approved' then 'reviewed' else 'pending_review' end
       from public.reasoning_knowledge_candidate r
      where r.embedding_gte is not null and r.status <> 'rejected'
      order by r.embedding_gte <=> p_embedding limit k)
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(sim::numeric, 4), 'trust', trust) order by sim desc), '[]'::jsonb)
    into out
    from (select * from hits order by sim desc limit k * 2) t;
  return out;
end $fn$;
revoke execute on function public.fn_reason_retrieve(text, vector, integer) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve(text, vector, integer) to service_role;

-- ── 4. the queue: file, claim, resolve ──────────────────────────────────────────────────────────
create or replace function public.fn_reason_hold(p_seat text, p_surface text, p_question text, p_request jsonb,
  p_plan jsonb, p_subject jsonb, p_reason text, p_dedupe_key text default null)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, expires_at)
  values (p_seat, p_surface, left(p_question, 8000), p_request, coalesce(p_plan, '{}'::jsonb), p_subject, p_reason, p_dedupe_key,
          case when p_surface in ('ceo.command_intent', 'inquiry_intake.trade') then null else now() + interval '7 days' end)
  on conflict (dedupe_key) do update set reason = excluded.reason, plan = excluded.plan
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_reason_hold(text, text, text, jsonb, jsonb, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_hold(text, text, text, jsonb, jsonb, jsonb, text, text) to service_role;

-- Claims the oldest held rows, least recently attempted first. Returns NOTHING while the gate refuses
-- for the hold — a replay under the hold would only re-file the same question.
create or replace function public.fn_reason_held_due(p_limit integer default 3)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_gate jsonb; v jsonb;
begin
  -- What can no longer be answered usefully is closed with its reason, never replayed at cost — and this
  -- runs under the hold too, so an expired question does not wait for the release to be closed.
  update public.reasoning_held_question set status = 'expired' where status = 'held' and expires_at < now();
  update public.reasoning_held_question set status = 'failed' where status = 'held' and attempts >= 5;
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with due as (
    select id from public.reasoning_held_question
     where status = 'held' and attempts < 5 and (expires_at is null or expires_at >= now())
       and (last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     order by last_attempt_at nulls first, created_at
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now()
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $fn$;
revoke execute on function public.fn_reason_held_due(integer) from public, anon, authenticated;
grant execute on function public.fn_reason_held_due(integer) to service_role;

-- The result of a replay. A result that is itself 'held' leaves the row held (attempts counts it; the
-- fifth failure marks it failed so it stops being retried and is visible). An answered result is
-- 'reasoned', and a surface whose effect lives in SQL has it applied here.
create or replace function public.fn_reason_held_resolve(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_effect jsonb := null;
begin
  select * into r from public.reasoning_held_question where id = p_id for update;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  if coalesce(p_result->>'status', '') <> 'answered' then
    update public.reasoning_held_question
       set result = p_result, status = case when attempts >= 5 then 'failed' else 'held' end
     where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'still_held');
  end if;
  update public.reasoning_held_question set result = p_result, status = 'reasoned', reasoned_at = now() where id = p_id;
  if r.surface = 'ceo.command_intent' and (r.subject->>'command_id') is not null then
    v_effect := public.fn_ceo_command_interpret((r.subject->>'command_id')::bigint, p_result->'decision'->>'choice',
                  left(coalesce(p_result->>'answer', ''), 1000));
    update public.reasoning_held_question set status = 'applied', applied_at = now() where id = p_id;
  elsif r.surface = 'inquiry_intake.trade' and (r.subject->>'intake_id') is not null then
    -- The held intake gets its reasoned trade and reopens; the portal continues the interview from it.
    update public.inquiry_intake i
       set category = p_result->'decision'->>'choice', status = 'needs_info', updated_at = now(),
           brief = coalesce(i.brief, '{}'::jsonb) || jsonb_build_object('category_by', 'reasoning', 'held_id', p_id)
     where i.id::text = r.subject->>'intake_id' and i.status = 'held'
       and exists (select 1 from public.category_specs cs where cs.category = p_result->'decision'->>'choice');
    v_effect := jsonb_build_object('intake_id', r.subject->>'intake_id', 'category', p_result->'decision'->>'choice', 'reopened', found);
    update public.reasoning_held_question set status = 'applied', applied_at = now() where id = p_id;
  end if;
  return jsonb_build_object('id', p_id, 'status', case when v_effect is null then 'reasoned' else 'applied' end, 'effect', v_effect);
end $fn$;
revoke execute on function public.fn_reason_held_resolve(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_held_resolve(bigint, jsonb) to service_role;

-- ── 5. research written back ────────────────────────────────────────────────────────────────────
create or replace function public.fn_reason_propose_knowledge(p_seat text, p_question text, p_finding text,
  p_sources jsonb, p_embedding vector(384))
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  if jsonb_typeof(p_sources) <> 'array' or jsonb_array_length(p_sources) = 0
     or exists (select 1 from jsonb_array_elements(p_sources) s where coalesce(s->>'url', '') !~ '^https://') then
    raise exception 'a research finding needs at least one https source' using errcode = '22023';
  end if;
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, embedding_gte)
  values (p_seat, left(p_question, 2000), left(p_finding, 4000), p_sources, p_embedding)
  on conflict (finding_sha) do nothing
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_reason_propose_knowledge(text, text, text, jsonb, vector) from public, anon, authenticated;
grant execute on function public.fn_reason_propose_knowledge(text, text, text, jsonb, vector) to service_role;

-- ── 6. what the channel delivery did ────────────────────────────────────────────────────────────
create or replace function public.fn_reason_held_delivered(p_id bigint, p_delivery jsonb)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  update public.reasoning_held_question
     set result = coalesce(result, '{}'::jsonb) || jsonb_build_object('delivery', p_delivery),
         status = case when coalesce((p_delivery->>'delivered')::boolean, false) or p_delivery->>'via' = 'none' then 'applied' else status end,
         applied_at = case when coalesce((p_delivery->>'delivered')::boolean, false) or p_delivery->>'via' = 'none' then now() else applied_at end
   where id = p_id;
end $fn$;
revoke execute on function public.fn_reason_held_delivered(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_held_delivered(bigint, jsonb) to service_role;
