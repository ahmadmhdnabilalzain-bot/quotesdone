-- THE QUOTE LEAK GUARD, REUNITED WITH ITS IMPLEMENTATION
--
-- public.quotes carries trg_mask_quote_contact, which strips contact details out of a quotation
-- free-text field so a supplier cannot put a phone number in the scope and reach the buyer around
-- the platform. It called mask_contact(text) -- SINGULAR. No committed file in this repository has
-- ever defined that name: the implementation in history is mask_contacts (PLURAL), and the
-- singular was created by a direct apply that never reached a file.
--
-- When the 7 September deletion removed it, the trigger kept calling a name with no definition
-- anywhere, and every quotation carrying a scope, notes, conditions or exclusions failed to insert.
--
-- The real implementation is restored under the name history actually has, and the trigger is
-- rewritten to call THAT. Reuniting the two is the fix; a wrapper called mask_contact would
-- preserve the split that caused this.
--
-- MY WRITE PROBE MISSED THIS ENTIRELY, which is the lesson worth keeping. The probe inserted the
-- minimum a quotes row needs, and the minimum has no scope, so the trigger never fired and
-- public.quotes reported writable. A probe thin enough to always pass proves nothing.

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

-- The trigger function, now calling a name that exists. Four fields, because a leak in the
-- exclusions is as reachable to a buyer as a leak in the scope.
create or replace function public.trg_mask_quote_contact()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  new.notes      := public.mask_contacts(new.notes);
  new.scope      := public.mask_contacts(new.scope);
  new.conditions := public.mask_contacts(new.conditions);
  new.exclusions := public.mask_contacts(new.exclusions);
  return new;
end $function$;
