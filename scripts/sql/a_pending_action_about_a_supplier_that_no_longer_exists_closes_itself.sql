-- A PENDING ACTION ABOUT A SUPPLIER THAT NO LONGER EXISTS CLOSES ITSELF.
-- Seat: customer_support (supplier registration; the actions are the sales_engineer's queue). 10 Nov 2026, item 10 of the
-- supplier-journey audit's report (#1901), founder ruling 1608.
--
-- MEASURED BEFORE THIS FILE (production, read-only, 10 Nov 2026): two pending document_read_stuck actions name suppliers that
-- were deleted (340683 -> 153580, 324789 -> 151660; fn_supplier_doc_reading_escalate filed them, and nothing closes one when
-- its lead goes). The same query over every pending action that names a supplier (detail.supplier_id, or target_table
-- 'leads') found 156, ALL orphaned: doc_trades_held 149, vision_trades_confirm 5, document_read_stuck 2, every one the
-- sales_engineer's. A queue item whose subject is gone can never be decided; it only makes the queue lie about its size.
--
-- WHAT THIS CHANGES (a rule, not a one-off delete; no row is deleted):
--   * fn_agent_actions_close_for_gone_suppliers(ids): every PENDING action, other than a handoff, that names a supplier
--     (detail.supplier_id, or target_table 'leads' and target_id) whose lead does not exist is set 'dismissed', decided_by
--     'sales_engineer', with detail.closed_because and detail.supplier_gone; null = every supplier, else only those ids.
--     A handoff is left alone: it carries its own note contract (agent_actions_handoff_*) and its own closer, and none names
--     a supplier today (0 pending).
--   * z90_leads_gone_closes_its_pending_actions: AFTER DELETE ... FOR EACH STATEMENT on leads, with the deleted rows as a
--     transition table, so a delete of many leads closes their actions in one statement.
--   * fn_supplier_doc_reading_escalate (the heartbeat's supplier_doc_reading_stuck step, live body md5 e976b205...) runs the
--     rule first, every run, for anything the trigger did not see (the 156 above are closed by its first run after the
--     apply; nothing here closes them at apply time).
-- WHAT IT DOES NOT CHANGE: an action whose supplier exists; any decided action; customers (not a supplier subject).
-- Prevented by: scripts/checks/a_pending_action_about_a_supplier_that_no_longer_exists_closes_itself.test.mjs and the probe of
-- the same name (rolled back on production).

create or replace function public.fn_agent_actions_close_for_gone_suppliers(p_ids bigint[] default null)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_n int;
begin
  with named as (
    select a.id, coalesce(nullif(a.detail ->> 'supplier_id', ''), case when a.target_table = 'leads' then a.target_id end) as sid
      from public.agent_actions a
     where a.status = 'pending' and a.kind <> 'handoff'
       and (a.detail ? 'supplier_id' or a.target_table = 'leads')
  ), gone as (
    select n.id, n.sid::bigint as sid from named n
     where n.sid ~ '^[0-9]{1,18}$'
       and (p_ids is null or n.sid::bigint = any(p_ids))
       and not exists (select 1 from public.leads l where l.id = n.sid::bigint)
  )
  update public.agent_actions a
     set status = 'dismissed', decided_at = now(), decided_by = 'sales_engineer',
         detail = a.detail || jsonb_build_object('closed_because', 'the supplier no longer exists', 'supplier_gone', g.sid)
    from gone g where a.id = g.id;
  get diagnostics v_n = row_count;
  return v_n;
end $fn$;
revoke execute on function public.fn_agent_actions_close_for_gone_suppliers(bigint[]) from public, anon, authenticated;

create or replace function public.fn_leads_gone_closes_its_pending_actions()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  perform public.fn_agent_actions_close_for_gone_suppliers(array(select g.id from gone g));
  return null;
end $fn$;
revoke execute on function public.fn_leads_gone_closes_its_pending_actions() from public, anon, authenticated;
drop trigger if exists z90_leads_gone_closes_its_pending_actions on public.leads;
create trigger z90_leads_gone_closes_its_pending_actions after delete on public.leads
  referencing old table as gone for each statement execute function public.fn_leads_gone_closes_its_pending_actions();

CREATE OR REPLACE FUNCTION public.fn_supplier_doc_reading_escalate(p_minutes integer DEFAULT 30, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb := '[]'::jsonb; r record; d jsonb; docs jsonb; i int; changed boolean; v_since timestamptz;
begin
  -- 10 Nov 2026: a pending action about a supplier that no longer exists closes itself here too, every heartbeat, for any
  -- delete the statement trigger did not see (a_pending_action_about_a_supplier_that_no_longer_exists_closes_itself.sql)
  perform public.fn_agent_actions_close_for_gone_suppliers(null);
  for r in select c.supplier_id, c.source_docs, c.extracted_at from public.supplier_capabilities c
            where c.source_docs -> 'docs' @> '[{"status":"reading"}]'::jsonb
            order by c.supplier_id limit greatest(1, least(coalesce(p_limit, 50), 200)) for update skip locked loop
    docs := r.source_docs -> 'docs'; changed := false;
    for i in 0 .. jsonb_array_length(docs) - 1 loop
      d := docs -> i;
      -- since when it has been 'reading': its own mark, else the capability row's last read, else now (never escalated on
      -- the first run when nothing says how old it is)
      v_since := coalesce((d ->> 'read_at')::timestamptz, r.extracted_at, now());
      if d ->> 'status' = 'reading' and v_since <= now() - make_interval(mins => greatest(coalesce(p_minutes, 30), 1)) then
        docs := jsonb_set(docs, array[i::text], d || jsonb_build_object('status', 'unreadable',
                  'reason', 'the read did not finish (the reader stopped before it was done); the sales engineer has it'));
        insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
        select 'sales_engineer', 'document_read_stuck', 'pending', 'low',
                left('A supplier document was never read: ' || coalesce(d ->> 'name', d ->> 'path', '?'), 200),
                jsonb_build_object('supplier_id', r.supplier_id, 'path', d ->> 'path', 'kind', d ->> 'kind', 'reading_since', d ->> 'read_at',
                                   'waiting_for', 'sales_engineer to read it again, or to ask the supplier for a smaller or clearer copy'),
                'supplier_capabilities', r.supplier_id::text || ':' || coalesce(d ->> 'path', '')
         where not exists (select 1 from public.agent_actions a where a.kind = 'document_read_stuck' and a.status = 'pending'
                             and a.target_id = r.supplier_id::text || ':' || coalesce(d ->> 'path', ''));
        v := v || jsonb_build_array(jsonb_build_object('supplier_id', r.supplier_id, 'path', d ->> 'path'));
        changed := true;
      end if;
    end loop;
    if changed then
      update public.supplier_capabilities set source_docs = jsonb_set(r.source_docs, '{docs}', docs) where supplier_id = r.supplier_id;
      -- the supplier's status is made current: no longer held for 'documents_being_read' by a read that will never finish
      if exists (select 1 from public.leads l where l.id = r.supplier_id) then
        perform public.fn_sales_engineer_verifies_supplier(r.supplier_id, 'documents_read');
      end if;
    end if;
  end loop;
  return v;
end $function$;

