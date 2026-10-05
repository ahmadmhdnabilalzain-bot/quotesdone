-- THE WHATSAPP TEMPLATE REGISTRY IS STAMPED BY EVERY TWILIO RE-READ (it_engineer, 6 Oct 2026).
--
-- every_provider_cap_and_renewal_date_is_recorded fails: "pending templates to re-read at Twilio and
-- Meta". Measured 6 Oct 2026: 7 rows of public.wa_template_registry sit at 'pending' with checked_at
-- 21 Sep 2026 17:28 UTC, 15 days ago. They WERE re-read: wa_templates_watch asks Twilio about every
-- undecided template once a day and last did so on 5 Oct 07:30 UTC - but it writes the answer only to
-- public.messaging_template (the register send_whatsapp reads). wa_template_registry was filled by hand
-- on 21 Sep and nothing has written it since, so the check measured the age of a hand-kept copy.
--
-- The cause is two registers with one writer. A trigger on messaging_template now carries each fresh
-- verdict to the registry row of the same name:
--   approved / rejected            -> that status, checked_at = the read, approved_on on approval
--   received / pending / submitted /
--   in_review / unsubmitted        -> stays 'pending' (still waiting on Meta), checked_at = the read
--   anything else ('404', 'unknown', an error) -> NOT stamped. Twilio no longer holding the content is
--     not a re-read of a pending template; the row stays stale and the check keeps naming it.
-- The verdicts already read are carried across once, below.
-- prevented by: scripts/checks/every_provider_cap_and_renewal_date_is_recorded.test.mjs (reads live).

create or replace function public.fn_wa_template_registry_follows_messaging_template()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_status text;
begin
  if new.channel is distinct from 'whatsapp' or new.last_checked_at is null then return new; end if;
  v_status := case when new.status in ('approved', 'rejected') then new.status
                   when new.status in ('received', 'pending', 'submitted', 'in_review', 'unsubmitted') then 'pending' end;
  if v_status is null then return new; end if;
  update public.wa_template_registry r
     set status = v_status,
         checked_at = new.last_checked_at,
         approved_on = case when v_status = 'approved' then coalesce(r.approved_on, new.last_checked_at::date) else r.approved_on end,
         source = 'wa_templates_watch: Twilio Content API said "' || new.status || '" on '
                  || to_char(new.last_checked_at at time zone 'UTC', 'DD Mon YYYY HH24:MI') || ' UTC (messaging_template ' || new.sid || ')'
   where r.template_name = new.name
     and (r.checked_at is null or r.checked_at < new.last_checked_at);
  return new;
end $fn$;
revoke execute on function public.fn_wa_template_registry_follows_messaging_template() from public, anon, authenticated;

drop trigger if exists z50_wa_template_registry_follows on public.messaging_template;
create trigger z50_wa_template_registry_follows
  after insert or update of status, last_checked_at on public.messaging_template
  for each row execute function public.fn_wa_template_registry_follows_messaging_template();

-- carry across the verdicts already read (the same mapping as the trigger)
update public.wa_template_registry r
   set status = m.v_status,
       checked_at = m.last_checked_at,
       approved_on = case when m.v_status = 'approved' then coalesce(r.approved_on, m.last_checked_at::date) else r.approved_on end,
       source = 'wa_templates_watch: Twilio Content API said "' || m.status || '" on '
                || to_char(m.last_checked_at at time zone 'UTC', 'DD Mon YYYY HH24:MI') || ' UTC (messaging_template ' || m.sid || ')'
  from (select distinct on (name) name, sid, status, last_checked_at,
               case when status in ('approved', 'rejected') then status
                    when status in ('received', 'pending', 'submitted', 'in_review', 'unsubmitted') then 'pending' end as v_status
          from public.messaging_template
         where channel = 'whatsapp' and last_checked_at is not null
         order by name, last_checked_at desc) m
 where r.template_name = m.name and m.v_status is not null
   and (r.checked_at is null or r.checked_at < m.last_checked_at);

-- It has a writer now, so it is no longer frozen "no_writer": it is exported beside messaging_template.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('wa_template_registry', true, 'conversation', 'The WhatsApp templates'' purpose and Meta status, kept in step with messaging_template by trigger z50_wa_template_registry_follows (6 Oct 2026).', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- PROBE (a verdict row; this file defines a routine, so it never raises)
select case
  when not exists (select 1 from pg_trigger where tgname = 'z50_wa_template_registry_follows'
                     and tgrelid = 'public.messaging_template'::regclass)
    then 'PROBE FAILED: the trigger is not on messaging_template'
  when exists (select 1 from public.wa_template_registry r join public.messaging_template m
                 on m.channel = 'whatsapp' and m.name = r.template_name
                where m.status in ('approved', 'rejected', 'received', 'pending', 'submitted', 'in_review', 'unsubmitted')
                  and m.last_checked_at > coalesce(r.checked_at, '-infinity'))
    then 'PROBE FAILED: a registry row is older than the Twilio verdict already read for it'
  else 'PROBE OK'
end as verdict;
