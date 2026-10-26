-- The knowledge-decay backfill alone wrote 1,003 undo rows, so this table will grow fast.
-- 90 days is well beyond any realistic "undo that change" window; unreverted rows older
-- than that are history, not a reverse gear.
create or replace function public.fn_audit_prune()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare n_audit int; n_undo int;
begin
  delete from os_audit_log where action='agent_run' and at < now() - interval '180 days';
  get diagnostics n_audit = row_count;

  delete from undo_log where created_at < now() - interval '90 days';
  get diagnostics n_undo = row_count;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('audit_prune', now(), now(), 'ok',
          jsonb_build_object('audit_pruned',n_audit,'undo_pruned',n_undo),
          'Retention: '||n_audit||' agent-run audit rows and '||n_undo||' undo rows older than their window removed.');

  return jsonb_build_object('audit_pruned',n_audit,'undo_pruned',n_undo);
end $fn$;
revoke execute on function public.fn_audit_prune() from public, anon, authenticated;
create index if not exists undo_log_created_idx on public.undo_log (created_at);