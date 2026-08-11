-- COST PER OS, AND IT CARRIES ITS OWN COVERAGE SO NOBODY CAN READ THE NUMBER WITHOUT THE CAVEAT.
--
-- "Cost per OS" is on the outstanding list. Building the obvious version - sum(cost_aed) grouped by
-- OS - would have produced a confident table that is wrong in three separate ways, each measured on
-- production 2026-08-11:
--
--   1. ATTRIBUTION. Only 1,627 of 2,285 calls in 30 days carry a dept_key at all, and they name
--      just 4 of the company's 25 departments. 658 calls belong to nobody. A per-OS table that
--      silently drops 29% of the spend is not a cost report, it is a guess with a border.
--
--   2. UNPRICEABLE HISTORY. 226 calls between 28 Jul and 5 Aug carry real tokens and cost_aed = 0.
--      fn_llm_log prices correctly - probed on production, gemini-3.1-flash-lite at 0.9181/5.5088
--      AED per Mtok returns 0.146898 for 100k in + 10k out - so those rows did not come through it.
--      The defect is ALREADY FIXED: zero-cost-with-tokens runs 28 Jul to 5 Aug and is ZERO on every
--      day since 6 Aug across 1,673 calls. They are not repriced here. Applying today's rate to
--      July usage would produce a number that was never charged, and inventing a cost is the same
--      class of error as inventing a KPI.
--
--   3. MODELS OUTSIDE THE CATALOG. 745 calls in 30 days ran on models absent from model_catalog
--      (~anthropic/claude-haiku-latest 669, claude-opus-4.8 61, gemini-3.5-flash 15). They price
--      correctly because model_rate has them - model_rate and model_catalog are two different
--      tables and only one of them is authoritative for money - but any report reading the catalog
--      to describe the fleet is describing a fleet that is not running.
--
-- So this returns the breakdown AND the coverage in ONE jsonb value. They cannot be separated by a
-- caller, which is the whole point: this codebase's recurring defect is a green number that has
-- quietly stopped measuring what it names.

create or replace function public.fn_cost_per_os(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_since timestamptz := now() - make_interval(days => greatest(coalesce(p_days,30), 1));
  v_rows jsonb; v_total numeric; v_calls bigint; v_unattributed bigint;
  v_unpriceable bigint; v_unpriceable_tokens bigint; v_first_unpriceable date; v_last_unpriceable date;
begin
  select coalesce(sum(cost_aed),0), count(*),
         count(*) filter (where dept_key is null),
         count(*) filter (where coalesce(cost_aed,0)=0 and (coalesce(prompt_tokens,0)+coalesce(output_tokens,0))>0 and not coalesce(cached,false)),
         coalesce(sum(coalesce(prompt_tokens,0)+coalesce(output_tokens,0))
                  filter (where coalesce(cost_aed,0)=0 and (coalesce(prompt_tokens,0)+coalesce(output_tokens,0))>0 and not coalesce(cached,false)),0),
         min(occurred_at) filter (where coalesce(cost_aed,0)=0 and (coalesce(prompt_tokens,0)+coalesce(output_tokens,0))>0 and not coalesce(cached,false))::date,
         max(occurred_at) filter (where coalesce(cost_aed,0)=0 and (coalesce(prompt_tokens,0)+coalesce(output_tokens,0))>0 and not coalesce(cached,false))::date
    into v_total, v_calls, v_unattributed, v_unpriceable, v_unpriceable_tokens, v_first_unpriceable, v_last_unpriceable
    from ai_cost_log where occurred_at > v_since;

  select coalesce(jsonb_agg(x order by x->>'cost_aed' desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
             'os_key',       coalesce(d.os_key, '(unattributed)'),
             'departments',  count(distinct l.dept_key),
             'calls',        count(*),
             'tokens',       coalesce(sum(coalesce(l.prompt_tokens,0)+coalesce(l.output_tokens,0)),0),
             'cost_aed',     round(coalesce(sum(l.cost_aed),0), 4),
             'share_pct',    case when v_total > 0
                                  then round(100.0 * coalesce(sum(l.cost_aed),0) / v_total, 1)
                                  else null end,
             'cost_per_call', case when count(*) > 0
                                   then round(coalesce(sum(l.cost_aed),0) / count(*), 5) else null end
           ) x
      from ai_cost_log l
      left join os_department d on d.dept_key = l.dept_key
     where l.occurred_at > v_since
     group by coalesce(d.os_key, '(unattributed)')
  ) s;

  return jsonb_build_object(
    'window_days', p_days,
    'since', v_since,
    'total_cost_aed', round(v_total, 4),
    'by_os', v_rows,
    -- THE COVERAGE TRAVELS WITH THE NUMBER. A caller cannot read one without the other.
    'coverage', jsonb_build_object(
      'calls', v_calls,
      'attributed_to_a_department', v_calls - v_unattributed,
      'unattributed', v_unattributed,
      'attributed_pct', case when v_calls > 0
                             then round(100.0 * (v_calls - v_unattributed) / v_calls, 1) else null end,
      'departments_seen', (select count(distinct dept_key) from ai_cost_log where occurred_at > v_since),
      'departments_active', (select count(*) from org_departments where active),
      'unpriceable_calls', v_unpriceable,
      'unpriceable_tokens', v_unpriceable_tokens,
      'unpriceable_window', case when v_unpriceable > 0
        then v_first_unpriceable::text || ' to ' || v_last_unpriceable::text else null end,
      'note', 'Unpriceable = real tokens, not cached, cost_aed 0. Those calls are counted in "calls" and contribute 0 to cost, so total_cost_aed is a FLOOR, not the spend. They are deliberately not repriced: applying today''s model_rate to past usage would report a number that was never charged.')
  );
end $function$;

revoke all on function public.fn_cost_per_os(integer) from public;
revoke all on function public.fn_cost_per_os(integer) from anon;
