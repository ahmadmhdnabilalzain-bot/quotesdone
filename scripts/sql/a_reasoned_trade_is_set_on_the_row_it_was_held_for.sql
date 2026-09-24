-- A REASONED TRADE IS SET ON THE ROW IT WAS HELD FOR — the replay effect of decision-point batch B2 (a lead's sector).
-- Seat: sales_engineer (the sector of a supplier lead). Written by it_engineer's batch
-- agent B2, 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
--
-- WHY. inbound_email inferSector() read a supplier lead's sector off a KW map: the highest substring count became
-- leads.sector ('door' in 'outdoor', 'sign' in 'design'). The map is deleted; the sector is reasoned among the real
-- category_specs rows, or 'none' (_shared/reasoned_trades.ts tradeOfText). Under the model hold the lead is saved with
-- no sector and fn_reason_held_resolve (a_reasoned_answer_is_applied_by_its_own_surface.sql) calls the routine below
-- once the question is reasoned. (create_inquiry's keyword fallback needed no replay: its trade is the intake's own.)
--
-- WHAT. public.fn_reason_apply_inbound_email__infer_sector(p_id bigint, p_result jsonb) returns jsonb: sets leads.sector
-- to the reasoned category_specs slug only while it is still NULL; 'none' or any id that is not a slug writes nothing
-- (no nearest mapping). Returns what it did.
--
-- MEASURED 23 Sep 2026 (supabase/schema/full_schema.sql): leads.id bigint identity, leads.sector text,
-- category_specs.category text.
--
-- Pending: scripts/sql/pending/a_reasoned_trade_is_set_on_the_row_it_was_held_for.txt (apply after
-- a_reasoned_answer_is_applied_by_its_own_surface.sql). Proved in one aborted transaction:
-- scripts/checks/decision_points_are_reasoned.test.mjs.

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
