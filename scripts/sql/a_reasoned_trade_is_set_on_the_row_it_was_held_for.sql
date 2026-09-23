-- A REASONED TRADE IS SET ON THE ROW IT WAS HELD FOR — the replay effects of decision-point batch B2.
-- Seat: sales_engineer (the trade of an inquiry, the sector of a supplier lead). Written by it_engineer's batch
-- agent B2, 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
--
-- WHY. Two surfaces read a trade off word lists and wrote it on a row:
--   customer_api.keywords      create_inquiry's fallback: customer_api/keywords.ts detect() scored KW substrings
--                              and the best became inquiries.category;
--   inbound_email.infer_sector inbound_email inferSector(): a second KW map, the highest substring count became
--                              leads.sector ('door' in 'outdoor', 'sign' in 'design').
-- Both maps are deleted. The trade is now reasoned among the real category_specs rows, or 'none'
-- (_shared/reasoned_trades.ts tradeOfText). Under the model hold the row is written without it ('general' /
-- NULL) and the question waits in the sales engineer's queue; fn_reason_held_resolve
-- (a_reasoned_answer_is_applied_by_its_own_surface.sql) calls the routine below the moment it is reasoned.
--
-- WHAT. One routine per surface, public.fn_reason_apply_<surface>(p_id bigint, p_result jsonb) returns jsonb:
--   * sets the reasoned trade ONLY while the row still carries the placeholder ('general' / NULL): a trade a
--     person or a later reasoning already set is never overwritten;
--   * only an exact category_specs slug is written; 'none' (a new trade, or no job) writes nothing — there is
--     no nearest mapping;
--   * returns what it did (so the held row reads 'applied' with its effect).
-- Not done here, on purpose: an inquiry that went out as 'general' is not re-dispatched when its trade is
-- reasoned later — the category is corrected on the row for the sales engineer's own matching.
--
-- MEASURED 23 Sep 2026 (read from supabase/schema/full_schema.sql): inquiries.id uuid, inquiries.category text,
-- inquiries.keywords text[]; leads.id bigint identity, leads.sector text; category_specs.category text.
--
-- Pending: scripts/sql/pending/a_reasoned_trade_is_set_on_the_row_it_was_held_for.txt (apply after
-- a_reasoned_answer_is_applied_by_its_own_surface.sql). Proved in one aborted transaction:
-- scripts/checks/decision_points_are_reasoned.test.mjs.

create or replace function public.fn_reason_apply_customer_api__keywords(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_n integer := 0;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if not found or (r.subject->>'inquiry_id') is null then return null; end if;
  if v_choice is not null and exists (select 1 from public.category_specs cs where cs.category = v_choice) then
    update public.inquiries i
       set category = v_choice,
           keywords = array(select distinct k from unnest(array[v_choice] || coalesce(i.keywords, '{}'::text[])) k)
     where i.id::text = r.subject->>'inquiry_id' and i.category = 'general';
    get diagnostics v_n = row_count;
  end if;
  return jsonb_build_object('inquiry_id', r.subject->>'inquiry_id', 'category', v_choice, 'set', v_n = 1);
end $fn$;
revoke execute on function public.fn_reason_apply_customer_api__keywords(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_customer_api__keywords(bigint, jsonb) to service_role;

create or replace function public.fn_reason_apply_inbound_email__infer_sector(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_n integer := 0;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if not found or (r.subject->>'lead_id') is null then return null; end if;
  if v_choice is not null and exists (select 1 from public.category_specs cs where cs.category = v_choice) then
    update public.leads l set sector = v_choice
     where l.id = (r.subject->>'lead_id')::bigint and l.sector is null;
    get diagnostics v_n = row_count;
  end if;
  return jsonb_build_object('lead_id', (r.subject->>'lead_id')::bigint, 'sector', v_choice, 'set', v_n = 1);
end $fn$;
revoke execute on function public.fn_reason_apply_inbound_email__infer_sector(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_inbound_email__infer_sector(bigint, jsonb) to service_role;
