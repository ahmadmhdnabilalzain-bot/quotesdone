-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260611104817   name: invite_enqueue_function
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function enqueue_supplier_invites(p_cap int default null)
returns int language plpgsql security definer as $$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_cap int := coalesce(p_cap, (select value::int from app_secrets where key='invite_daily_cap'), 40);
  v_used int; v_remaining int; v_subj text; v_body text; v_count int;
begin
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then
    return 0;
  end if;
  select value into v_subj from app_secrets where key='invite_subject';
  select value into v_body from app_secrets where key='invite_body';
  select count(*) into v_used from notifications
    where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today;
  v_remaining := greatest(0, v_cap - v_used);
  if v_remaining <= 0 then return 0; end if;

  with elig as (
    select distinct on (lower(email)) id, email
    from leads
    where email is not null and email <> ''
      and invite_status is null
      and coalesce(source,'') <> 'self_registered'
      and coalesce(claimed,false) = false
    order by lower(email), id
    limit v_remaining
  ),
  ins as (
    insert into notifications(type,to_email,to_role,lead_id,subject,body,status,created_at)
    select 'supplier_invite', email, 'supplier', id, v_subj, v_body, 'queued', now()
    from elig
    returning to_email
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and lower(email) in (select lower(to_email) from ins);
  get diagnostics v_count = row_count;
  return v_count;
end; $$;

-- daily schedule (09:00 UTC = 1pm UAE); enqueues up to the cap, outbox cron sends them
select cron.unschedule(jobid) from cron.job where jobname='supplier_invites_daily';
select cron.schedule('supplier_invites_daily','0 9 * * *', $$ select enqueue_supplier_invites(); $$);
select jobname, schedule, active from cron.job where jobname='supplier_invites_daily';
