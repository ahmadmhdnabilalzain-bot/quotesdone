-- ---------------------------------------------------------------------------------------------
-- A DAILY JOB THAT HAS BEEN ABORTING ON A CONSTRAINT ITS OWN GUARD CANNOT SEE.
--
-- index_slowdown_watch_daily failed at 04:15 UTC on 16 Aug 2026 with:
--   duplicate key value violates unique constraint "evolution_proposal_dedupe_idx"
--
-- The index is  unique (trigger_kind, subject, change_class) where status = 'proposed'  — no date
-- in it at all. The function's guard is
--   not exists (... from evolution_proposal p where p.created_at::date >= z.measured_on ...)
-- which only looks at proposals raised ON OR AFTER the day being measured. Six proposals from
-- 27 Jul and 10 Aug are still sitting at status='proposed' — company_maturity,
-- marketplace_health, rfq_ready_pct, refund_rate, avoidable_ai_pct and others. They are older than
-- today's measurement, so the guard waves the insert through and the index refuses it.
--
-- Two guards, two different definitions of "already raised", and the weaker one runs first. This is
-- the same shape as the idempotency_key collision recorded in the session skill: a not-exists guard
-- that scopes on something the UNIQUE constraint does not.
--
-- The damage is not the failed insert. plpgsql aborts the whole function on it, so:
--   - every remaining index in the loop is skipped,
--   - the agent_runs row at the end is never written.
-- The job therefore fails silently as far as anything reading agent_runs is concerned — including
-- the failed-run watchdog, which cannot report a run that left no row.
--
-- THE CONSTRAINT IS THE RULE, so let it decide. `on conflict do nothing` on the exact predicate of
-- the partial index makes the loop idempotent, and the count becomes actual inserts rather than
-- attempts — GET DIAGNOSTICS, not n := n + 1, because a skipped duplicate is not an investigation
-- raised. The existing not-exists guards are kept: they are cheaper and they also cover
-- founder_alerts and agent_actions, which the index knows nothing about. They are simply no longer
-- the last word.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_index_slowdown_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int := 0; r record; v_moved text; v_ins int;
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
      'process')
    -- The partial unique index gets the final say. Its predicate is repeated verbatim so the
    -- arbiter resolves to evolution_proposal_dedupe_idx and nothing else.
    on conflict (trigger_kind, subject, change_class) where status = 'proposed' do nothing;
    -- Count what was written, not what was attempted: a duplicate that was skipped is not an
    -- investigation raised, and the note at the bottom is read as if it were.
    get diagnostics v_ins = row_count;
    n := n + v_ins;
  end loop;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('index_slowdown_watch', now(), now(), 'ok', jsonb_build_object('investigated', n),
    case when n = 0 then 'No index lost more than a point in the last 7 days without something already picking it up.'
         else n||' index fall(s) over a point raised for investigation, with the dimensions that moved.' end);

  return jsonb_build_object('investigated', n);
end $function$
;
