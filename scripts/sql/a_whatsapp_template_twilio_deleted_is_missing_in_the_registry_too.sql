-- A WHATSAPP TEMPLATE TWILIO DELETED IS 'MISSING' IN THE REGISTRY TOO (it_engineer, 13 Oct 2026).
--
-- every_provider_cap_and_renewal_date_is_recorded fails: "no WhatsApp template waits more than 14 days without
-- being read again" names quotesdone_login_code_{en_mu6eslpb,ar_mu6esobi} and
-- quotesdone_supplier_account_notice_{en_mu6esqkz,ar_mu6est8z}.
--
-- MEASURED (read-only, production htdblwldjkcgjvmqkbeh, 13 Oct 2026 07:10 UTC): all four WERE re-read. In
-- public.messaging_template each is status 'missing', last_http_status 404, last_checked_at 5 Oct 07:30 UTC --
-- Twilio no longer holds the Content SID; each was superseded by an approved *_mul7343u template (12 Oct).
-- public.wa_template_registry still says 'pending', checked_at 21 Sep, because
-- fn_wa_template_registry_follows_messaging_template (the_whatsapp_template_registry_is_stamped_by_every_twilio_re_read.sql,
-- 6 Oct) carries only approved / rejected / still-waiting verdicts and leaves anything else unstamped -- written
-- before #1256 (a_whatsapp_template_twilio_no_longer_has_is_missing_not_404.sql) made 'missing' a real, final
-- verdict. The registry's CHECK has no 'missing' either. So the registry says a deleted template is waiting on
-- Meta, which is false, and the check is right to name it.
--
-- WHAT THIS DOES: the registry accepts 'missing'; the trigger carries 'missing' across like 'rejected' (final,
-- checked_at = the read); the verdicts already read are carried across once. An HTTP error or 'unknown' is still
-- not stamped.
-- prevented by: scripts/checks/every_provider_cap_and_renewal_date_is_recorded.test.mjs (reads live) and the
-- verdict row below.
--   node scripts/apply_sql.mjs scripts/sql/a_whatsapp_template_twilio_deleted_is_missing_in_the_registry_too.sql --apply --ddl --seat it_engineer

alter table public.wa_template_registry drop constraint if exists wa_template_registry_status_check;
alter table public.wa_template_registry add constraint wa_template_registry_status_check
  check (status = any (array['approved', 'pending', 'rejected', 'unsubmitted', 'missing']));

create or replace function public.fn_wa_template_registry_follows_messaging_template()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_status text;
begin
  if new.channel is distinct from 'whatsapp' or new.last_checked_at is null then return new; end if;
  v_status := case when new.status in ('approved', 'rejected', 'missing') then new.status
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

-- carry across the 'missing' verdicts already read (the same mapping as the trigger)
update public.wa_template_registry r
   set status = 'missing',
       checked_at = m.last_checked_at,
       source = 'wa_templates_watch: Twilio Content API said "missing" (HTTP ' || coalesce(m.last_http_status::text, '?') || ') on '
                || to_char(m.last_checked_at at time zone 'UTC', 'DD Mon YYYY HH24:MI') || ' UTC (messaging_template ' || m.sid || ')'
  from (select distinct on (name) name, sid, status, last_checked_at, last_http_status
          from public.messaging_template
         where channel = 'whatsapp' and last_checked_at is not null
         order by name, last_checked_at desc) m
 where r.template_name = m.name and m.status = 'missing'
   and (r.checked_at is null or r.checked_at < m.last_checked_at);

select case
  when not exists (select 1 from pg_proc where proname = 'fn_wa_template_registry_follows_messaging_template'
                    and prosrc like '%''approved'', ''rejected'', ''missing''%')
    then 'PROBE FAILED: the trigger does not carry missing'
  when exists (select 1 from public.wa_template_registry r join public.messaging_template m on m.name = r.template_name
                where m.channel = 'whatsapp' and m.status = 'missing' and r.status <> 'missing')
    then 'PROBE FAILED: a template Twilio deleted still reads otherwise in the registry'
  when exists (select 1 from public.wa_template_registry where status = 'pending' and checked_at < now() - interval '14 days')
    then 'PROBE FAILED: a pending template is still unread for 14 days'
  else 'PROBE OK' end as verdict;
