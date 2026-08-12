-- THE BACKFILL GOT SLOWER THE MORE OF IT WAS DONE.
--
-- fn_leads_retrade picked its batch with
--
--   where invite_trades is distinct from fn_norm_trades(<the lead's own text>)
--   order by id limit N
--
-- which is correct and self-limiting, and which degrades as it succeeds. fn_norm_trades regex-
-- matches every alias of every active taxonomy_trade row, so the predicate costs a full alias sweep
-- PER ROW EXAMINED. Early on the stale rows are at the front and a batch is cheap. After 12,620
-- rows have converged the planner walks all 12,620 satisfied rows first, paying that sweep on each,
-- before it finds 700 that still need work — and the taxonomy just grew from 25 trades to 40, so
-- each of those sweeps got 60% more expensive at the same time. It now hits the statement timeout
-- and takes the whole call down with it, including the rows it had just fixed.
--
-- A BOUNDED ID WINDOW INSTEAD OF A PREDICATE SEARCH. The caller walks id ranges, so the work per
-- call is the size of the window and does not depend on how much is already done. `is distinct
-- from` stays in the UPDATE, so a converged row inside the window is still not rewritten and the
-- function is still idempotent — it just stops being the thing that finds the window.
--
-- p_after defaults to 0 and the return carries next_after, so a caller with no state can loop on
-- the value it was handed and stop when the window passes the highest id. The daily cron keeps the
-- predicate form: at three thousand rows a night against a converged table it is a cheap no-op, and
-- it is the path that has to catch a single edited lead rather than sweep the corpus.
create or replace function public.fn_leads_retrade(p_limit integer default 2000, p_after bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_n int; v_left bigint; v_hi bigint; v_max bigint;
begin
  -- The window: the next p_limit ids at or above p_after, chosen WITHOUT calling the normaliser.
  select max(id) into v_hi from (
    select id from public.leads where id > coalesce(p_after,0)
     order by id limit greatest(coalesce(p_limit, 2000), 1)) w;
  select max(id) into v_max from public.leads;

  if v_hi is null then
    -- past the end: nothing left to walk
    return jsonb_build_object('renormalised', 0, 'next_after', null, 'done', true,
      'in_taxonomy_vocab', (select count(*) from public.leads
                             where invite_trades && (select array_agg(code) from public.taxonomy_trade)));
  end if;

  update public.leads l
     set invite_trades = public.fn_norm_trades(
           coalesce(l.company_name,'')||' '||coalesce(l.categories,'')||' '||
           coalesce(l.sector,'')||' '||coalesce(l.services,'')||' '||coalesce(l.products,''))
   where l.id > coalesce(p_after,0) and l.id <= v_hi
     and not (coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid')
     and l.invite_trades is distinct from public.fn_norm_trades(
           coalesce(l.company_name,'')||' '||coalesce(l.categories,'')||' '||
           coalesce(l.sector,'')||' '||coalesce(l.services,'')||' '||coalesce(l.products,''));
  get diagnostics v_n = row_count;

  -- Progress is an array overlap, never a second run of the normaliser. See the header.
  select count(*) into v_left from public.leads l
   where l.invite_trades is not null and array_length(l.invite_trades,1) > 0
     and not (l.invite_trades && (select array_agg(code) from public.taxonomy_trade));

  return jsonb_build_object(
    'renormalised', v_n,
    'next_after', v_hi,
    'done', v_hi >= coalesce(v_max, v_hi),
    'still_wrong_vocabulary', v_left,
    'in_taxonomy_vocab', (select count(*) from public.leads
                           where invite_trades && (select array_agg(code) from public.taxonomy_trade)));
end
$function$;

comment on function public.fn_leads_retrade(integer, bigint) is
  'Re-normalises leads.invite_trades into taxonomy_trade codes via fn_norm_trades. Walks a BOUNDED '
  'ID WINDOW (p_after, +p_limit] so the cost per call does not grow as the backfill converges; loop '
  'on the returned next_after until done=true. Idempotent.';

revoke execute on function public.fn_leads_retrade(integer, bigint) from public;
grant execute on function public.fn_leads_retrade(integer, bigint) to service_role;

-- The one-argument form the daily cron called is now ambiguous against the two-argument default.
drop function if exists public.fn_leads_retrade(integer);

-- THE CRON MUST NOT USE THE WINDOW, and writing `fn_leads_retrade(3000, 0)` into it would have been
-- a defect I introduced: p_after=0 every night means it re-walks ids 1..3000 for ever and never
-- reaches the rest of the table. The window is for a caller that carries next_after between calls.
--
-- The nightly job wants "find anything stale, anywhere", which is what it did before — and the
-- reason that got expensive is the per-row fn_norm_trades in the SEARCH. So it searches on a CHEAP
-- predicate instead: a row is a candidate if it has no trades at all, or if its trades do not
-- overlap the taxonomy vocabulary. Both are array operations on data already in the row.
--
-- STATED PLAINLY, because it is a narrower net than the one it replaces: this does NOT catch a lead
-- whose own text changed while its stored trades still overlap the vocabulary — say a supplier who
-- adds "solar" to their services and is already tagged `electrical`. That row keeps a correct but
-- incomplete trade list until the next full window sweep. Catching it needs the normaliser in the
-- search, which is exactly the cost that broke this. A full sweep is the window loop, run
-- deliberately, not a nightly cron pretending to do it.
create or replace function public.fn_leads_retrade_stale(p_limit integer default 3000)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_n int;
begin
  with vocab as (select array_agg(code) c from public.taxonomy_trade where active),
  pick as (
    select l.id from public.leads l, vocab v
     where not (coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid')
       and (l.invite_trades is null
            or array_length(l.invite_trades,1) is null
            or not (l.invite_trades && v.c))
     order by l.id
     limit greatest(coalesce(p_limit, 3000), 1))
  update public.leads l
     set invite_trades = public.fn_norm_trades(
           coalesce(l.company_name,'')||' '||coalesce(l.categories,'')||' '||
           coalesce(l.sector,'')||' '||coalesce(l.services,'')||' '||coalesce(l.products,''))
    from pick
   where l.id = pick.id
     and l.invite_trades is distinct from public.fn_norm_trades(
           coalesce(l.company_name,'')||' '||coalesce(l.categories,'')||' '||
           coalesce(l.sector,'')||' '||coalesce(l.services,'')||' '||coalesce(l.products,''));
  get diagnostics v_n = row_count;
  return jsonb_build_object('renormalised', v_n,
    'in_taxonomy_vocab', (select count(*) from public.leads
                           where invite_trades && (select array_agg(code) from public.taxonomy_trade)));
end
$function$;

comment on function public.fn_leads_retrade_stale(integer) is
  'Nightly maintenance pass for leads.invite_trades. Searches on a CHEAP array predicate (no trades, '
  'or trades outside the taxonomy vocabulary) so the scan does not pay fn_norm_trades per row. Does '
  'not catch a lead whose text changed while its trades still overlap the vocabulary - that needs '
  'the fn_leads_retrade window sweep.';

revoke execute on function public.fn_leads_retrade_stale(integer) from public;
grant execute on function public.fn_leads_retrade_stale(integer) to service_role;

select cron.schedule('backfill_invite_trades', '15 4 * * *',
  $cron$select public.fn_leads_retrade_stale(3000);$cron$);
