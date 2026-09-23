-- EVERY SEAT REMEMBERS ITS CASES AND RECALLS THEM BY MEANING (23 Sep 2026, it_engineer, shared platform).
--
-- THE FOUNDER, 23 Sep 2026: "If a sales agent dealt with a customer today for a specific inquiry and
-- later another customer asked a very similar inquiry, it should tip something in his brain — we did
-- that before, what did we do, was it finalised or not. This is how real employees work." Structural,
-- for EVERY seat. Standing rule: recall by MEANING (gte-small), never by word matching.
--
-- WHAT WAS MEASURED (audit/learning_loop_and_cross_family.md, 23 Sep): nine routines search by vector,
-- and every one reads a KNOWLEDGE table or the LLM cache. None reads an episode. The nearest thing to a
-- case memory was it_engineer_finding (341 rows, 329 closed with a close_note), deduplicated by exact
-- issue_key only. The legacy stores (institutional_memory 1,973, agent_memory 975) are keyed to
-- departments that no longer exist and are left untouched as history; nothing is backfilled from them.
--
-- WHAT THIS BUILDS
--   1. public.seat_case_memory — one row per case, keyed on the live row it came from
--      (source_table, source_id). Situation text is MASKED AT WRITE: e-mails, phone numbers, links and
--      every identity string the source row itself names (the customer's name, e-mail, phone; the
--      complainant's name) become [party]/[email]/[phone]/[link]. Recall can therefore never hand one
--      customer's identity to another seat or another customer.
--   2. Write-back: AFTER triggers on each seat's case-closing events. A case that finalises later is
--      the SAME row updated. No trigger can fail its source write: an error is written to
--      seat_case_memory_miss (read by the check) and the source row goes through.
--   3. Embedding queue: a row whose situation changed has embedding NULL. resilience_ping's
--      caseMemoryEmbedTick claims a few per tick (fn_case_embed_claim) and writes them back
--      (fn_case_embed_write) with the in-runtime gte-small session — free, in-region, NOT OpenRouter.
--      scripts/kb/embed_seat_case_memory.mjs drains a backlog (the 329 IT findings) the same way.
--   4. fn_case_recall(seat, embedding, trade, k, ...) — the top similar past cases with decision,
--      outcome, finalised, lessons, correction and similarity. Exact scan below 20,000 rows, HNSW above.
--   5. Corrections become lessons: fn_case_correct appends to lessons and sets correction/corrected_by.
--      Wired automatically for a CEO refusal (ceo_approval), an accountant re-classification
--      (expense_entries.category changed) and a reopened IT finding (the earlier fix did not hold).
--
-- THE FLOOR, MEASURED (23 Sep 2026, gte-small via ai_gateway {action:'embed'}):
--   paraphrases of the same case 0.847-0.924; unrelated cases 0.760-0.816. Floor = 0.84.
--   A DIFFERENT trade framed the same way scored 0.913 ("40 split AC units ... two-floor office" vs
--   "200 office chairs ... two-floor office"): similarity alone cannot separate that, so a caller that
--   knows the trade passes it and a case recorded under another trade is excluded (the exact-trade rule).
--   A corrected case gets +0.05 in the ranking only, never toward the floor.

create table if not exists public.seat_case_memory (
  id              bigserial primary key,
  seat            text not null check (seat in ('ceo','customer_support','sales_engineer','accountant','it_engineer','marketing')),
  case_kind       text not null,
  source_table    text not null,
  source_id       text not null,
  trade           text,
  situation       text not null,
  decision        text,
  reasoning       text,
  outcome         text,
  finalised       boolean not null default false,
  finalised_at    timestamptz,
  lessons         text[] not null default '{}',
  corrected_by    text,
  correction      text,
  embedding       vector(384),
  embedded_hash   text,
  embed_claimed_at timestamptz,
  opened_at       timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint seat_case_memory_source_uq unique (source_table, source_id)
);
comment on table public.seat_case_memory is
  'One row per case any seat handled, keyed on the live row (source_table, source_id). Party identity is masked at write. Embedded with gte-small; read by fn_case_recall before a seat decides. Scripts: every_seat_remembers_its_cases_and_recalls_them_by_meaning.sql.';

create index if not exists seat_case_memory_seat_kind_idx on public.seat_case_memory (seat, case_kind, finalised, opened_at desc);
create index if not exists seat_case_memory_pending_idx on public.seat_case_memory (id) where embedding is null;
create index if not exists seat_case_memory_emb_hnsw on public.seat_case_memory using hnsw (embedding vector_cosine_ops);

alter table public.seat_case_memory enable row level security;
drop policy if exists seat_case_memory_service_role_only on public.seat_case_memory;
create policy seat_case_memory_service_role_only on public.seat_case_memory
  as permissive for all to public using (false) with check (false);
revoke all on public.seat_case_memory from anon, authenticated;
revoke all on sequence public.seat_case_memory_id_seq from anon, authenticated;

-- A write-back that failed. Never silent, never fatal to the source row.
create table if not exists public.seat_case_memory_miss (
  id           bigserial primary key,
  source_table text not null,
  source_id    text,
  error        text not null,
  at           timestamptz not null default now()
);
alter table public.seat_case_memory_miss enable row level security;
drop policy if exists seat_case_memory_miss_service_role_only on public.seat_case_memory_miss;
create policy seat_case_memory_miss_service_role_only on public.seat_case_memory_miss
  as permissive for all to public using (false) with check (false);
revoke all on public.seat_case_memory_miss from anon, authenticated;
revoke all on sequence public.seat_case_memory_miss_id_seq from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- MASKING. Deterministic: patterns for contact shapes, plus every identity string the source row
-- itself names (p_known). Two characters or fewer are ignored so "Al" cannot eat every word.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_case_mask(p_text text, p_known text[] default '{}')
returns text
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v text := coalesce(p_text, '');
  k text;
  m text[];
begin
  if p_text is null then return null; end if;
  -- Shapes first, so a name inside an address cannot leave "[party]@domain" behind.
  v := regexp_replace(v, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', '[email]', 'g');
  v := regexp_replace(v, 'https?://\S+|www\.\S+', '[link]', 'gi');
  -- A phone is a run of 9+ digits with separators; a date (2026-09-01) or an amount is not.
  for m in select regexp_matches(v, '\+?\d[\d\s\-().]{6,}\d', 'g') loop
    if length(regexp_replace(m[1], '\D', '', 'g')) >= 9 then
      v := replace(v, m[1], '[phone]');
    end if;
  end loop;
  -- Each identity string the row names, whole, longest first.
  for k in select btrim(x) from unnest(coalesce(p_known, '{}')) x
            where length(btrim(x)) >= 3 order by length(btrim(x)) desc loop
    v := regexp_replace(v, regexp_replace(k, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'), '[party]', 'gi');
  end loop;
  -- Then each WORD of a name (a first name alone is still a name), whole words only so "Ali" can
  -- never eat "quality"; words with no letter in them are left to the phone rule above.
  for k in select distinct btrim(t) from unnest(coalesce(p_known, '{}')) x, regexp_split_to_table(x, '\s+') t
            where x !~ '@' and length(btrim(t)) >= 3 and btrim(t) ~ '[[:alpha:]]' loop
    v := regexp_replace(v, '\m' || regexp_replace(k, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '\M', '[party]', 'gi');
  end loop;
  return nullif(left(btrim(v), 2000), '');
end
$fn$;
revoke execute on function public.fn_case_mask(text, text[]) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- THE ONE WRITER. Upsert on (source_table, source_id). The embedding is cleared only when the masked
-- situation changed; a case that finalises later keeps its vector and gains its outcome.
-- finalised never goes back to false from here: a reopened case is a correction (fn_case_correct).
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_case_remember(
  p_seat text, p_case_kind text, p_source_table text, p_source_id text,
  p_trade text, p_situation text, p_decision text, p_reasoning text, p_outcome text,
  p_finalised boolean, p_known text[] default '{}', p_opened_at timestamptz default null,
  p_lesson text default null)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare
  v_sit text := public.fn_case_mask(p_situation, p_known);
  v_id  bigint;
begin
  if coalesce(v_sit, '') = '' then return null; end if;
  insert into public.seat_case_memory as m
    (seat, case_kind, source_table, source_id, trade, situation, decision, reasoning, outcome,
     finalised, finalised_at, lessons, opened_at)
  values (p_seat, p_case_kind, p_source_table, p_source_id, nullif(lower(btrim(p_trade)), ''), v_sit,
          public.fn_case_mask(p_decision, p_known), public.fn_case_mask(p_reasoning, p_known),
          public.fn_case_mask(p_outcome, p_known), coalesce(p_finalised, false),
          case when p_finalised then now() end,
          case when coalesce(p_lesson, '') <> '' then array[public.fn_case_mask(p_lesson, p_known)] else '{}' end,
          coalesce(p_opened_at, now()))
  on conflict (source_table, source_id) do update set
    trade        = coalesce(excluded.trade, m.trade),
    situation    = excluded.situation,
    decision     = coalesce(excluded.decision, m.decision),
    reasoning    = coalesce(excluded.reasoning, m.reasoning),
    outcome      = coalesce(excluded.outcome, m.outcome),
    finalised    = m.finalised or excluded.finalised,
    finalised_at = coalesce(m.finalised_at, excluded.finalised_at),
    lessons      = case when coalesce(p_lesson, '') <> '' and not (excluded.lessons[1] = any (m.lessons))
                        then m.lessons || excluded.lessons else m.lessons end,
    embedding    = case when m.situation is distinct from excluded.situation then null else m.embedding end,
    updated_at   = now()
  returning id into v_id;
  return v_id;
end
$fn$;
revoke execute on function public.fn_case_remember(text, text, text, text, text, text, text, text, text, boolean, text[], timestamptz, text) from public, anon, authenticated;

-- CORRECTIONS BECOME LESSONS. The founder, the CEO, a reviewer seat or the owning seat itself.
create or replace function public.fn_case_correct(p_source_table text, p_source_id text, p_by text, p_correction text)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint; v_c text := public.fn_case_mask(p_correction);
begin
  if coalesce(v_c, '') = '' then return null; end if;
  update public.seat_case_memory m
     set corrected_by = p_by, correction = v_c,
         lessons = case when ('Corrected by ' || p_by || ': ' || v_c) = any (m.lessons) then m.lessons
                        else m.lessons || ('Corrected by ' || p_by || ': ' || v_c) end,
         updated_at = now()
   where m.source_table = p_source_table and m.source_id = p_source_id
  returning id into v_id;
  return v_id;
end
$fn$;
revoke execute on function public.fn_case_correct(text, text, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- RECALL. Before a seat decides. Floor on raw similarity; the correction bonus only reorders.
-- A case from another seat is returned masked and WITHOUT its source pointer.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_case_recall(
  p_seat text, p_embedding vector(384), p_trade text default null, p_k integer default 5,
  p_case_kind text default null, p_other_seats boolean default true, p_floor real default 0.84,
  p_exclude_source_table text default null, p_exclude_source_id text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
declare
  v_trade text := nullif(lower(btrim(p_trade)), '');
  v_out   jsonb;
begin
  if p_embedding is null then
    return jsonb_build_object('ok', false, 'reason', 'no_embedding', 'cases', '[]'::jsonb);
  end if;
  -- EXACT UNTIL 20,000 ROWS. An HNSW scan with a WHERE clause can return fewer than k rows that
  -- clear the floor; below this size the exact scan costs milliseconds and misses nothing.
  if (select count(*) from public.seat_case_memory where embedding is not null) < 20000 then
    perform set_config('enable_indexscan', 'off', true);
  end if;
  with c as (
    select m.*, (1 - (m.embedding <=> p_embedding))::real as sim
      from public.seat_case_memory m
     where m.embedding is not null
       and (p_other_seats or m.seat = p_seat)
       and (p_case_kind is null or m.case_kind = p_case_kind)
       and (v_trade is null or m.trade is null or m.trade = v_trade)
       -- IS DISTINCT, not "not (a = b)": with no exclusion given, "not (x = null)" is null and would
       -- silently drop every row (it did, on the first probe run).
       and (m.source_table, m.source_id) is distinct from (p_exclude_source_table, p_exclude_source_id)
  ), top as (
    select * from c where sim >= coalesce(p_floor, 0.84)
     order by sim + case when correction is not null then 0.05 else 0 end desc
     limit greatest(1, least(coalesce(p_k, 5), 20))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'case_id', t.id, 'seat', t.seat, 'case_kind', t.case_kind, 'trade', t.trade,
           'situation', t.situation, 'decision', t.decision, 'reasoning', t.reasoning,
           'outcome', t.outcome, 'finalised', t.finalised, 'finalised_at', t.finalised_at,
           'lessons', to_jsonb(t.lessons), 'correction', t.correction, 'corrected_by', t.corrected_by,
           'similarity', round(t.sim::numeric, 3), 'opened_at', t.opened_at,
           'source', case when t.seat = p_seat then t.source_table || ':' || t.source_id end)
         order by t.sim + case when t.correction is not null then 0.05 else 0 end desc), '[]'::jsonb)
    into v_out from top t;
  return jsonb_build_object('ok', true, 'floor', coalesce(p_floor, 0.84), 'cases', v_out,
                            'finalised_precedent', exists (select 1 from jsonb_array_elements(v_out) e where (e->>'finalised')::boolean));
end
$fn$;
revoke execute on function public.fn_case_recall(text, vector, text, integer, text, boolean, real, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- THE EMBED QUEUE. Claim with a three-minute lease (same discipline as fn_kb_embed_dispatch);
-- write back only if the situation is still the one that was embedded.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_case_embed_claim(p_limit integer default 8)
returns table (id bigint, text text, hash text)
language sql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with pick as (
    select m.id from public.seat_case_memory m
     where m.embedding is null
       and (m.embed_claimed_at is null or m.embed_claimed_at < now() - interval '3 minutes')
     order by m.id
     limit greatest(1, least(coalesce(p_limit, 8), 200))
     for update skip locked
  )
  update public.seat_case_memory m set embed_claimed_at = now()
    from pick where m.id = pick.id
  returning m.id, left(m.situation, 1200), md5(m.situation);
$fn$;
revoke execute on function public.fn_case_embed_claim(integer) from public, anon, authenticated;

create or replace function public.fn_case_embed_write(p_id bigint, p_embedding vector(384), p_hash text)
returns boolean
language sql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $fn$
  with u as (
    update public.seat_case_memory m
       set embedding = p_embedding, embedded_hash = p_hash, embed_claimed_at = null
     where m.id = p_id and md5(m.situation) = p_hash
    returning 1)
  select exists (select 1 from u);
$fn$;
revoke execute on function public.fn_case_embed_write(bigint, vector, text) from public, anon, authenticated;

-- ON THE HEARTBEAT: resilience_ping's caseMemory step (caseMemoryEmbedTick) drains the queue.
insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('caseMemory', interval '15 minutes', 4000, 'plan', 0,
   'seat_case_memory embed queue: up to 8 cases per tick embedded with the in-runtime gte-small session (free, not OpenRouter) so fn_case_recall can find them',
   'it_engineer')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
                                rank = excluded.rank, note = excluded.note, owner_seat = excluded.owner_seat;

-- ---------------------------------------------------------------------------------------------
-- WRITE-BACK TRIGGERS. One function per source, each the whole mapping for that seat's case, each
-- wrapped so a mapping error is recorded in seat_case_memory_miss and never fails the source write.
-- ---------------------------------------------------------------------------------------------

-- sales_engineer: an inquiry, from creation to its end state.
create or replace function public.fn_case_from_inquiry(n public.inquiries, o public.inquiries default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_known text[]; v_fin boolean;
begin
  begin
    select array[c.full_name, c.email, c.phone, c.whatsapp_phone] into v_known
      from public.customers c where c.id = n.customer_id;
    v_fin := n.completed_at is not null or n.outcome is not null or n.lost_reason is not null
             or n.status in ('revealed','expired','cancelled','canceled','closed','won','lost','completed');
    perform public.fn_case_remember('sales_engineer', 'inquiry', 'inquiries', n.id::text,
      coalesce(n.trades[1], n.category),
      concat_ws(' | ', coalesce(n.summary_masked, n.summary), left(coalesce(n.raw_input_masked, n.raw_input), 600),
                'category: ' || n.category, 'emirate: ' || n.emirate, 'scope: ' || n.scope_type),
      concat_ws('; ', 'status ' || n.status, 'stage ' || n.pipeline_stage,
                case when n.hired_supplier_id is not null then 'supplier hired' end),
      null,
      concat_ws('; ', n.outcome, 'lost: ' || n.lost_reason),
      v_fin, coalesce(v_known, '{}'), n.created_at,
      case when n.lost_reason is not null then 'Lost because: ' || n.lost_reason end);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('inquiries', n.id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_inquiry(public.inquiries, public.inquiries) from public, anon, authenticated;
create or replace function public.trg_case_memory_inquiry()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_inquiry(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_inquiry() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.inquiries;
create trigger z90_case_memory after insert or update of status, outcome, lost_reason, completed_at, pipeline_stage, hired_supplier_id, summary_masked
  on public.inquiries for each row execute function public.trg_case_memory_inquiry();

-- customer_support: a support case, closed with its reason.
create or replace function public.fn_case_from_support_case(n public.support_case, o public.support_case default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_case_remember('customer_support', 'support_case', 'support_case', n.case_id::text, null,
      concat_ws(' | ', n.subject, n.party_kind || ' party'),
      'state ' || n.state, null, n.close_reason,
      n.state = 'closed' or n.closed_at is not null, array[n.party_id], n.opened_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('support_case', n.case_id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_support_case(public.support_case, public.support_case) from public, anon, authenticated;
create or replace function public.trg_case_memory_support_case()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_support_case(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_support_case() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.support_case;
create trigger z90_case_memory after insert or update of state, closed_at, close_reason
  on public.support_case for each row execute function public.trg_case_memory_support_case();

-- customer_support: a complaint, finalised by its final response.
create or replace function public.fn_case_from_complaint(n public.complaint_tickets, o public.complaint_tickets default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_case_remember('customer_support', 'complaint', 'complaint_tickets', n.id::text, null,
      n.message, 'status ' || n.status, n.decision_ref, n.final_response,
      n.final_response_at is not null, array[n.name, n.email], n.created_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('complaint_tickets', n.id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_complaint(public.complaint_tickets, public.complaint_tickets) from public, anon, authenticated;
create or replace function public.trg_case_memory_complaint()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_complaint(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_complaint() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.complaint_tickets;
create trigger z90_case_memory after insert or update of status, final_response, final_response_at
  on public.complaint_tickets for each row execute function public.trg_case_memory_complaint();

-- ceo: the decision log (every row is a decision taken), the decision record, and approvals.
create or replace function public.fn_case_from_ceo_decision_log(n public.ceo_decision_log, o public.ceo_decision_log default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_case_remember('ceo', 'decision', 'ceo_decision_log', n.id::text, null,
      concat_ws(' | ', n.decision_key, n.reading_before), n.the_decision, null,
      concat_ws('; ', n.outcome, 'after: ' || n.reading_after, 'founder: ' || n.founder_answer),
      n.outcome is not null, '{}', n.decided_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('ceo_decision_log', n.id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_ceo_decision_log(public.ceo_decision_log, public.ceo_decision_log) from public, anon, authenticated;
create or replace function public.trg_case_memory_ceo_decision_log()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_ceo_decision_log(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_ceo_decision_log() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.ceo_decision_log;
create trigger z90_case_memory after insert or update of outcome, reading_after, founder_answer
  on public.ceo_decision_log for each row execute function public.trg_case_memory_ceo_decision_log();

create or replace function public.fn_case_from_decision_record(n public.decision_record, o public.decision_record default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_case_remember('ceo', 'decision_record', 'decision_record', n.id::text, null,
      concat_ws(' | ', n.problem, left(n.context, 600)), n.recommendation,
      concat_ws('; ', 'expected: ' || n.expected_outcome, 'risks: ' || n.risks),
      concat_ws('; ', 'status ' || n.status, n.actual_outcome),
      n.actual_outcome is not null or n.status in ('executed','obsolete','rejected','reversed'),
      '{}', n.created_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('decision_record', n.id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_decision_record(public.decision_record, public.decision_record) from public, anon, authenticated;
create or replace function public.trg_case_memory_decision_record()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_decision_record(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_decision_record() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.decision_record;
create trigger z90_case_memory after insert or update of status, actual_outcome, recommendation
  on public.decision_record for each row execute function public.trg_case_memory_decision_record();

-- ceo_approval is append-only: an approval or refusal IS the final decision. A refusal is also a
-- correction of the seat that proposed it (refund -> refund_case, publication -> marketing_campaign).
create or replace function public.fn_case_from_ceo_approval(n public.ceo_approval, o public.ceo_approval default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_case_remember('ceo', 'approval:' || n.subject_kind, 'ceo_approval', n.decision_id::text, null,
      concat_ws(' | ', n.subject_kind || ' ' || n.decision || ': ' || n.rationale, 'AED ' || n.amount_aed), n.decision,
      n.rationale, n.decision, true, '{}', n.decided_at, null);
    if n.decision = 'refused' then
      perform public.fn_case_correct(
        case n.subject_kind when 'refund' then 'refund_case' when 'publication' then 'marketing_campaign' end,
        n.subject_id, 'ceo', 'Refused by the CEO: ' || n.rationale);
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('ceo_approval', n.decision_id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_ceo_approval(public.ceo_approval, public.ceo_approval) from public, anon, authenticated;
create or replace function public.trg_case_memory_ceo_approval()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_ceo_approval(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_ceo_approval() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.ceo_approval;
create trigger z90_case_memory after insert on public.ceo_approval
  for each row execute function public.trg_case_memory_ceo_approval();

-- accountant: a refund case, finalised by its decision and settlement.
create or replace function public.fn_case_from_refund_case(n public.refund_case, o public.refund_case default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_case_remember('accountant', 'refund', 'refund_case', n.refund_id::text, null,
      concat_ws(' | ', n.requested_reason, 'AED ' || n.amount_aed, 'eligibility: ' || n.eligibility,
                n.eligibility_reason),
      concat_ws('; ', n.decision, 'state ' || n.state), n.decision_rationale,
      concat_ws('; ', n.state, n.provider_status, n.failure_reason),
      n.state in ('ceo_declined','succeeded','reconciled','communicated','canceled','ineligible'),
      array[n.destination_ref], n.created_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('refund_case', n.refund_id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_refund_case(public.refund_case, public.refund_case) from public, anon, authenticated;
create or replace function public.trg_case_memory_refund_case()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_refund_case(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_refund_case() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.refund_case;
create trigger z90_case_memory after insert or update of state, decision, decision_rationale
  on public.refund_case for each row execute function public.trg_case_memory_refund_case();

-- accountant: how an expense was classified. A change of category IS a correction.
create or replace function public.fn_case_from_expense(n public.expense_entries, o public.expense_entries default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_case_remember('accountant', 'expense_classification', 'expense_entries', n.id::text, null,
      concat_ws(' | ', 'vendor ' || n.vendor, n.currency || ' ' || n.amount, n.doc_kind, n.note, n.doc_note),
      'classified as ' || coalesce(n.category, 'unclassified'), null, n.category,
      n.category is not null, '{}', n.created_at, null);
    if o.category is not null and n.category is distinct from o.category then
      perform public.fn_case_correct('expense_entries', n.id::text, 'accountant',
        'Re-classified from ' || o.category || ' to ' || coalesce(n.category, 'unclassified'));
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('expense_entries', n.id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_expense(public.expense_entries, public.expense_entries) from public, anon, authenticated;
create or replace function public.trg_case_memory_expense()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_expense(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_expense() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.expense_entries;
create trigger z90_case_memory after insert or update of category, vendor, note
  on public.expense_entries for each row execute function public.trg_case_memory_expense();

-- it_engineer: a finding, finalised when closed with a fix. Reopening it is a correction.
create or replace function public.fn_case_from_it_finding(n public.it_engineer_finding, o public.it_engineer_finding default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_case_remember('it_engineer', 'it_finding', 'it_engineer_finding', n.issue_key, null,
      concat_ws(' | ', n.title, 'where: ' || n.where_it_is, 'blast: ' || n.blast),
      case when n.closed_at is not null then 'closed' else 'open' end,
      array_to_string(n.ruled_out, '; '), n.close_note,
      n.closed_at is not null, '{}', n.started_at,
      case when n.closed_at is not null and n.close_note is not null then 'Fixed by: ' || n.close_note end);
    if o.closed_at is not null and n.closed_at is null then
      perform public.fn_case_correct('it_engineer_finding', n.issue_key, 'it_engineer',
        'Reopened: the earlier fix (' || coalesce(o.close_note, 'no note') || ') did not hold');
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('it_engineer_finding', n.issue_key, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_it_finding(public.it_engineer_finding, public.it_engineer_finding) from public, anon, authenticated;
create or replace function public.trg_case_memory_it_finding()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_it_finding(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_it_finding() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.it_engineer_finding;
create trigger z90_case_memory after insert or update of closed_at, close_note, title
  on public.it_engineer_finding for each row execute function public.trg_case_memory_it_finding();

-- marketing: a month's plan, finalised by the founder's approval.
create or replace function public.fn_case_from_campaign(n public.marketing_campaign, o public.marketing_campaign default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    if not coalesce(n.is_demo, false) then
      perform public.fn_case_remember('marketing', 'campaign_plan', 'marketing_campaign', n.id::text, null,
        concat_ws(' | ', n.title, 'theme: ' || n.theme, 'month ' || n.month, 'spend: ' || n.spend_policy),
        case when n.approved_at is not null then 'plan approved by ' || coalesce(n.approved_by, 'the founder') else 'plan sent for approval' end,
        null, case when n.approved_at is not null then 'approved' end,
        n.approved_at is not null, '{}', n.created_at, null);
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('marketing_campaign', n.id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_campaign(public.marketing_campaign, public.marketing_campaign) from public, anon, authenticated;
create or replace function public.trg_case_memory_campaign()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_campaign(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_campaign() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.marketing_campaign;
create trigger z90_case_memory after insert or update of approved_at, theme, title
  on public.marketing_campaign for each row execute function public.trg_case_memory_campaign();

-- marketing: a reply to a comment or DM, finalised when its outcome is known. The situation is the
-- message it answered, masked.
create or replace function public.fn_case_from_social_reply(n public.social_message, o public.social_message default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_asked text; v_author text;
begin
  begin
    if n.direction = 'out' and n.outcome is not null then
      select m.body, m.author into v_asked, v_author from public.social_message m where m.id = n.in_reply_to;
      perform public.fn_case_remember('marketing', 'social_reply', 'social_message', n.id::text, null,
        concat_ws(' | ', coalesce(v_asked, n.body), n.platform || ' ' || n.channel),
        coalesce(n.reply_kind, 'reply') || ': ' || left(n.body, 500), n.reply_key, n.outcome,
        true, array[v_author, n.author], n.occurred_at, null);
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('social_message', n.id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_social_reply(public.social_message, public.social_message) from public, anon, authenticated;
create or replace function public.trg_case_memory_social_reply()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_social_reply(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_social_reply() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.social_message;
create trigger z90_case_memory after insert or update of outcome
  on public.social_message for each row execute function public.trg_case_memory_social_reply();

-- sales_engineer: a spec the market could not meet exactly, the alternatives offered, and the answer.
create or replace function public.fn_case_from_spec_offer(n public.spec_alternative_offer, o public.spec_alternative_offer default null)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_case_remember('sales_engineer', 'spec_offer', 'spec_alternative_offer', n.id::text, null,
      concat_ws(' | ', 'no exact match for ' || n.label_en || ' = ' || n.requested, 'item: ' || n.item,
                'alternatives: ' || left(n.alternatives::text, 400)),
      'offered ' || jsonb_array_length(case when jsonb_typeof(n.alternatives) = 'array' then n.alternatives else '[]'::jsonb end) || ' alternative(s)',
      null, concat_ws('; ', n.state, 'accepted: ' || n.accepted_value, n.closed_reason),
      n.state <> 'open', '{}', n.opened_at, null);
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error) values ('spec_alternative_offer', n.id::text, sqlerrm);
  end;
  return true;
end $fn$;
revoke execute on function public.fn_case_from_spec_offer(public.spec_alternative_offer, public.spec_alternative_offer) from public, anon, authenticated;
create or replace function public.trg_case_memory_spec_offer()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  perform public.fn_case_from_spec_offer(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $fn$;
revoke execute on function public.trg_case_memory_spec_offer() from public, anon, authenticated;
drop trigger if exists z90_case_memory on public.spec_alternative_offer;
create trigger z90_case_memory after insert or update of state, accepted_value
  on public.spec_alternative_offer for each row execute function public.trg_case_memory_spec_offer();

-- ---------------------------------------------------------------------------------------------
-- BACKFILL. Every existing row through the same mapping the triggers use, by SELECT — never by a
-- no-op UPDATE, which would fire the sources' other triggers (support_case's AFTER UPDATE OF state
-- tells the reporter the case closed; inquiries' version_rfq writes a new RFQ version). The 329
-- closed IT findings are the one seat with real history on day one. Idempotent (upsert on the key).
-- ---------------------------------------------------------------------------------------------
select count(public.fn_case_from_it_finding(t)) from public.it_engineer_finding t;
select count(public.fn_case_from_inquiry(t)) from public.inquiries t;
select count(public.fn_case_from_spec_offer(t)) from public.spec_alternative_offer t;
select count(public.fn_case_from_support_case(t)) from public.support_case t;
select count(public.fn_case_from_complaint(t)) from public.complaint_tickets t;
select count(public.fn_case_from_ceo_decision_log(t)) from public.ceo_decision_log t;
select count(public.fn_case_from_decision_record(t)) from public.decision_record t;
select count(public.fn_case_from_ceo_approval(t)) from public.ceo_approval t;
select count(public.fn_case_from_refund_case(t)) from public.refund_case t;
select count(public.fn_case_from_expense(t)) from public.expense_entries t;
select count(public.fn_case_from_campaign(t)) from public.marketing_campaign t;
select count(public.fn_case_from_social_reply(t)) from public.social_message t where t.direction = 'out' and t.outcome is not null;

select 'seat_case_memory rows: ' || count(*) || ', misses: ' || (select count(*) from public.seat_case_memory_miss) as verdict
  from public.seat_case_memory;
