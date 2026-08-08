-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260701135157   name: whatsapp_notification_fanout
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- Opt-in flags (default off; enable per recipient / at registration later). Transactional service alerts only.
alter table leads add column if not exists wa_optin boolean default false;
alter table customers add column if not exists wa_optin boolean default false;

-- When an email notification is created for an opted-in supplier/customer who has a phone on file,
-- automatically queue a parallel WhatsApp copy. The existing send_whatsapp cron drains it.
create or replace function fn_wa_fanout() returns trigger language plpgsql security definer as $$
declare ph text; opt boolean := false;
begin
  -- only fan out plain email rows; never recurse on whatsapp rows
  if coalesce(NEW.channel,'email') <> 'email' then return NEW; end if;
  if NEW.to_email is null then return NEW; end if;

  if NEW.to_role = 'supplier' then
    select coalesce(nullif(btrim(l.whatsapp),''), l.phone), coalesce(l.wa_optin,false)
      into ph, opt from leads l
      where (NEW.lead_id is not null and l.id = NEW.lead_id)
         or (NEW.lead_id is null and lower(l.email) = lower(NEW.to_email))
      order by (l.id = NEW.lead_id) desc nulls last
      limit 1;
  elsif NEW.to_role = 'customer' then
    select c.phone, coalesce(c.wa_optin,false)
      into ph, opt from customers c where lower(c.email) = lower(NEW.to_email) limit 1;
  else
    return NEW;
  end if;

  if opt is true and ph is not null and length(regexp_replace(ph, '[^0-9]', '', 'g')) >= 8 then
    insert into notifications(type, to_email, to_role, to_phone, lead_id, inquiry_id, quote_id, subject, body, channel, status)
    values (NEW.type, NEW.to_email, NEW.to_role, ph, NEW.lead_id, NEW.inquiry_id, NEW.quote_id, NEW.subject, NEW.body, 'whatsapp', 'queued');
  end if;
  return NEW;
end $$;

drop trigger if exists trg_wa_fanout on notifications;
create trigger trg_wa_fanout after insert on notifications
  for each row execute function fn_wa_fanout();

