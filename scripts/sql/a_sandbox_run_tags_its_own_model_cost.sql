-- A SANDBOX RUN TAGS ITS OWN MODEL COST, SO ITS CLEANUP REMOVES EXACTLY THOSE ROWS.
-- Seat: it_engineer. Ledger 1119 (stage-2 sandbox e2e, scripts/e2e/stage2.mjs).
--
-- Measured 6 Oct 2026: ai_cost_log has no inquiry, customer or run column. The stage-2 cleanup could
-- remove a run's cost rows only by a time window, and only when nothing real happened in that window.
-- The founder's rule is that no agent learns from demo traffic, and the coordinator ruled the window
-- out as guessing. So the row carries the run tag itself.
--
-- WHERE THE TAG COMES FROM, in order:
--   1. app.e2e_run_tag, the session setting the aborted duty probes set (scripts/e2e/stage2_duties.mjs);
--   2. the x-qd-e2e-run request header that PostgREST exposes as request.headers. The harness sends
--      it, and _shared/observe.ts forwards it on every call an edge function makes back to this
--      project. That covers ai_gateway's fn_llm_log rpc, the hop that writes this row.
-- A TAG IS ONLY KEPT FOR A RUN THAT IS OPEN. A header is caller-controlled, so a tag that does not name
-- an open rehearsal_window (opened by the harness with the service role) is dropped. A real caller
-- cannot mark its own cost rows for the cleanup to delete.
--
-- NOT CHANGED: fn_llm_log's signature and body. The trigger runs on the insert fn_llm_log already makes.
-- Production with no header and no setting behaves exactly as before: the column stays null.

alter table public.ai_cost_log add column if not exists e2e_run_tag text;
comment on column public.ai_cost_log.e2e_run_tag is
  'Run tag of the sandbox harness run that caused this model call (scripts/e2e/stage2.mjs). Null for all real traffic. Set by trg_ai_cost_log_e2e_run_tag; cleanup deletes by it.';

create or replace function public.fn_ai_cost_log_e2e_run_tag()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_tag text;
begin
  v_tag := coalesce(new.e2e_run_tag,
                    nullif(current_setting('app.e2e_run_tag', true), ''),
                    nullif(current_setting('request.headers', true), '')::json ->> 'x-qd-e2e-run');
  if v_tag is not null and (v_tag !~ '^[a-z0-9]{4,16}$' or not exists (
        select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || v_tag and w.ended_at is null)) then
    v_tag := null;
  end if;
  new.e2e_run_tag := v_tag;
  return new;
exception when others then
  -- request.headers that is not JSON must never cost the company its cost record
  new.e2e_run_tag := null;
  return new;
end $fn$;

revoke execute on function public.fn_ai_cost_log_e2e_run_tag() from public, anon, authenticated;

drop trigger if exists trg_ai_cost_log_e2e_run_tag on public.ai_cost_log;
create trigger trg_ai_cost_log_e2e_run_tag before insert on public.ai_cost_log
  for each row execute function public.fn_ai_cost_log_e2e_run_tag();

create index if not exists ai_cost_log_e2e_run_tag_idx on public.ai_cost_log (e2e_run_tag) where e2e_run_tag is not null;
