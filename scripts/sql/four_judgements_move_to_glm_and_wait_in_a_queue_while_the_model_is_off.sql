-- FOUR JUDGEMENTS MOVE TO GLM 5.3 FLASH, AND WAIT IN A QUEUE - NEVER WORD-MATCHED - WHILE THE MODEL IS OFF.
-- Seat: it_engineer (the queue), for the sales_engineer (quote spec match, repeat requests, supplier trade
-- words) and the accountant/customer_support inbox (mail from unknown senders). 24 Sep 2026.
--
-- THE FOUNDER'S APPROVAL (24 Sep 2026): four judgements move from code to GLM 5.3 Flash, the cheap internal class
-- (model_policy routine_employee_reasoning -> z-ai/glm-5.3-flash, $0.15 / $0.50 per 1M tokens, list price, checked
-- the same day: it is not a promotion):
--   1. quote_spec_match       - each quoted value the technical comparison marks as differing (≠) from the customer's
--                               requested spec is judged: a genuine mismatch (SS304 quoted for SS316) or not. Exact
--                               matches never reach the model (line_specs/compare.ts decides ✓ by code).
--   2. repeat_request         - pg_trgm stays first (trg_inquiry_enrich, 0.5). Only a request BELOW that similarity,
--                               from the same customer, in the same category, within 30 minutes, is judged - which
--                               is where English vs Arabic and reworded repeats land.
--   3. supplier_trade_words   - a supplier's own words that no exact taxonomy trade holds (taxonomy_trade_proposal,
--                               status pending) are mapped to EXACT taxonomy_trade codes or none. One exact trade is
--                               OFFERED to the supplier (status map_offered - the supplier confirms, nothing is
--                               mapped silently); several or none leave the row pending with the question to ask.
--   4. unknown_sender_mail    - inbound mail from a sender who is no lead, customer, admin or expense forwarder.
--                               Known senders keep their existing path; only an unknown sender is judged on GLM.
--
-- HOW IT WORKS. Every judgement is a row in public.glm_judgement. The caller enqueues it
-- (fn_glm_judgement_enqueue, idempotent on (kind, subject_key)), may judge it inline, and resilience_ping drains
-- the rest (step 'glm_judgements').
-- NO DAILY CAP, ON PURPOSE. The founder, 24 Sep 2026 (founder_instruction 987): no caps on LLM spend; idle spend
-- stays low because the code is correct. An earlier draft of this PR limited each kind per day; that was removed.
-- What bounds the volume is correctness: a judgement is enqueued once per (kind, subject_key); only the cells, mail
-- and requests that code could not decide reach it; and three failed readings end a row (no infinite retry).
-- HELD (the model hold, a model that failed or answered outside the format): the row stays queued and is
-- tried again - never answered by a word list. Three failed readings mark it failed and the seat's existing manual
-- path owns it (it is exactly what happens today).
--
-- COST: one judgement = one think() (a decompose and a synthesis call on GLM), about AED 0.0045. At 0 customers and
-- 0 suppliers none of the four has a subject except unknown-sender mail; the idle rate is in the PR (IDLE_PROOF).
--
-- Pending: scripts/sql/pending/four_judgements_move_to_glm_and_wait_in_a_queue_while_the_model_is_off.txt
-- Prevented by: scripts/checks/four_glm_judgements_run_on_glm_and_never_word_match.test.mjs and
--               supabase/functions/_shared/glm_judgements.test.ts

-- ── the queue ───────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.glm_judgement (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('quote_spec_match', 'repeat_request', 'supplier_trade_words', 'unknown_sender_mail')),
  subject_key text not null check (btrim(subject_key) <> ''),
  input jsonb not null,
  status text not null default 'queued' check (status in ('queued', 'done', 'failed', 'superseded')),
  result jsonb,
  model text,
  attempts integer not null default 0,
  last_error text,
  leased_until timestamptz,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  unique (kind, subject_key)
);
create index if not exists glm_judgement_due_idx on public.glm_judgement (id) where status = 'queued';
alter table public.glm_judgement enable row level security;
drop policy if exists glm_judgement_service_role_only on public.glm_judgement;
create policy glm_judgement_service_role_only on public.glm_judgement as permissive for all to public using (false) with check (false);
revoke all on public.glm_judgement from anon, authenticated;

-- ── enqueue / due / defer / resolve ─────────────────────────────────────────────────────────────────────
create or replace function public.fn_glm_judgement_enqueue(p_kind text, p_subject_key text, p_input jsonb)
returns bigint language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  insert into public.glm_judgement (kind, subject_key, input) values (p_kind, p_subject_key, p_input)
  on conflict (kind, subject_key) do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.glm_judgement where kind = p_kind and subject_key = p_subject_key; end if;
  return v_id;
end $fn$;
revoke execute on function public.fn_glm_judgement_enqueue(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.fn_glm_judgement_enqueue(text, text, jsonb) to service_role;

-- Leases queued rows for 5 minutes so two drainers never judge (and pay for) the same row.
create or replace function public.fn_glm_judgement_due(p_limit integer default 5, p_ids bigint[] default null)
returns setof public.glm_judgement language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  return query
  update public.glm_judgement g set leased_until = now() + interval '5 minutes'
   where g.id in (select q.id from public.glm_judgement q
                   where q.status = 'queued' and (q.leased_until is null or q.leased_until < now())
                     and (p_ids is null or q.id = any(p_ids))
                   order by q.id limit greatest(1, least(coalesce(p_limit, 5), 50))
                   for update skip locked)
  returning g.*;
end $fn$;
revoke execute on function public.fn_glm_judgement_due(integer, bigint[]) from public, anon, authenticated;
grant execute on function public.fn_glm_judgement_due(integer, bigint[]) to service_role;

-- Not judged this time. p_counts = a failed reading (counts toward the three); the model hold does not.
create or replace function public.fn_glm_judgement_defer(p_id bigint, p_error text, p_counts boolean)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare g public.glm_judgement;
begin
  update public.glm_judgement
     set leased_until = null, last_error = left(p_error, 500),
         attempts = attempts + case when p_counts then 1 else 0 end,
         status = case when p_counts and attempts + 1 >= 3 then 'failed' else status end,
         decided_at = case when p_counts and attempts + 1 >= 3 then now() else decided_at end
   where id = p_id and status = 'queued'
  returning * into g;
  if g.id is null or g.status <> 'failed' then return; end if;
  -- THE TERMINAL STATE HANDS EACH KIND BACK TO ITS OWNER (review of this PR): three failed readings never leave
  -- anything waiting on a judgement that will not come.
  if g.kind = 'unknown_sender_mail' then
    -- The mail leaves the 'glm_queued' mark (which email_triage skips) and goes to a person's review, unread.
    update public.inbound_messages set ai_category = 'other', ai_summary = 'Not read: GLM could not judge this mail after 3 tries.', triaged_at = now()
     where id = (g.input->>'message_id')::bigint and triaged_at is null;
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, target_table, target_id, detail)
    values ('email', 'inbound_review', 'pending', 'low',
            left('Inbox (unknown sender, unread): ' || coalesce(g.input->>'subject', '(no subject)'), 70),
            'GLM could not read this mail from an unknown sender after 3 tries. Read it and reply from the Inbox.',
            'inbound_messages', g.input->>'message_id',
            jsonb_build_object('from', g.input->>'from', 'glm_judgement_id', g.id, 'last_error', g.last_error));
  elsif g.kind = 'supplier_trade_words' then
    -- The proposal stays pending for the sales engineer (as before this PR), now saying why it was not offered.
    update public.taxonomy_trade_proposal set note = coalesce(note || ' ', '') || '[GLM could not map these words after 3 tries; decide by hand.]'
     where id = (g.input->>'proposal_id')::bigint and status = 'pending';
  end if;
  -- repeat_request: the inquiry simply stays unflagged (exactly its state before this PR; a flag only marks review).
  -- quote_spec_match: fn_quote_spec_mismatches reports the cells as 'unread', never as meeting the request.
end $fn$;
revoke execute on function public.fn_glm_judgement_defer(bigint, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_glm_judgement_defer(bigint, text, boolean) to service_role;

-- The answer and its one effect, in one transaction.
create or replace function public.fn_glm_judgement_resolve(p_id bigint, p_result jsonb, p_model text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare g public.glm_judgement; v_effect text := 'recorded'; v_codes text[]; v_n integer;
begin
  update public.glm_judgement set status = 'done', result = p_result, model = p_model, decided_at = now(), leased_until = null
   where id = p_id and status = 'queued' returning * into g;
  if g.id is null then return jsonb_build_object('ok', false, 'reason', 'not_queued'); end if;

  if g.kind = 'repeat_request' and p_result->>'verdict' = 'same' then
    update public.inquiries
       set plausibility = coalesce(plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true,
             'duplicate_of', g.input->>'earlier_id', 'duplicate_by', 'glm', 'glm_judgement_id', g.id)
     where id::text = g.input->>'inquiry_id'
       and not coalesce((plausibility->>'possible_duplicate')::boolean, false);
    v_effect := 'inquiry_flagged';

  elsif g.kind = 'supplier_trade_words' then
    -- Exact codes only: a code the taxonomy does not hold is never written (the caller already refused it; this
    -- is the second door).
    select array_agg(c) into v_codes from jsonb_array_elements_text(coalesce(p_result->'codes', '[]'::jsonb)) c
     where exists (select 1 from public.taxonomy_trade t where t.code = c and t.active);
    v_n := coalesce(array_length(v_codes, 1), 0);
    if v_n = 1 then
      update public.taxonomy_trade_proposal
         set status = 'map_offered', mapped_to = v_codes[1], decided_at = now(), decided_by = 'sales_engineer:glm',
             note = 'Offered to the supplier to confirm: ' || v_codes[1] || '. ' || coalesce(p_result->>'why', '')
       where id = (g.input->>'proposal_id')::bigint and status = 'pending';
      v_effect := 'map_offered';
    else
      update public.taxonomy_trade_proposal
         set note = case when v_n > 1
                      then 'Names several exact trades (' || array_to_string(v_codes, ', ') || '). Ask the supplier: '
                      else 'Names no exact taxonomy trade. Ask the supplier: ' end
                    || coalesce(nullif(p_result->>'ask', ''), 'which of our trades is this work?')
       where id = (g.input->>'proposal_id')::bigint and status = 'pending';
      v_effect := case when v_n > 1 then 'ask_several' else 'ask_none' end;
    end if;

  elsif g.kind = 'unknown_sender_mail' then
    update public.inbound_messages
       set ai_category = left(coalesce(p_result->>'category', 'other'), 40), ai_summary = left(p_result->>'summary', 500),
           triaged_at = now()
     where id = (g.input->>'message_id')::bigint and triaged_at is null;
    -- The same review item email_triage files for a drafted mail, so customer_support sees it; spam files nothing.
    if coalesce(p_result->>'category', 'other') <> 'spam' then
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, target_table, target_id, detail)
      values ('email', 'inbound_review', 'pending', 'low',
              left('Inbox (unknown sender): ' || coalesce(g.input->>'subject', '(no subject)'), 70) || ' - ' || coalesce(p_result->>'category', 'other'),
              'Unknown sender, read by GLM. Review and reply from the Inbox.', 'inbound_messages', g.input->>'message_id',
              jsonb_build_object('from', g.input->>'from', 'category', p_result->>'category', 'summary', p_result->>'summary', 'glm_judgement_id', g.id));
    end if;
    v_effect := 'mail_triaged';
  end if;
  return jsonb_build_object('ok', true, 'effect', v_effect);
end $fn$;
revoke execute on function public.fn_glm_judgement_resolve(bigint, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_glm_judgement_resolve(bigint, jsonb, text) to service_role;

-- A NEW COMPARISON SUPERSEDES THE OLD CELLS (review of this PR). quote_compare enqueues the quote's CURRENT ≠ cells
-- under content keys and then names them here; every other quote_spec_match row of that quote is superseded, so a
-- cell the supplier corrected (now ✓, or changed) stops counting. p_keep empty = no ≠ cell remains.
create or replace function public.fn_glm_quote_spec_supersede(p_quote_id text, p_keep text[])
returns integer language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare n integer;
begin
  update public.glm_judgement set status = 'superseded', leased_until = null, decided_at = now()
   where kind = 'quote_spec_match' and input->>'quote_id' = p_quote_id
     and status in ('queued', 'done', 'failed') and not (subject_key = any(coalesce(p_keep, '{}'::text[])));
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke execute on function public.fn_glm_quote_spec_supersede(text, text[]) from public, anon, authenticated;
grant execute on function public.fn_glm_quote_spec_supersede(text, text[]) to service_role;

-- What the comparison report and the quote review read: the judged ≠ cells of one quote.
create or replace function public.fn_quote_spec_mismatches(p_quote_id text)
returns jsonb language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'quote_id', p_quote_id,
    'pending', count(*) filter (where g.status = 'queued'),
    'unread', coalesce(sum(jsonb_array_length(g.input->'cells')) filter (where g.status = 'failed'), 0),
    'mismatches', coalesce(jsonb_agg(v) filter (where g.status = 'done' and (v->>'mismatch')::boolean), '[]'::jsonb),
    'meets', count(v) filter (where g.status = 'done' and not (v->>'mismatch')::boolean))
  from public.glm_judgement g
  left join lateral jsonb_array_elements(coalesce(g.result->'cells', '[]'::jsonb)) v on true
  where g.kind = 'quote_spec_match' and g.input->>'quote_id' = p_quote_id;
$fn$;
revoke execute on function public.fn_quote_spec_mismatches(text) from public, anon, authenticated;
grant execute on function public.fn_quote_spec_mismatches(text) to service_role;

-- The trades a supplier's words may map to: the live taxonomy, exact codes only.
create or replace function public.fn_glm_taxonomy_trades()
returns jsonb language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) order by sort, code), '[]'::jsonb)
    from public.taxonomy_trade where active;
$fn$;
revoke execute on function public.fn_glm_taxonomy_trades() from public, anon, authenticated;
grant execute on function public.fn_glm_taxonomy_trades() to service_role;

-- Who is a known sender: a lead (supplier), a customer, an admin or an expense forwarder. EXACT address
-- equality, lower-cased - an identity lookup, not reading meaning.
create or replace function public.fn_glm_sender_known(p_email text)
returns text language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare e text := lower(btrim(coalesce(p_email, '')));
begin
  if e = '' then return null; end if;
  if exists (select 1 from public.app_secrets s, unnest(string_to_array(lower(s.value), ',')) a
              where s.key in ('admin_emails', 'expense_forwarders', 'founder_email') and btrim(a) = e) then return 'staff'; end if;
  if exists (select 1 from public.customers where lower(email) = e) then return 'customer'; end if;
  if exists (select 1 from public.leads where lower(email) = e) then return 'supplier'; end if;
  return null;
end $fn$;
revoke execute on function public.fn_glm_sender_known(text) from public, anon, authenticated;
grant execute on function public.fn_glm_sender_known(text) to service_role;

-- ── enqueue triggers ────────────────────────────────────────────────────────────────────────────────────
-- 2. A repeat request below the trigram threshold: AFTER INSERT, so trg_inquiry_enrich (BEFORE, pg_trgm) has
-- already had its say; anything it flagged is never sent to the model.
create or replace function public.trg_glm_repeat_request_enqueue()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare p record;
begin
  if NEW.customer_id is null or btrim(coalesce(NEW.summary, '')) = ''
     or coalesce((NEW.plausibility->>'possible_duplicate')::boolean, false) then return NEW; end if;
  select i.id, i.summary into p from public.inquiries i
   where i.customer_id = NEW.customer_id and i.id <> NEW.id
     and i.created_at > now() - interval '30 minutes'
     and coalesce(i.category, '') = coalesce(NEW.category, '')
     and btrim(coalesce(i.summary, '')) <> ''
   order by i.created_at desc limit 1;
  if p.id is not null then
    perform public.fn_glm_judgement_enqueue('repeat_request', NEW.id::text,
      jsonb_build_object('inquiry_id', NEW.id, 'earlier_id', p.id, 'earlier', left(p.summary, 2000), 'later', left(NEW.summary, 2000),
                         'category', NEW.category));
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_glm_repeat_request_enqueue() from public, anon, authenticated;
drop trigger if exists z20_glm_repeat_request_enqueue on public.inquiries;
create trigger z20_glm_repeat_request_enqueue after insert on public.inquiries
  for each row execute function public.trg_glm_repeat_request_enqueue();

-- 3. A supplier's words no exact trade holds.
create or replace function public.trg_glm_trade_words_enqueue()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if NEW.status = 'pending' then
    perform public.fn_glm_judgement_enqueue('supplier_trade_words', NEW.id::text,
      jsonb_build_object('proposal_id', NEW.id, 'supplier_id', NEW.supplier_id,
                         'words', coalesce(NEW.label_en, '') || case when NEW.label_ar is not null then ' / ' || NEW.label_ar else '' end));
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_glm_trade_words_enqueue() from public, anon, authenticated;
drop trigger if exists z20_glm_trade_words_enqueue on public.taxonomy_trade_proposal;
create trigger z20_glm_trade_words_enqueue after insert on public.taxonomy_trade_proposal
  for each row execute function public.trg_glm_trade_words_enqueue();

-- ── probe: the chain end to end, on rows it creates and removes. This file carries DDL, so a failure is a
-- verdict ROW (apply_sql.mjs exits 3 on PROBE FAILED), never a raise that would roll the DDL back.
create temporary table glm_probe_verdict (verdict text) on commit drop;
do $probe$
declare v_id bigint; v_id2 bigint; v_before integer; v_res jsonb; v_n integer; v_fail text := null;
begin
  select count(*) into v_before from public.glm_judgement;
  v_id := public.fn_glm_judgement_enqueue('quote_spec_match', 'zz-probe:' || txid_current(), jsonb_build_object('quote_id', 'zz-probe-quote'));
  v_id2 := public.fn_glm_judgement_enqueue('quote_spec_match', 'zz-probe:' || txid_current(), '{}'::jsonb);
  if v_id is distinct from v_id2 then v_fail := 'enqueue is not idempotent'; end if;
  perform public.fn_glm_judgement_due(50, array[v_id]);
  perform public.fn_glm_judgement_defer(v_id, 'probe', true);
  v_res := public.fn_glm_judgement_resolve(v_id, jsonb_build_object('cells', jsonb_build_array(
             jsonb_build_object('line_no', 1, 'attr', 'grade', 'requested', 'SS316', 'quoted', 'SS304', 'mismatch', true))), 'probe');
  if v_fail is null and not coalesce((v_res->>'ok')::boolean, false) then v_fail := 'resolve refused a queued row: ' || v_res::text; end if;
  v_n := jsonb_array_length(public.fn_quote_spec_mismatches('zz-probe-quote')->'mismatches');
  if v_fail is null and v_n <> 1 then v_fail := 'fn_quote_spec_mismatches read ' || v_n || ' mismatches, expected 1'; end if;
  -- The terminal state: three failed readings mark the row failed and the report counts its cells unread.
  v_id2 := public.fn_glm_judgement_enqueue('quote_spec_match', 'zz-probe-fail:' || txid_current(), jsonb_build_object('quote_id', 'zz-probe-quote2', 'cells', jsonb_build_array(jsonb_build_object('line_no', 1))));
  perform public.fn_glm_judgement_defer(v_id2, 'probe', true); perform public.fn_glm_judgement_defer(v_id2, 'probe', true);
  perform public.fn_glm_judgement_defer(v_id2, 'probe', false);
  if v_fail is null and (select status from public.glm_judgement where id = v_id2) <> 'queued' then v_fail := 'a hold counted toward the three tries'; end if;
  perform public.fn_glm_judgement_defer(v_id2, 'probe', true);
  if v_fail is null and (select status from public.glm_judgement where id = v_id2) <> 'failed' then v_fail := 'three failed readings did not fail the row'; end if;
  if v_fail is null and (public.fn_quote_spec_mismatches('zz-probe-quote2')->>'unread')::int <> 1 then v_fail := 'a failed judgement is not reported unread'; end if;
  -- A corrected cell stops counting: a new run that no longer carries v_id's cells supersedes it.
  perform public.fn_glm_quote_spec_supersede('zz-probe-quote', array['zz-probe-other']);
  if v_fail is null and jsonb_array_length(public.fn_quote_spec_mismatches('zz-probe-quote')->'mismatches') <> 0 then v_fail := 'a superseded (corrected) cell still counts'; end if;
  delete from public.glm_judgement where id in (v_id, v_id2);
  if v_fail is null and (select count(*) from public.glm_judgement) <> v_before then v_fail := 'probe left rows behind'; end if;
  insert into glm_probe_verdict values (case when v_fail is null then 'PROBE OK' else 'PROBE FAILED: ' || v_fail end);
end $probe$;
select verdict from glm_probe_verdict;
