-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260619131912   name: new_quote_sms_trigger
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.notify_new_quote_sms() returns trigger language plpgsql security definer as $$
declare inq record; c record;
begin
  select i.summary, i.customer_id into inq from public.inquiries i where i.id = NEW.inquiry_id;
  if inq.customer_id is null then return NEW; end if;
  select email, phone, phone_verified into c from public.customers where id = inq.customer_id;
  if c.phone is not null and coalesce(c.phone_verified,false) then
    insert into public.notifications(type, channel, to_phone, to_role, inquiry_id, quote_id, subject, body, status)
    values ('new_quote_sms','sms', c.phone, 'customer', NEW.inquiry_id, NEW.id, '',
      'QuotesDone: you have a new quote on your request'||coalesce(': '||left(inq.summary,80),'')||'. View & compare at quotesdone.com/app', 'queued');
  end if;
  return NEW;
end $$;

drop trigger if exists trg_new_quote_sms on public.quotes;
create trigger trg_new_quote_sms after insert on public.quotes
  for each row execute function public.notify_new_quote_sms();
