-- Audit 9.3 prerequisite. inquiries_supplier_safe is the intended single supplier-facing
-- projection, but the write-time masking behind it was WEAKER than the retrieval-time redactor in
-- supplier_api, so switching the inbox to the view would have reduced protection.
--
-- Demonstrated on production in a rolled-back transaction before this change:
--   summary -> 'Call Ahmed Al Rashid on [hidden] or [hidden] about Villa 42 Emirates Hills,
--               see acme-trading.ae'      <- bare domain survived
--   budget  -> 'around AED 90,000 - call 04-3345566'   <- UAE landline survived
--
-- mask_contacts covered emails, explicit URLs, a short social allow-list, +971 numbers and 05x
-- mobiles. It did not cover UAE landlines (02/03/04/06/07/09), bare domains without a scheme, or
-- the buyer's own name. This brings write-time masking up to at least the retrieval-time standard,
-- so the view can become the single source without losing ground.

create or replace function public.mask_contacts(t text)
returns text language plpgsql immutable set search_path to 'public','pg_temp' as $function$
declare s text := t;
begin
  if s is null or s = '' then return s; end if;
  -- emails
  s := regexp_replace(s, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', '[hidden]', 'gi');
  -- explicit URLs
  s := regexp_replace(s, '(https?://|www\.)[^[:space:]]+', '[hidden]', 'gi');
  -- social / messenger short links (no scheme)
  s := regexp_replace(s, '(wa\.me|t\.me|bit\.ly|instagram\.com|facebook\.com|fb\.com|linkedin\.com|twitter\.com|x\.com)/[^[:space:]]*', '[hidden]', 'gi');
  -- international UAE numbers (+971 ...)
  s := regexp_replace(s, '\+?971[ \-]?[0-9][0-9 \-]{6,}[0-9]', '[hidden]', 'g');
  -- local UAE mobile 05x xxx xxxx
  s := regexp_replace(s, '\y0?5[0-9][ \-]?[0-9]{3}[ \-]?[0-9]{4}\y', '[hidden]', 'g');
  -- NEW: UAE landlines - area codes 02 03 04 06 07 09 then 7 digits, separators optional.
  -- Anchored on a leading 0 and word boundaries so prices and quantities are unaffected.
  s := regexp_replace(s, '\y0[234679][ \-]?[0-9]{3}[ \-]?[0-9]{4}\y', '[hidden]', 'g');
  -- NEW: bare domains with no scheme (acme-trading.ae). Requires a 2+ character label and a known
  -- TLD, so decimals, part numbers and version strings are not touched.
  s := regexp_replace(s,
        '\y[A-Za-z0-9][A-Za-z0-9\-]{1,62}(\.[A-Za-z0-9\-]{1,62})*\.(ae|com|net|org|io|co|me|info|biz|shop|store|online|site|app|dev)\y',
        '[hidden]', 'gi');
  return s;
end;
$function$;

-- NEW: redact a person's name and its parts, word-boundary anchored so ordinary words survive.
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

-- Apply the buyer's own name to the supplier-facing copies. supplier_api did this at retrieval
-- time from customers.full_name; doing it at write time means every reader inherits it.
create or replace function public.scrub_inquiry_contacts()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare changed boolean := false; v_name text;
begin
  new.summary_masked      := public.mask_contacts(new.summary);
  new.raw_input_masked    := public.mask_contacts(new.raw_input);
  new.budget_masked       := public.mask_contacts(new.budget);
  new.spec_masked         := public.mask_contacts_jsonb(new.spec);
  new.boq_masked          := public.mask_contacts_jsonb(new.boq);
  new.completeness_masked := public.mask_contacts_jsonb(new.completeness);

  if new.customer_id is not null then
    begin
      select nullif(btrim(c.full_name),'') into v_name from public.customers c where c.id = new.customer_id;
    exception when others then v_name := null; end;
    if v_name is not null then
      new.summary_masked   := public.mask_name(new.summary_masked,   v_name);
      new.raw_input_masked := public.mask_name(new.raw_input_masked, v_name);
      new.budget_masked    := public.mask_name(new.budget_masked,    v_name);
    end if;
  end if;

  changed := (new.summary_masked      is distinct from new.summary)
          or (new.raw_input_masked    is distinct from new.raw_input)
          or (new.budget_masked       is distinct from new.budget)
          or (new.spec_masked         is distinct from new.spec)
          or (new.boq_masked          is distinct from new.boq)
          or (new.completeness_masked is distinct from new.completeness);

  if changed then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn', 'inquiry_contact_masked',
              'Masked customer contact details in the supplier-facing copy of inquiry '||coalesce(new.id::text,'?')||' from customer '||coalesce(new.customer_id::text,'?')||'.',
              'system');
    exception when others then null; end;
  end if;
  return new;
end;
$function$;;
