-- The stale brief that nobody had read either — 12 Aug 2026
--
-- Sixth in the s36 sequence. One rule, raised once per lagging agent, and its assumptions are
-- interpolated per agent: the slug, the item count and the staleness all appear in the reason, so
-- two agents never get the same sentence.
--
-- The assumption worth stating is that item count and refresh date measure the SHELF, not the
-- reading: an agent with a large, fresh brief that it never retrieves is indistinguishable here from
-- one that reads its brief on every call. This rule can see stock and cannot see use.
--
-- Loop, conditions, auto-close behaviour and return shape unchanged.

create or replace function public.fn_dispatch_agent_knowledge_gaps(p_stale_days integer default 14, p_thin_min integer default 4)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare a jsonb; g jsonb; opened int := 0; resolved_before int; resolved_after int; total_gap int := 0;
begin
  g := fn_knowledge_gaps(p_stale_days, p_thin_min);
  select count(*) into resolved_before from agent_actions where kind='knowledge_task' and detail->>'signal' like 'agent_knowledge:%' and status in ('pending','needs_review');
  for a in select * from jsonb_array_elements(g->'agents') loop
    declare v_gap boolean := (a->>'status') in ('stale','thin'); v_slug text := a->>'slug';
    begin
      if v_gap then total_gap := total_gap + 1; end if;
      perform kn_task('agent_knowledge:'||v_slug, v_gap, case when (a->>'status')='thin' then 'low' else 'medium' end,
        'Refresh knowledge: '||coalesce(a->>'name',v_slug),
        coalesce(a->>'name',v_slug)||' has '||coalesce(a->>'items','0')||' knowledge item(s), last refreshed '||
        coalesce((a->>'days_stale')||' days ago','never')||' (status: '||(a->>'status')||'). Regenerate its field brief so it advises with current expertise. Auto-closes once refreshed.',
        jsonb_build_array(
          'Item count and refresh date measure the SHELF, not the reading. '||coalesce(a->>'name',v_slug)||' could hold a large, fresh brief it never retrieves and look identical here to one that reads it on every call.',
          'The thresholds are chosen, not derived: under '||p_thin_min||' item(s) is "thin" and '||p_stale_days||' day(s) is "stale". An agent whose field genuinely changes twice a year is stale here every fortnight.',
          '"Regenerate" assumes the source material has moved on. Regenerating against an unchanged world produces a new date and the same knowledge, which closes this task without improving anything.',
          coalesce(a->>'name',v_slug)||' is doing work worth briefing. An agent that has never run is stale in exactly the same way as one that runs hourly.'),
        coalesce(a->>'name',v_slug)||' currently advises from '||coalesce(a->>'items','0')||' item(s) last refreshed '||coalesce((a->>'days_stale')||' days ago','never')||'. Refreshing changes what it tells suppliers and customers; leaving it means confident advice from a stale field brief, which does not fail visibly.',
        'Model spend, one generation per agent. The cheap failure is regenerating everything on a schedule; the expensive one is an agent quoting last quarter''s rules to a customer.');
    end;
  end loop;
  select count(*) into resolved_after from agent_actions where kind='knowledge_task' and detail->>'signal' like 'agent_knowledge:%' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at', now(), 'gaps_found', total_gap, 'open_tasks', resolved_after,
    'summary', g->'summary');
end $function$;
