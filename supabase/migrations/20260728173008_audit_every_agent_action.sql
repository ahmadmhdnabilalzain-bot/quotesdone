-- os_audit_log held 27 rows against 11,262 agent runs: only OS-UI actions were audited,
-- no agent work at all. From now every agent run lands in the audit trail, so autonomous
-- work is reconstructable after the fact - the precondition for leaving it alone.
create or replace function public.trg_audit_agent_run()
returns trigger
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
begin
  insert into os_audit_log (actor, action, entity, entity_id, detail, ok, err)
  values (
    coalesce(new.agent,'unknown_agent'),
    'agent_run',
    'agent_runs',
    new.id::text,
    jsonb_strip_nulls(jsonb_build_object(
      'status',  new.status,
      'counts',  new.counts,
      'note',    left(coalesce(new.note,''), 600),
      'started', new.started_at,
      'seconds', case when new.finished_at is not null and new.started_at is not null
                      then round(extract(epoch from (new.finished_at - new.started_at))::numeric, 2)
                      else null end)),
    coalesce(new.status,'ok') <> 'error',
    case when new.status = 'error' then left(coalesce(new.note,'error'), 400) else null end
  );
  return new;
exception when others then
  return new;   -- audit must never break the work it is recording
end $fn$;

drop trigger if exists trg_audit_agent_run on public.agent_runs;
create trigger trg_audit_agent_run
  after insert on public.agent_runs
  for each row execute function public.trg_audit_agent_run();

create index if not exists os_audit_log_at_idx    on public.os_audit_log (at desc);
create index if not exists os_audit_log_actor_idx on public.os_audit_log (actor, at desc);
create index if not exists os_audit_log_action_idx on public.os_audit_log (action, at desc);

-- Keep it bounded: agent-run audit is high volume, so retain 180 days.
-- Everything else (settings, incidents, undo, catalogue changes) is retained indefinitely.
create or replace function public.fn_audit_prune()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare n int;
begin
  delete from os_audit_log
   where action = 'agent_run' and at < now() - interval '180 days';
  get diagnostics n = row_count;
  return jsonb_build_object('pruned', n);
end $fn$;

revoke execute on function public.fn_audit_prune() from public, anon, authenticated;

comment on function public.trg_audit_agent_run() is
  'Every agent run writes an audit row: who acted, what happened, how long it took, and whether it failed. Fails open - auditing never blocks the work.';