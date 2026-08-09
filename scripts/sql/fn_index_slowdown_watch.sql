-- ROW #3 s31 — an index fell and nothing in the company noticed.
--
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   s31-slowdown-investigated  MISSING  1 index fall(s) over 1 point in 7d, of which 1 produced no
--                                       alert, proposal or action afterwards
--
--   company_maturity fell 44.1 -> 42.4 on 2026-08-06. Nothing referenced it afterwards.
--
-- The check's first leg — "a routine other than the writer reads company_index and raises
-- something" — reads 1 and is satisfied by ACCIDENT: the only routine matching is fn_ws_company_os,
-- a read path for the OS screen that happens to name company_index and agent_actions in the same
-- body. It investigates nothing. There is no index watcher in this company.
--
-- ── WHAT AN INVESTIGATION HAS TO CONTAIN TO BE ONE ──────────────────────────────────────────────
-- "The index fell" is a restatement, not an investigation. company_index stores a `dimensions`
-- object alongside every score, so the fall can be attributed: the routine compares the dimensions
-- of the falling measurement against the previous one and names the dimensions that went DOWN, with
-- both values. That is arithmetic over stored numbers — the same standard as the health note, and
-- the reason the proposal can say where the drop came from without guessing why.
--
-- The proposal is explicit that the two are different: "the drop is arithmetic, the reason is not".
-- Naming the moved dimension is as far as the data goes; a routine that also asserted a CAUSE would
-- be inventing one.
--
-- ── CATCHING UP IS NOT BACK-DATING ──────────────────────────────────────────────────────────────
-- The first run will raise the 6 Aug fall, three days late. That is legitimate: the investigation
-- happens now and is dated now. Nothing is written with a historical timestamp and no past row is
-- edited — the company is simply looking at something it should have looked at on the day.
--
-- Only falls with NO existing artefact are raised, using the same three-way lookup the check does
-- (founder_alerts, evolution_proposal, agent_actions), so a fall someone already picked up is left
-- alone and a daily schedule cannot produce a duplicate.
--
-- trigger_kind and change_class are drawn from evolution_proposal's CHECK constraints:
-- metric_off_target and process. An index losing a point is a metric off its target.
create or replace function public.fn_index_slowdown_watch()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare n int := 0; r record; v_moved text;
begin
  for r in
    select z.index_name, z.measured_on, z.score, z.prev, z.dims, z.prev_dims
      from (select c.index_name, c.measured_on, c.score, c.dimensions dims,
                   lag(c.score)      over (partition by c.index_name order by c.measured_on) prev,
                   lag(c.dimensions) over (partition by c.index_name order by c.measured_on) prev_dims
              from public.company_index c
             where c.measured_on > current_date - 30) z
     where z.prev is not null and z.score < z.prev - 1 and z.measured_on > current_date - 7
       and not exists (select 1 from public.founder_alerts a
                        where a.created_at::date >= z.measured_on
                          and position(z.index_name in coalesce(a.event,'')||' '||coalesce(a.detail::text,'')) > 0)
       and not exists (select 1 from public.evolution_proposal p
                        where p.created_at::date >= z.measured_on
                          and position(z.index_name in coalesce(p.subject,'')||' '||coalesce(p.observation,'')) > 0)
       and not exists (select 1 from public.agent_actions g
                        where g.created_at::date >= z.measured_on
                          and position(z.index_name in coalesce(g.title,'')||' '||coalesce(g.detail::text,'')) > 0)
  loop
    -- WHERE THE DROP CAME FROM, out of the index's own stored dimensions. Only dimensions that
    -- actually fell, biggest mover first, with both values so the size is visible.
    select string_agg(d.k||' '||d.was||' to '||d.now_v, ', ' order by (d.was - d.now_v) desc)
      into v_moved
      from (select k, (r.prev_dims->>k)::numeric was, (r.dims->>k)::numeric now_v
              from jsonb_object_keys(r.dims) k
             where jsonb_typeof(r.dims->k) = 'number'
               and jsonb_typeof(coalesce(r.prev_dims->k,'null'::jsonb)) = 'number'
               and (r.prev_dims->>k)::numeric > (r.dims->>k)::numeric) d;

    insert into public.evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
    values ('metric_off_target', r.index_name,
      format('%s fell from %s to %s on %s, a drop of %s points. Dimensions that moved down: %s.',
             r.index_name, r.prev, r.score, r.measured_on, round(r.prev - r.score, 2),
             coalesce(v_moved, 'none that the index breaks out — the drop is in the weighting, not in a named dimension')),
      jsonb_build_object('index', r.index_name, 'from', r.prev, 'to', r.score,
                         'fell_by', round(r.prev - r.score, 2), 'measured_on', r.measured_on,
                         'dimensions_down', v_moved),
      format('Find the cause of the %s fall before it compounds. The dimensions above are where it came from; the drop is arithmetic, the reason is not, and only one of those two is in the data.', r.index_name),
      'process');
    n := n + 1;
  end loop;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('index_slowdown_watch', now(), now(), 'ok', jsonb_build_object('investigated', n),
    case when n = 0 then 'No index lost more than a point in the last 7 days without something already picking it up.'
         else n||' index fall(s) over a point raised for investigation, with the dimensions that moved.' end);

  return jsonb_build_object('investigated', n);
end $function$;
