-- Seat: sales_engineer (the hold desk), delivered by customer_support. Assigned: customer_support (supplier follow-up of
-- #1909, item 3; founder ruling 1608).
--
-- MEASURED on origin/main: a hold had ONE end besides being answered: the customer's reveal
-- (a_supplier_who_leaves_holds_unanswered_is_warned_then_held.sql, trigger z30_decision_closes_unanswered_holds on
-- transactions.revealed_at). A quote_spec_hold ('open' / 'awaiting_approval') or a quote_quality_hold (released_at and
-- superseded_at null) on a request that ENDED without a reveal (expired, lost, cancelled, closed, completed without
-- award: the request-outcome duty of #1906 and the customer's cancel) or on a quote the supplier WITHDREW stayed open for
-- good: it counted in the supplier's bell (supplier_portal overview LIVE_HOLD), the quality tick kept mailing its fixes
-- and could still release it after 24 hours, and spec_hold kept offering a form for a quote nobody would see.
-- Production on 10 Nov 2026: 0 such holds open (0 open spec holds in total), so nothing is backfilled in practice; the
-- backfill below is still run so the rule holds for whatever exists when this is applied.
--
-- WHAT THIS CHANGES:
--   1. Two more ends for a spec hold: 'request_ended' and 'quote_withdrawn' (the state CHECK widened; decided_at set).
--      Neither is an "ignored hold" incident: the founder's rule (instruction 158) counts a hold left open at the
--      customer's DECISION, and an ended request or a withdrawn quote had none. Neither resets the run either
--      (trg_hold_answered_resets_the_run reads only 'released' / 'superseded').
--   2. A quality hold on such a quote is closed as superseded (superseded_at), the column the quality tick and every
--      reader already treat as closed-without-release.
--   3. Who closes: one routine, fn_quote_holds_close_without_decision, called by two triggers, so EVERY door that ends a
--      request (fn_sales_engineer_request_outcomes, fn_cancel_inquiry, fn_sales_engineer_closes_unreached_requests, a
--      hire) and every door that withdraws a quote (supplier_api withdraw_quote) closes its holds, with no list of doors
--      to keep in step. The ends of a request are the one list (_shared/request_closed.ts CLOSED_REQUEST_STATUSES).
-- NOT CHANGED: the reveal's own close (unresolved_at_decision + the incident), the hold desk's release, the quality tick.
-- prevented by: scripts/checks/a_hold_closes_when_its_request_ends_or_its_quote_is_withdrawn.test.mjs and this file's _probe.sql.
-- Pending until the release applies it: scripts/sql/pending/a_hold_closes_when_its_request_ends_or_its_quote_is_withdrawn.txt

alter table public.quote_spec_hold drop constraint if exists quote_spec_hold_state_check;
alter table public.quote_spec_hold add constraint quote_spec_hold_state_check
  check (state in ('open', 'awaiting_approval', 'released', 'superseded', 'unresolved_at_decision', 'request_ended', 'quote_withdrawn'));

create or replace function public.fn_quote_holds_close_without_decision(p_inquiry uuid, p_quote uuid, p_state text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_spec int := 0; v_quality int := 0;
begin
  if p_state not in ('request_ended', 'quote_withdrawn') then raise exception 'a hold closes without a decision as request_ended or quote_withdrawn, not %', p_state; end if;
  if p_inquiry is null and p_quote is null then return jsonb_build_object('spec', 0, 'quality', 0); end if;
  update public.quote_spec_hold h
     set state = p_state, decided_at = now(), updated_at = now()
   where h.state in ('open', 'awaiting_approval')
     and (h.quote_id = p_quote or (p_inquiry is not null and h.quote_id in (select q.id from public.quotes q where q.inquiry_id = p_inquiry)));
  get diagnostics v_spec = row_count;
  update public.quote_quality_hold x
     set superseded_at = now(), updated_at = now()
   where x.released_at is null and x.superseded_at is null
     and (x.quote_id = p_quote or (p_inquiry is not null and x.quote_id in (select q.id from public.quotes q where q.inquiry_id = p_inquiry)));
  get diagnostics v_quality = row_count;
  return jsonb_build_object('spec', v_spec, 'quality', v_quality);
end $fn$;
revoke execute on function public.fn_quote_holds_close_without_decision(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.trg_request_end_closes_its_holds()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  if coalesce(NEW.status, '') in ('completed', 'closed', 'cancelled', 'expired', 'lost')
     and coalesce(OLD.status, '') not in ('completed', 'closed', 'cancelled', 'expired', 'lost') then
    perform public.fn_quote_holds_close_without_decision(NEW.id, null, 'request_ended');
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_request_end_closes_its_holds() from public, anon, authenticated;
drop trigger if exists z31_request_end_closes_its_holds on public.inquiries;
create trigger z31_request_end_closes_its_holds after update of status on public.inquiries
  for each row execute function public.trg_request_end_closes_its_holds();

create or replace function public.trg_withdrawn_quote_closes_its_holds()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  if NEW.status = 'withdrawn' and OLD.status is distinct from 'withdrawn' then
    perform public.fn_quote_holds_close_without_decision(null, NEW.id, 'quote_withdrawn');
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_withdrawn_quote_closes_its_holds() from public, anon, authenticated;
drop trigger if exists z31_withdrawn_quote_closes_its_holds on public.quotes;
create trigger z31_withdrawn_quote_closes_its_holds after update of status on public.quotes
  for each row execute function public.trg_withdrawn_quote_closes_its_holds();

-- The rule for whatever is open when this is applied (0 on 10 Nov 2026).
select public.fn_quote_holds_close_without_decision(null, q.id, 'quote_withdrawn') from public.quotes q
 where q.status = 'withdrawn'
   and (exists (select 1 from public.quote_spec_hold h where h.quote_id = q.id and h.state in ('open', 'awaiting_approval'))
     or exists (select 1 from public.quote_quality_hold x where x.quote_id = q.id and x.released_at is null and x.superseded_at is null));
select public.fn_quote_holds_close_without_decision(i.id, null, 'request_ended') from public.inquiries i
 where i.status in ('completed', 'closed', 'cancelled', 'expired', 'lost')
   and exists (select 1 from public.quotes q where q.inquiry_id = i.id
                and (exists (select 1 from public.quote_spec_hold h where h.quote_id = q.id and h.state in ('open', 'awaiting_approval'))
                  or exists (select 1 from public.quote_quality_hold x where x.quote_id = q.id and x.released_at is null and x.superseded_at is null)));

select case
  when exists (select 1 from public.quote_spec_hold h join public.quotes q on q.id = h.quote_id left join public.inquiries i on i.id = q.inquiry_id
                where h.state in ('open', 'awaiting_approval') and (q.status = 'withdrawn' or i.status in ('completed', 'closed', 'cancelled', 'expired', 'lost')))
    then 'PROBE FAILED: a spec hold is still open on an ended request or a withdrawn quote'
  when exists (select 1 from public.quote_quality_hold x join public.quotes q on q.id = x.quote_id left join public.inquiries i on i.id = q.inquiry_id
                where x.released_at is null and x.superseded_at is null and (q.status = 'withdrawn' or i.status in ('completed', 'closed', 'cancelled', 'expired', 'lost')))
    then 'PROBE FAILED: a quality hold is still open on an ended request or a withdrawn quote'
  when not exists (select 1 from pg_trigger where tgname = 'z31_request_end_closes_its_holds' and tgrelid = 'public.inquiries'::regclass)
    or not exists (select 1 from pg_trigger where tgname = 'z31_withdrawn_quote_closes_its_holds' and tgrelid = 'public.quotes'::regclass)
    then 'PROBE FAILED: a closing trigger is missing'
  when has_function_privilege('anon', 'public.fn_quote_holds_close_without_decision(uuid, uuid, text)', 'execute')
    then 'PROBE FAILED: anon can close a hold'
  else 'PROBE OK' end as verdict;
