-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709101415   name: fn_ws_ea
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_ea()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $fn$
  select jsonb_build_object(
    'today_events', a->'today'->'events',
    'reminders_due', a->'today'->'reminders_due',
    'upcoming_events', a->'upcoming_events',
    'open_tasks', a->'open_tasks',
    'overdue_tasks', (a->>'overdue_tasks')::int,
    'approvals_total', (a->'approvals_to_clear'->>'total')::int,
    'approvals_high_risk', (a->'approvals_to_clear'->>'high_risk')::int,
    'approvals_top', a->'approvals_to_clear'->'top',
    'recent_meetings', a->'recent_meetings'
  )
  from (select fn_ea_agenda(7) a) x;
$fn$;
revoke all on function public.fn_ws_ea() from anon, authenticated, public;
