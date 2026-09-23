-- THE SALES ENGINEER REASONS INTAKE AND QUOTATIONS INSTEAD OF MATCHING WORDS — the SQL half of decision-point batch
-- B4 (supabase/functions/_shared/decision_points.json orders 31-38). Seat: sales_engineer. 23 Sep 2026,
-- founder_instruction 886-903 (ledger 890: no word matching anywhere).
--
-- WHY. The TypeScript side of this batch (supabase/functions/_shared/reasoned_intake.ts) moved eight decisions off
-- word lists onto think(). Under the model hold each of them is HELD — filed in reasoning_held_question — and three
-- of them have an effect that lives in the database when the hold lifts and the replay (resilience_ping ->
-- replayHeld -> fn_reason_held_resolve) reasons them. fn_reason_held_resolve calls
-- public.fn_reason_apply_<surface with '.' -> '__'>(p_id, p_result) when it exists
-- (scripts/sql/a_reasoned_answer_is_applied_by_its_own_surface.sql); this file defines them:
--   * service_rewrite.install            -> taxonomy_trade_service.install_work (NEW column; null = not reasoned).
--       service_rewrite.ts isInstallWork read "install|cabling|wiring|contract|..." off a service's label; it now
--       reads this column. Every trade with an unreasoned service is queued here (fn_service_install_queue), at
--       apply for the backlog and by trigger for a service added or renamed later. MEASURED 23 Sep 2026 on
--       production (read-only): 975 active services in 195 trades, at most 10 in one — so 195 reasonings, one per
--       trade, not 975. Nobody waits on these rows (a supply-only company is not withheld anything while a service
--       is unreasoned — isInstallWork treats null as not install work), so they are marked escalated at filing
--       and never become 195 pending items in the seat's queue at 48 hours.
--   * sales_engineer.brief_trades        -> inquiries.trades, ONLY while still empty. The matcher reasoned the
--       brief's trades instead of fn_norm_trades(brief); held, it matched nobody and said so (gap
--       trade_reasoning_held). The reasoned codes land on the inquiry, so its next match has them.
--   * supplier_api.quote_review_match    -> quote_reviews.working.boq_match (which quotation line prices which BOQ
--       line), ONLY when the working still has no match and still describes the same lines (working.boq_match_for =
--       subject.key, the fingerprint the flow asked with); working.pending_rereview = true, so the thread re-reviews
--       at the supplier's next step (quote_review_flow.ts load()).
--   * supplier_api.quote_review_reply    -> appended to quote_reviews.working.pending_reasoned {message_id, fields};
--       applied as corrections at the supplier's next step, and acknowledged in the thread.
--   * supplier_api.quote_review_question -> the reasoned ANSWER is posted in the thread as the sales engineer's
--       message (quote_review_messages, role sales_engineer, kind text). The supplier had the open points as the
--       answer while it was held.
-- The other surfaces of the batch (classify.urgency_emirate, interview.answers, intake_requirements.parse,
-- line_specs.options_derive_vat, drawing_boq.vocabulary) have no database effect: the intake re-reasons the whole
-- conversation on the customer's next turn and the quote form / drawing are re-read on the next submission, so
-- their replay is 'reasoned' and recorded only.
--
-- WHAT IT DOES NOT DO. It calls no model, lifts no hold and decides no meaning: every routine here writes a
-- decision think() already made. The only text it reads is OUR OWN format — the "Line N" label the flow wrote into
-- the listing it asked about, and a field key it built (boq_<n>).
--
-- Follows a_reasoned_answer_is_applied_by_its_own_surface.sql and a_held_question_never_expires_it_is_escalated_at_48_hours.sql.
-- Pending: scripts/sql/pending/the_sales_engineer_reasons_intake_and_quotations_instead_of_matching_words.txt.
-- Proved in one aborted transaction: scripts/checks/decision_points_are_reasoned.test.mjs (the B4 probe at its end).

-- ── 1. the reasoned column ─────────────────────────────────────────────────────────────────────────
alter table public.taxonomy_trade_service add column if not exists install_work boolean;
comment on column public.taxonomy_trade_service.install_work is
  'REASONED (decision point service_rewrite.install): the service is installation / contracting / after-sales work a supply-only company does not do. null = not reasoned yet (never withheld meanwhile). Written only by fn_reason_apply_service_rewrite__install.';

-- ── 2. the queue for a trade's services (mirrors reasoned_intake.ts serviceInstallRequest; keep the two equal) ──
create or replace function public.fn_service_install_queue(p_trade text)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_services jsonb; v_q text; v_req jsonb; v_key text; v_id bigint;
begin
  select jsonb_agg(jsonb_build_object('code', s.code, 'label_en', s.label_en) order by s.sort, s.code) into v_services
    from public.taxonomy_trade_service s where s.trade_code = p_trade and s.active;
  if v_services is null then return null; end if;
  v_q := format('Which of these %s services are work done on site or after sale?', p_trade);
  -- One row per trade AND service list: a service added later makes a new question, never a stale replay.
  v_key := 'service_install:' || p_trade || ':' || md5(v_services::text);
  v_req := jsonb_build_object(
    'seat', 'sales_engineer', 'surface', 'service_rewrite.install', 'question', v_q, 'dedupeKey', v_key,
    'subject', jsonb_build_object('trade_code', p_trade),
    'context', jsonb_build_object('audience', 'internal', 'conversation', jsonb_build_array(jsonb_build_object('role', 'seat',
      'text', (select string_agg((e->>'code') || ': ' || (e->>'label_en'), E'\n') from jsonb_array_elements(v_services) e)))),
    'decision', jsonb_build_object('name', 'install_work', 'fields', (select jsonb_agg(jsonb_build_object('key', e->>'code',
      'question', format('the words of "%s" that make it installation, contracting, maintenance, design or approvals work a company that only sells goods does not do (only if it is such work, and not a supply service)', e->>'label_en')))
      from jsonb_array_elements(v_services) e)));
  v_id := public.fn_reason_hold('sales_engineer', 'service_rewrite.install', v_q, v_req, '{}'::jsonb,
            jsonb_build_object('trade_code', p_trade), 'queued_at_write', v_key);
  -- Nobody is waiting on a catalogue reasoning: it is not escalated to the seat as a pending item at 48 hours.
  update public.reasoning_held_question set escalated_at = coalesce(escalated_at, now()) where id = v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_service_install_queue(text) from public, anon, authenticated;
grant execute on function public.fn_service_install_queue(text) to service_role;

create or replace function public.trg_service_install_queue()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- ponytail: a renamed service keeps its reasoned value; the upgrade is to null it on a label change.
  if new.active and new.install_work is null then perform public.fn_service_install_queue(new.trade_code); end if;
  return null;
end $fn$;
revoke execute on function public.trg_service_install_queue() from public, anon, authenticated;
drop trigger if exists trg_service_install_queue on public.taxonomy_trade_service;
create trigger trg_service_install_queue after insert or update of label_en, active on public.taxonomy_trade_service
  for each row execute function public.trg_service_install_queue();

-- the backlog: every trade with an unreasoned service, once
select public.fn_service_install_queue(t.trade_code)
  from (select distinct trade_code from public.taxonomy_trade_service where active and install_work is null) t;

-- ── 3. the replay's effects, one routine per surface ───────────────────────────────────────────────
create or replace function public.fn_reason_apply_service_rewrite__install(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_trade text; v_codes text[]; v_n integer;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_trade := r.subject->>'trade_code';
  if v_trade is null then return jsonb_build_object('applied', false, 'why', 'no trade on the held row'); end if;
  -- The codes the question was asked about are the request's own field keys (our format); a field the reasoning
  -- filled is install work, one it left out is supply.
  select array_agg(f->>'key') into v_codes from jsonb_array_elements(coalesce(r.request->'decision'->'fields', '[]'::jsonb)) f;
  update public.taxonomy_trade_service s
     set install_work = (p_result->'decision'->'fields') ? s.code
   where s.trade_code = v_trade and s.code = any(coalesce(v_codes, '{}'::text[]));
  get diagnostics v_n = row_count;
  return jsonb_build_object('trade_code', v_trade, 'services', v_n);
end $fn$;
revoke execute on function public.fn_reason_apply_service_rewrite__install(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_service_rewrite__install(bigint, jsonb) to service_role;

create or replace function public.fn_reason_apply_sales_engineer__brief_trades(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_codes text[]; v_n integer;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  -- Only the taxonomy's own codes (the field keys the question was built from) can land.
  select array_agg(k order by k) into v_codes
    from jsonb_object_keys(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) k
   where exists (select 1 from public.taxonomy_trade t where t.code = k and t.active);
  if coalesce(cardinality(v_codes), 0) = 0 or r.subject->>'inquiry_id' is null then
    return jsonb_build_object('applied', false, 'trades', coalesce(to_jsonb(v_codes), '[]'::jsonb));
  end if;
  update public.inquiries i set trades = v_codes
   where i.id::text = r.subject->>'inquiry_id' and coalesce(cardinality(i.trades), 0) = 0;
  get diagnostics v_n = row_count;
  return jsonb_build_object('inquiry_id', r.subject->>'inquiry_id', 'trades', to_jsonb(v_codes), 'written', v_n = 1);
end $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__brief_trades(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sales_engineer__brief_trades(bigint, jsonb) to service_role;

create or replace function public.fn_reason_apply_supplier_api__quote_review_match(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_match jsonb := '{}'::jsonb; v_used int[] := '{}'; f record; v_n int; v_j int; v_rows integer;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  -- FORMAT only: the key is ours (boq_<n>), the value is the "Line <j>" label the flow wrote into the listing.
  for f in select key, value from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) order by key loop
    v_n := (substring(f.key from '^boq_(\d+)$'))::int;
    v_j := coalesce((substring(f.value->>'value' from '^\s*[Ll]ine\s+(\d+)'))::int, (substring(f.value->>'evidence' from '^\s*[Ll]ine\s+(\d+)'))::int);
    if v_n is not null and v_j is not null and not (v_j = any(v_used)) then v_match := v_match || jsonb_build_object(v_n::text, v_j); v_used := v_used || v_j; end if;
  end loop;
  update public.quote_reviews q
     set working = q.working || jsonb_build_object('boq_match', v_match, 'pending_rereview', true), updated_at = now()
   where q.id::text = r.subject->>'review_id'
     and q.working is not null and q.working->>'boq_match_for' = r.subject->>'key'
     and coalesce(jsonb_typeof(q.working->'boq_match'), 'null') = 'null'
     and q.status not in ('submitted', 'closed');
  get diagnostics v_rows = row_count;
  return jsonb_build_object('review_id', r.subject->>'review_id', 'match', v_match, 'written', v_rows = 1);
end $fn$;
revoke execute on function public.fn_reason_apply_supplier_api__quote_review_match(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_supplier_api__quote_review_match(bigint, jsonb) to service_role;

create or replace function public.fn_reason_apply_supplier_api__quote_review_reply(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_rows integer;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  update public.quote_reviews q
     set working = q.working || jsonb_build_object('pending_reasoned',
           coalesce(q.working->'pending_reasoned', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
             'message_id', r.subject->>'message_id', 'fields', coalesce(p_result->'decision'->'fields', '{}'::jsonb)))),
         updated_at = now()
   where q.id::text = r.subject->>'review_id' and q.working is not null and q.status not in ('submitted', 'closed');
  get diagnostics v_rows = row_count;
  return jsonb_build_object('review_id', r.subject->>'review_id', 'message_id', r.subject->>'message_id', 'queued', v_rows = 1);
end $fn$;
revoke execute on function public.fn_reason_apply_supplier_api__quote_review_reply(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_supplier_api__quote_review_reply(bigint, jsonb) to service_role;

create or replace function public.fn_reason_apply_supplier_api__quote_review_question(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_answer text; v_msg uuid;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_answer := left(btrim(coalesce(p_result->>'answer', '')), 4000);
  if v_answer = '' then return jsonb_build_object('posted', false, 'why', 'no answer'); end if;
  insert into public.quote_review_messages (review_id, role, kind, body, body_ar, attachments)
  select q.id, 'sales_engineer', 'text', v_answer, v_answer, '[]'::jsonb
    from public.quote_reviews q
   where q.id::text = r.subject->>'review_id' and q.status not in ('submitted', 'closed')
  returning id into v_msg;
  return jsonb_build_object('review_id', r.subject->>'review_id', 'posted', v_msg is not null, 'message_id', v_msg);
end $fn$;
revoke execute on function public.fn_reason_apply_supplier_api__quote_review_question(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_supplier_api__quote_review_question(bigint, jsonb) to service_role;
