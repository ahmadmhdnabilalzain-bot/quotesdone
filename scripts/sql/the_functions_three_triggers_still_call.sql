-- THE FUNCTIONS THREE LIVE TRIGGERS STILL CALL
--
-- The 7 September deletion removed 461 routines. plpgsql resolves a callee at RUN time, so every
-- trigger that called one kept existing and its table silently became UNWRITABLE. Measured by
-- driving a real insert at each product table inside an aborted transaction:
--
--   public.customers   refused every row: function is_disposable_email(text) does not exist
--   public.inquiries   refused every row: function mask_contacts_jsonb(jsonb) does not exist
--
-- No customer could register. No inquiry could be created. Nothing reported it, because nothing had
-- tried to write since the deletion -- the estate is on hold and the website had no traffic.
--
-- RESTORED RATHER THAN THEIR TRIGGERS DROPPED, because each still does something the product needs:
-- refusing a disposable signup address, and masking contact details out of an inquiry before the
-- supplier side can read it. Dropping the masking trigger would have left every inquiry fully
-- readable by suppliers -- a privacy failure introduced while tidying a schema.
--
-- Recovered verbatim from supabase/migrations_history, the record of what was actually applied.
-- That directory is read, never edited.

-- AND THE TABLE ONE OF THEM READS. is_disposable_email selects from app_blocked_domains, which the
-- deletion also removed -- so restoring the function alone still left customers unwritable, with a
-- different error. A dependency chain is not repaired one link at a time; it is repaired to the end.
-- The 24 disposable domains come back with it: an empty allow-everything table would look like a
-- working guard and block nothing.

create table if not exists app_blocked_domains (
  domain text primary key,
  reason text default 'disposable',
  created_at timestamptz default now()
);
insert into app_blocked_domains(domain) values
 ('mailinator.com'),('guerrillamail.com'),('10minutemail.com'),('yopmail.com'),
 ('trashmail.com'),('sharklasers.com'),('getnada.com'),('dispostable.com'),
 ('maildrop.cc'),('temp-mail.org'),('tempmail.com'),('throwawaymail.com'),
 ('fakeinbox.com'),('mailnesia.com'),('mintemail.com'),('mohmal.com'),
 ('emailondeck.com'),('discard.email'),('spam4.me'),('grr.la'),
 ('moakt.com'),('luxusmail.org'),('tempr.email'),('inboxkitten.com')
on conflict (domain) do nothing;

create or replace function is_disposable_email(p_email text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from app_blocked_domains d
    where d.domain = lower(split_part(p_email,'@',2))
  );
$$;

create or replace function public.mask_contacts_jsonb(j jsonb)
returns jsonb
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
declare r jsonb; k text; v jsonb; e jsonb;
begin
  if j is null then return j; end if;
  case jsonb_typeof(j)
    when 'string' then
      return to_jsonb(public.mask_contacts(j #>> '{}'));
    when 'object' then
      r := '{}'::jsonb;
      for k, v in select key, value from jsonb_each(j) loop
        r := r || jsonb_build_object(k, public.mask_contacts_jsonb(v));
      end loop;
      return r;
    when 'array' then
      r := '[]'::jsonb;
      for e in select value from jsonb_array_elements(j) loop
        r := r || jsonb_build_array(public.mask_contacts_jsonb(e));
      end loop;
      return r;
    else
      return j;
  end case;
end;
$function$;

create or replace function public.mask_name(t text, nm text)
returns text language plpgsql immutable set search_path to 'public','pg_temp' as $function$
declare s text := t; part text;
begin
  if s is null or s = '' or nm is null or btrim(nm) = '' then return s; end if;
  s := regexp_replace(s, '\y' || regexp_replace(btrim(nm), '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '\y', '[hidden]', 'gi');
  for part in select unnest(regexp_split_to_array(btrim(nm), '\s+')) loop
    if length(part) >= 3 then
      s := regexp_replace(s, '\y' || regexp_replace(part, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '\y', '[hidden]', 'gi');
    end if;
  end loop;
  return s;
end;
$function$;

