-- a_trade_read_off_a_picture_waits_for_the_sales_engineer_to_confirm_it
-- Seat: sales_engineer (the decision); it_engineer (the build). 18 Oct 2026, review of #1412.
-- A profile or catalogue with no text layer (an image, a scanned PDF) is read by the vision model. Code can check the
-- trades' quotes only against the model's own transcription, so supplier_doc_trades.readDocForTrades never proposes
-- them: they sit in source_docs.docs[].vision_held, and one agent_actions row (kind vision_trades_confirm, pending,
-- target_id '<supplier_id>:<path>') asks the sales engineer to check them against the file.
--   1. agent_actions_one_pending_vision_confirm: at most ONE pending item per supplier and document, in the table, so two
--      simultaneous uploads cannot file two (the edge function's insert then fails 23505 and files nothing more).
--   2. fn_sales_engineer_decides_vision_trades(action, confirm[]): the codes confirmed (only codes that were held) move
--      into that document's trades and into supplier_capabilities.proposed_trades; the document's vision_held is
--      cleared; the item closes 'done' (something confirmed) or 'dismissed' (nothing confirmed = rejected). A decided
--      item cannot be decided again.
--   Proved by scripts/checks/a_trade_read_off_a_picture_waits_for_the_sales_engineer.test.mjs (one rolled-back
--   transaction on ZZ DEMO rows, this file replayed first).
-- The routine is CREATEd, so EXECUTE is revoked from PUBLIC here. Applied at merge (release operator), never before.

create unique index if not exists agent_actions_one_pending_vision_confirm
  on public.agent_actions (target_id) where kind = 'vision_trades_confirm' and status = 'pending';

create or replace function public.fn_sales_engineer_decides_vision_trades(p_action_id bigint, p_confirm text[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare a public.agent_actions; v_supplier bigint; v_path text; cap public.supplier_capabilities; docs jsonb; d jsonb;
        i int; v_held jsonb; v_keep jsonb; v_codes text[] := '{}';
begin
  select * into a from public.agent_actions where id = p_action_id and kind = 'vision_trades_confirm' for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_such_item'); end if;
  if a.status <> 'pending' then return jsonb_build_object('ok', false, 'error', 'already_decided', 'status', a.status); end if;
  v_supplier := (a.detail ->> 'supplier_id')::bigint; v_path := a.detail ->> 'path';
  select * into cap from public.supplier_capabilities where supplier_id = v_supplier for update;
  if found then
    docs := coalesce(cap.source_docs -> 'docs', '[]'::jsonb);
    for i in 0 .. jsonb_array_length(docs) - 1 loop
      d := docs -> i;
      continue when d ->> 'path' is distinct from v_path;
      v_held := coalesce(d -> 'vision_held', '[]'::jsonb);
      -- only a code that was held, and confirmed, is kept; it is marked as the sales engineer's confirmation
      select coalesce(jsonb_agg(h || jsonb_build_object('via', 'sales_engineer_confirmed')), '[]'::jsonb), coalesce(array_agg(distinct h ->> 'code'), '{}')
        into v_keep, v_codes
        from jsonb_array_elements(v_held) h where h ->> 'code' = any(coalesce(p_confirm, '{}'));
      docs := jsonb_set(docs, array[i::text], (d - 'vision_held') || jsonb_build_object('trades', coalesce(d -> 'trades', '[]'::jsonb) || v_keep));
    end loop;
    update public.supplier_capabilities
       set source_docs = jsonb_set(cap.source_docs, '{docs}', docs),
           proposed_trades = (select coalesce(array_agg(distinct c order by c), '{}') from unnest(coalesce(cap.proposed_trades, '{}') || v_codes) c)
     where supplier_id = v_supplier;
  end if;
  update public.agent_actions set status = case when cardinality(v_codes) > 0 then 'done' else 'dismissed' end,
         decided_at = now(), decided_by = 'sales_engineer',
         detail = detail || jsonb_build_object('confirmed', to_jsonb(v_codes))
   where id = a.id;
  return jsonb_build_object('ok', true, 'supplier_id', v_supplier, 'path', v_path, 'confirmed', to_jsonb(v_codes),
                            'status', case when cardinality(v_codes) > 0 then 'done' else 'dismissed' end);
end $function$;
revoke all on function public.fn_sales_engineer_decides_vision_trades(bigint, text[]) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_decides_vision_trades(bigint, text[]) to service_role;
