-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260630172659   name: quote_leak_guard
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- Leak-guard: mask off-platform contact details a supplier might slip into quote free-text
-- so they can't bypass the reveal fee or break pre-reveal anonymity. Original uploaded
-- file (released only AFTER paid reveal) is intentionally NOT touched.

create or replace function public.mask_contacts(t text)
returns text
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare s text := t;
begin
  if s is null or s = '' then return s; end if;
  -- emails
  s := regexp_replace(s, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', '[hidden]', 'gi');
  -- explicit URLs
  s := regexp_replace(s, '(https?://|www\.)[^[:space:]]+', '[hidden]', 'gi');
  -- bare social / messenger short links (no scheme)
  s := regexp_replace(s, '(wa\.me|t\.me|bit\.ly|instagram\.com|facebook\.com|fb\.com|linkedin\.com|twitter\.com|x\.com)/[^[:space:]]*', '[hidden]', 'gi');
  -- international UAE numbers (+971 ...)
  s := regexp_replace(s, '\+?971[ \-]?[0-9][0-9 \-]{6,}[0-9]', '[hidden]', 'g');
  -- local UAE mobile  05x xxx xxxx  (9 digits starting 5, optional separators) — bounded so prices/qtys are safe
  s := regexp_replace(s, '\y0?5[0-9][ \-]?[0-9]{3}[ \-]?[0-9]{4}\y', '[hidden]', 'g');
  return s;
end;
$$;

create or replace function public.scrub_quote_contacts()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare changed boolean := false;
begin
  if new.notes         is distinct from public.mask_contacts(new.notes)         then new.notes         := public.mask_contacts(new.notes);         changed := true; end if;
  if new.scope         is distinct from public.mask_contacts(new.scope)         then new.scope         := public.mask_contacts(new.scope);         changed := true; end if;
  if new.conditions    is distinct from public.mask_contacts(new.conditions)    then new.conditions    := public.mask_contacts(new.conditions);    changed := true; end if;
  if new.exclusions    is distinct from public.mask_contacts(new.exclusions)    then new.exclusions    := public.mask_contacts(new.exclusions);    changed := true; end if;
  if new.payment_terms is distinct from public.mask_contacts(new.payment_terms) then new.payment_terms := public.mask_contacts(new.payment_terms); changed := true; end if;
  if new.warranty      is distinct from public.mask_contacts(new.warranty)      then new.warranty      := public.mask_contacts(new.warranty);      changed := true; end if;
  if new.lead_time     is distinct from public.mask_contacts(new.lead_time)     then new.lead_time     := public.mask_contacts(new.lead_time);     changed := true; end if;
  if new.validity      is distinct from public.mask_contacts(new.validity)      then new.validity      := public.mask_contacts(new.validity);      changed := true; end if;
  if changed then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn', 'quote_contact_masked',
              'Masked off-platform contact details in quote for inquiry '||coalesce(new.inquiry_id::text,'?')||' from supplier '||coalesce(new.supplier_id::text,'?')||'.',
              'system');
    exception when others then null; end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_scrub_quote_contacts on public.quotes;
create trigger trg_scrub_quote_contacts
  before insert or update on public.quotes
  for each row execute function public.scrub_quote_contacts();

