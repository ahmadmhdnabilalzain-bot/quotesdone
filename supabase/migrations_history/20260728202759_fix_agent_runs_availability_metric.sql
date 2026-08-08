-- ---------------------------------------------------------------------------
-- The agent_runs health check could never report anything but 0%.
--
-- Whatever writes health_checks(check_kind='agent_runs') sets ok=false whenever ANY
-- agent had a failed run in the window - detail is literally "10 failed runs". The
-- company runs ~140 scheduled jobs, so at least one of them fails somewhere in any
-- given hour, always. The check was therefore structurally pinned at 0.00% across all
-- 168 samples in 7 days.
--
-- That number was then averaged with the real HTTP probe (100.00% across 672 samples)
-- to produce a reported availability of ~80%, which described nothing that exists.
--
-- Fixing the writer would only fix one writer. This corrects the metric at the table,
-- so any producer - present or future - gets a threshold instead of a tripwire.
--
-- "Available" for agent reliability now means: fewer than 10% of agent runs in the last
-- hour failed. Below that is normal operation in a system this size. Above it is a real
-- signal. The observed 7-day reliability is ~97%, so the threshold has honest headroom
-- without being so loose it can never fire.
-- ---------------------------------------------------------------------------

create or replace function trg_health_check_agent_threshold()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_total   int;
  v_failed  int;
  v_rate    numeric;
  v_limit   numeric := coalesce(
    (select nullif(value,'')::numeric from app_secrets where key='agent_failure_rate_limit'), 0.10);
begin
  if new.check_kind is distinct from 'agent_runs' then
    return new;
  end if;

  select count(*),
         count(*) filter (where status not in ('ok','success','completed','skipped','warn'))
    into v_total, v_failed
  from agent_runs
  where started_at > now() - interval '1 hour';

  -- No runs at all in an hour is itself a failure: the company has gone quiet.
  if v_total = 0 then
    new.ok := false;
    new.detail := 'NO agent runs at all in the last hour - the company has gone silent, which is worse than a high failure rate.';
    return new;
  end if;

  v_rate := round(v_failed::numeric / v_total, 4);
  new.ok := (v_rate < v_limit);
  new.detail := v_failed || ' of ' || v_total || ' agent runs failed in the last hour ('
             || round(v_rate * 100, 2) || '%); threshold ' || round(v_limit * 100, 2) || '%'
             || case when new.ok then '' else ' - OVER THRESHOLD' end
             || '. [Recomputed by trg_health_check_agent_threshold; the raw producer sets ok=false on any single failure, which can never be true.]';
  return new;
end $$;

drop trigger if exists health_checks_agent_threshold on health_checks;
create trigger health_checks_agent_threshold
  before insert on health_checks
  for each row execute function trg_health_check_agent_threshold();

revoke execute on function trg_health_check_agent_threshold() from public, anon, authenticated;

insert into app_secrets (key, value)
select 'agent_failure_rate_limit', '0.10'
where not exists (select 1 from app_secrets where key='agent_failure_rate_limit');

comment on function trg_health_check_agent_threshold() is
  'Replaces the any-failure-means-down rule on health_checks(agent_runs) with a real failure-rate threshold. Added 28 Jul 2026: the old rule pinned the metric at 0% forever and, averaged with the 100% HTTP probe, produced a fictional 80% availability.';