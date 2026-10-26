-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709101112   name: ea_tables_agenda_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- founder calendar / meetings / travel entries (manual now; calendar connectors can populate later)
create table if not exists public.ea_events (
  id bigint generated always as identity primary key,
  kind text not null default 'meeting',      -- meeting, call, travel, event, deadline
  title text not null,
  starts_at timestamptz, ends_at timestamptz, all_day boolean default false,
  location text, attendees text[], notes text,
  source text default 'manual', external_id text,
  status text default 'scheduled',            -- scheduled, done, cancelled
  created_at timestamptz not null default now()
);
create index if not exists ea_events_start on public.ea_events(starts_at);
create table if not exists public.ea_reminders (
  id bigint generated always as identity primary key,
  title text not null, remind_at timestamptz not null, notes text,
  done boolean default false, done_at timestamptz, notified_at timestamptz,
  source text default 'manual', created_at timestamptz not null default now()
);
create index if not exists ea_reminders_at on public.ea_reminders(remind_at) where not done;
create table if not exists public.ea_meetings (
  id bigint generated always as identity primary key,
  title text, meeting_at timestamptz default now(), attendees text[],
  summary text, decisions jsonb default '[]'::jsonb, action_items jsonb default '[]'::jsonb,
  source text default 'manual', created_at timestamptz not null default now()
);
revoke all on public.ea_events, public.ea_reminders, public.ea_meetings from anon, authenticated;

-- consolidated founder agenda / daily briefing
create or replace function public.fn_ea_agenda(p_days int default 7)
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog'
as $fn$
  select jsonb_build_object(
    'as_of', now(),
    'today', jsonb_build_object(
      'events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location,'attendees',attendees) order by starts_at)
          from ea_events where status='scheduled' and coalesce(starts_at, now())::date = current_date),'[]'::jsonb),
      'reminders_due', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'remind_at',remind_at) order by remind_at)
          from ea_reminders where not done and remind_at <= now()+interval '1 day'),'[]'::jsonb)
    ),
    'upcoming_events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location) order by starts_at)
        from ea_events where status='scheduled' and starts_at > current_date and starts_at <= (current_date + (p_days||' days')::interval)),'[]'::jsonb),
    'open_tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'priority',priority,'due',due_date,'source',source) order by (due_date is null), due_date)
        from (select * from crm_tasks where coalesce(status,'')<>'done' order by (due_date is null), due_date limit 15) t),'[]'::jsonb),
    'overdue_tasks', (select count(*) from crm_tasks where coalesce(status,'')<>'done' and due_date < now()),
    'approvals_to_clear', jsonb_build_object(
      'total',(select count(*) from agent_actions where status in ('pending','needs_review')),
      'high_risk',(select count(*) from agent_actions where status in ('pending','needs_review') and coalesce(risk,'') in ('high','critical')),
      'top', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'title',title,'risk',risk) order by (coalesce(risk,'')='high') desc, created_at desc)
          from (select * from agent_actions where status in ('pending','needs_review') order by (coalesce(risk,'')='high') desc, created_at desc limit 8) a),'[]'::jsonb)
    ),
    'recent_meetings', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'meeting_at',meeting_at,'summary',left(summary,240)) order by meeting_at desc)
        from (select * from ea_meetings order by meeting_at desc limit 5) m),'[]'::jsonb)
  );
$fn$;
revoke all on function public.fn_ea_agenda(int) from anon, authenticated, public;

-- EA agent: surfaces due reminders, nudges overdue follow-ups, snapshots the agenda
create table if not exists public.ea_snapshots (id bigint generated always as identity primary key, snapshot_date date not null default current_date, agenda jsonb not null, created_at timestamptz not null default now());
create unique index if not exists ea_snap_day on public.ea_snapshots(snapshot_date);
revoke all on public.ea_snapshots from anon, authenticated;

create or replace function public.fn_ea_assistant()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare v_agenda jsonb; n_rem int:=0; n_nudge int:=0; rec record;
begin
  v_agenda := fn_ea_agenda(7);
  insert into ea_snapshots(snapshot_date, agenda) values (current_date, v_agenda)
    on conflict (snapshot_date) do update set agenda=excluded.agenda, created_at=now();

  -- mark due reminders as notified (they surface in the agenda; internal only)
  update ea_reminders set notified_at=now() where not done and remind_at <= now() and notified_at is null;
  select count(*) into n_rem from ea_reminders where not done and remind_at <= now();

  -- nudge: overdue tasks/follow-ups -> founder-visible EA reminder action (de-duped daily)
  if (select count(*) from crm_tasks where coalesce(status,'')<>'done' and due_date < now()) > 0
     and not exists (select 1 from agent_actions where agent='executive_assistant' and detail->>'signal'='overdue_followups' and status in ('pending','needs_review') and created_at::date=current_date) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values('executive_assistant','handoff','pending','low','Overdue follow-ups need your attention',
      (select count(*)::text from crm_tasks where coalesce(status,'')<>'done' and due_date < now())||' task(s)/follow-up(s) are past due. Review your open items in the agenda.',
      jsonb_build_object('signal','overdue_followups'),'ea','overdue');
    n_nudge:=1;
  end if;

  return jsonb_build_object('ran_at',now(),'reminders_due',n_rem,'nudged',n_nudge,'agenda',v_agenda);
end $fn$;
revoke all on function public.fn_ea_assistant() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('executive_assistant','Executive Assistant','🗓️',true,
  'The founder''s executive assistant. Keeps a single agenda across calendar/meetings, tasks, follow-ups, reminders and the approvals queue; delivers a daily briefing; summarises meetings into decisions and action items (which become tracked tasks); and keeps documents and follow-ups organised. It prepares, reminds and drafts — it does not send external emails, book travel, or take irreversible actions without the founder. Live calendar and email sync require the Google Calendar / Gmail connectors to be authorised.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

select cron.schedule('ea_assistant_daily','0 4 * * *', $$select public.fn_ea_assistant();$$);
