-- Seat: sales_engineer. Assigned: sales_engineer (founder_instruction / ledger 1697, 15 Nov 2026).
--
-- THE FOUNDER (1697), verbatim: "Quotation validity depends on what the supplier mentions in his quotation. No specific period".
--
-- MEASURED before this file (local Postgres 16 built from the mirror, every routine below md5-equal to production; SELECT on
-- production 15 Nov 2026):
--   * trg_quote_expiry (BEFORE INSERT on quotes, no source file in scripts/sql: it lived only in the database) gave every quote
--     an expiry of its own choosing: 14 days when the supplier stated nothing, any number found in the text read as days
--     ("valid until 30 Nov 2026" became 30 days, "valid till 15/12/2026" 15 days), months as 30 days, capped at 180 days, always
--     counted from the row's created_at, never from the quotation's own date. It ran on INSERT only, so a validity the supplier
--     stated later (the hold desk's spec_fill, a resubmission over a held option) never moved the expiry. EXECUTE was granted to
--     PUBLIC, anon and authenticated.
--   * the reveal period (a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql) filled a missing expiry with
--     created_at + 14 days in three routines: fn_sales_engineer_reveal_period_until, fn_sales_engineer_live_quotes_left and
--     fn_sales_engineer_tells_unchosen_suppliers. A quotation that stated no validity therefore stopped being revealable after
--     14 days, a period nobody stated.
--   * production holds 3 quotes; all 3 state "30 days" and carry created_at + 30 days. 0 quotes carry an expiry the supplier
--     did not state. No row is rewritten by this file (see BACKFILL at the end).
--
-- WHAT A QUOTATION'S EXPIRY IS NOW:
--   * public.fn_quote_validity_until(validity, quotation_date, received) reads the supplier's own words, deterministically:
--       - a period: "15 days", "validity: 30 days from date", "2 weeks", "one month", "10 working days", "صالح لمدة 15 يوما",
--         "صلاحية العرض ثلاثين يوماً", "أسبوعين", "شهر" — counted from the quotation's own date when we know it
--         (quotes.quotation_date, new), else from the day we received it (created_at, Dubai date); months are calendar
--         months; working days skip Saturday and Sunday (the UAE week since 2022; public holidays are not known here);
--         a range ("15-30 days") counts its shorter end; a period counted "from <date>" counts from that date;
--       - a date: "valid until 30 Nov 2026", "valid till 15/12/2026" (day first, as written in the UAE), "2026-12-15",
--         "Nov 30, 2026", "حتى 30 نوفمبر 2026", "end of November 2026" (its last day); a date without a year takes the
--         first such date on or after the day counted from;
--       - the quotation is valid to the END of its last day in Dubai (Asia/Dubai midnight that follows it);
--       - anything else ("subject to stock", "TBA", blank, "0 days", a period of more than ten years, a date that does not
--         exist): NULL. No expiry, and the customer reads "Validity: not stated by the supplier" or the supplier's own words.
--   * trg_quote_expiry: on INSERT it fills expires_at from that reading when the writer did not set one; on UPDATE OF
--     validity or quotation_date it reads again (to NULL too) unless the same statement set expires_at itself. No default,
--     no cap, no fallback period anywhere.
--   * the reveal period: a live quotation with no stated validity stays live (it has no end of its own); the period is still
--     capped at 30 days after the first paid reveal (decision B of 13 Nov 2026, a rule about the REQUEST, unchanged here).
--
-- Prevented by: scripts/checks/a_quotation_is_valid_for_the_period_the_supplier_states.test.mjs (this file's text, and no
-- routine source in the repository fills an expiry with a period of its own) and this file's _probe.sql (run on a local
-- Postgres 16: 63 wordings read, 51 that state a validity and 12 that state none, the trigger on insert and update, the three reveal-period routines).
-- Pending until the release applies it: scripts/sql/pending/<this name>.txt
--
-- THE APPLY MUST NOT FREEZE THE SITE: it adds a nullable column to quotes (ACCESS EXCLUSIVE, catalogue only, no rewrite) and
-- replaces one trigger; lock_timeout makes it FAIL after 1.5 seconds rather than queue live readers behind it.
set local lock_timeout = '1500ms';

-- ── 0. the quotation's own date ───────────────────────────────────────────────────────────────────────────────────────────
alter table public.quotes add column if not exists quotation_date date;
comment on column public.quotes.quotation_date is
  'sales_engineer (ledger 1697): the date printed on the supplier''s quotation, when the document states one (read by code from a labelled date line, or typed). A stated validity period is counted from it; when it is NULL, from the day we received the quotation (created_at). Never filled with a guess.';
comment on column public.quotes.expires_at is
  'sales_engineer (ledger 1697): the end of the validity the supplier stated (fn_quote_validity_until over validity and quotation_date, end of the last day in Dubai). NULL when he stated none we can read: the quotation then has no expiry, and nothing anywhere supplies a period of its own.';

-- ── 1. the reading (code; no model, no default) ───────────────────────────────────────────────────────────────────────────
-- Three routines, each one job: the month of a month name, the first date a text states, and the validity's end.
create or replace function public.fn_quote_validity_month(p text)
 returns int
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when p ~ '^(jan|يناير)' then 1 when p ~ '^(feb|فبراير)' then 2 when p ~ '^(mar|مارس)' then 3
    when p ~ '^(apr|أبريل|ابريل|إبريل)' then 4 when p ~ '^(may|مايو)' then 5 when p ~ '^(jun|يونيو)' then 6
    when p ~ '^(jul|يوليو)' then 7 when p ~ '^(aug|أغسطس|اغسطس)' then 8 when p ~ '^(sep|سبتمبر)' then 9
    when p ~ '^(oct|أكتوبر|اكتوبر)' then 10 when p ~ '^(nov|نوفمبر)' then 11 when p ~ '^(dec|ديسمبر)' then 12 end
$fn$;
revoke execute on function public.fn_quote_validity_month(text) from public, anon, authenticated;

-- The first calendar date a NORMALISED text states (fn_quote_validity_until normalises it), or NULL. Numeric dates are read day
-- first, as written in the UAE; a date without a year is the first such date on or after p_from; a date that does not exist
-- (31/02/2026, month 13, a US-style 12/15/2026) is NULL, never a guess.
create or replace function public.fn_quote_validity_date(p text, p_from date)
 returns date
 language plpgsql
 immutable
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  m text[]; v_dt date; v_year int; v_mon int; v_day int;
  c_months constant text :=
    '(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec'
    || '|يناير|فبراير|مارس|أبريل|ابريل|إبريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر)(?![a-zء-ي])';
begin
  if p is null or p = '' then return null; end if;
  m := regexp_match(p, '(?<!\d)(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})(?!\d)');
  if m is not null then
    v_dt := make_date(m[1]::int, m[2]::int, m[3]::int);
  else
    m := regexp_match(p, '(?<!\d)(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})(?!\d)');
  end if;
  if v_dt is null and m is not null then
    v_dt := make_date(case when length(m[3]) = 2 then 2000 + m[3]::int else m[3]::int end, m[2]::int, m[1]::int);
  end if;
  if v_dt is null then
    m := regexp_match(p, '(?<!\d)(\d{1,2}) ?(?:of )?' || c_months || '\.?,? ?(\d{4})?(?!\d)');
    if m is not null then
      v_day := m[1]::int; v_mon := public.fn_quote_validity_month(m[2]);
    else
      m := regexp_match(p, '(?<![a-zء-ي])' || c_months || '\.? (\d{1,2})(?!\d)(?:,? ?(\d{4}))?');
      if m is not null then v_day := m[2]::int; v_mon := public.fn_quote_validity_month(m[1]); m := array[m[2], m[1], m[3]]; end if;
    end if;
    if m is not null then
      v_year := coalesce(m[3]::int, extract(year from p_from)::int);
      v_dt := make_date(v_year, v_mon, v_day);
      if m[3] is null and v_dt < p_from then v_dt := make_date(v_year + 1, v_mon, v_day); end if;
    end if;
  end if;
  if v_dt is null then
    m := regexp_match(p, '(?:\mend of (?:the )?|(?<![ء-ي])نهاية (?:شهر )?)' || c_months || '(?: (\d{4}))?');
    if m is not null then
      v_mon := public.fn_quote_validity_month(m[1]); v_year := coalesce(m[2]::int, extract(year from p_from)::int);
      v_dt := (make_date(v_year, v_mon, 1) + interval '1 month - 1 day')::date;
      if m[2] is null and v_dt < p_from then v_dt := (make_date(v_year + 1, v_mon, 1) + interval '1 month - 1 day')::date; end if;
    elsif p ~ '(\mend of (?:the |this )?month\M|(?<![ء-ي])نهاية (?:هذا )?الشهر(?![ء-ي]))' then
      v_dt := (date_trunc('month', p_from) + interval '1 month - 1 day')::date;   -- the end of the month counted from
    end if;
  end if;
  if v_dt is not null and (extract(year from v_dt) < 2000 or extract(year from v_dt) > 2100) then return null; end if;
  return v_dt;
exception when others then
  return null;
end $fn$;
revoke execute on function public.fn_quote_validity_date(text, date) from public, anon, authenticated;

create or replace function public.fn_quote_validity_until(p_validity text, p_quotation_date date, p_received timestamptz)
 returns timestamptz
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v text; m text[]; v_from date; v_end date; v_dt date; v_n numeric; v_unit text; v_until text; v_since text; i int;
  c_until constant text := '(\muntil\M|\mtill\M|\mup ?to\M|\mexpir[a-z]*|\mvalid to\M|\mend of\M|(?<![ء-ي])(حتى|لغاية|إلى|الى|ينتهي|تنتهي|نهاية)(?![ء-ي]))';
  c_since constant text := '(\mfrom\M|\mstarting\M|\mw\.?e\.?f\M|(?<![ء-ي])(اعتبارا من|ابتداء من|من)(?![ء-ي]))';
begin
  v := btrim(coalesce(p_validity, ''));
  if v = '' then return null; end if;
  v_from := coalesce(p_quotation_date, (coalesce(p_received, now()) at time zone 'Asia/Dubai')::date);

  -- normalise: lower case, Arabic-Indic and Persian digits, Arabic diacritics and tatweel, brackets, ordinals, spacing
  v := lower(v);
  v := translate(v, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
  v := regexp_replace(v, '[ًٌٍَُِّْـ]', '', 'g');
  v := regexp_replace(v, '[()\[\]{}]', ' ', 'g');
  v := regexp_replace(v, '(\d)(st|nd|rd|th)\M', '\1', 'g');
  v := regexp_replace(v, '\s+', ' ', 'g');

  -- number words before a unit (English word-bounded; Arabic with no Arabic letter on either side; longest first)
  v := regexp_replace(v, '\mforty[- ]five\M', '45', 'g');
  for m in select array[w, n] from (values
      ('ninety','90'),('sixty','60'),('forty','40'),('thirty','30'),('twenty','20'),('fifteen','15'),('fourteen','14'),('twelve','12'),
      ('eleven','11'),('ten','10'),('nine','9'),('eight','8'),('seven','7'),('six','6'),('five','5'),('four','4'),('three','3'),
      ('two','2'),('one','1'),('a','1'),('an','1')) t(w, n) loop
    v := regexp_replace(v, '\m' || m[1] || '\M(?= (calendar |working |business )?(days?|weeks?|months?|years?)\M)', m[2], 'g');
  end loop;
  for m in select array[w, n] from (values
      ('خمسة وأربعين','45'),('خمسة واربعين','45'),('خمس وأربعين','45'),('خمس واربعين','45'),('خمسة عشرة','15'),('خمسة عشر','15'),
      ('خمس عشرة','15'),('تسعين','90'),('تسعون','90'),('ستين','60'),('ستون','60'),('خمسين','50'),('خمسون','50'),('أربعين','40'),
      ('اربعين','40'),('ثلاثين','30'),('ثلاثون','30'),('عشرين','20'),('عشرون','20'),('عشرة','10'),('عشر','10'),('سبعة','7'),
      ('سبع','7'),('خمسة','5'),('خمس','5'),('ثلاثة','3'),('ثلاث','3')) t(w, n) loop
    v := regexp_replace(v, '(?<![ء-ي])' || m[1] || '(?![ء-ي])', m[2], 'g');
  end loop;
  -- an Arabic dual is a number (يومين 2 days, أسبوعين 2 weeks, شهرين 2 months); a bare أسبوع or شهر is one
  v := regexp_replace(v, '(?<![ء-ي])(يومين|يومان)(?![ء-ي])', '2 يوم', 'g');
  v := regexp_replace(v, '(?<![ء-ي])(أسبوعين|اسبوعين|أسبوعان|اسبوعان)(?![ء-ي])', '2 أسبوع', 'g');
  v := regexp_replace(v, '(?<![ء-ي])(شهرين|شهران)(?![ء-ي])', '2 شهر', 'g');
  v := regexp_replace(v, '(?<![ء-ي])(سنتين|سنتان|عامين|عامان)(?![ء-ي])', '2 سنة', 'g');
  v := regexp_replace(v, '(?<!\d)(?<!\d )(?<![ء-ي])(أسبوع|اسبوع|شهرا|شهر|سنة|سنه)(?![ء-ي])(?! (يناير|فبراير|مارس|أبريل|ابريل|إبريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر))', '1 \1', 'g');

  -- (a) a stated last day: the first date after "until / till / حتى ..."; else a date with no "from" before it
  m := regexp_match(v, c_until || '(.*)$');
  v_until := case when m is null then null else m[array_length(m, 1)] end;
  m := regexp_match(v, c_since || '(.*)$');
  v_since := case when m is null then null else m[array_length(m, 1)] end;
  v_dt := public.fn_quote_validity_date(v_until, v_from);
  if v_dt is null and v ~ '\mend of (?:the |this )?month\M|(?<![ء-ي])نهاية (?:هذا )?الشهر(?![ء-ي])' then
    v_dt := public.fn_quote_validity_date(v, v_from);
  end if;

  -- (b) a stated period (the first one; a range counts its shorter end)
  m := regexp_match(v, '(\d+(?:\.\d+)?) ?(?:(?:-|to|–|إلى|الى) ?\d+(?:\.\d+)? ?)?'
    || '(working days?|business days?|calendar days?|days?|d(?![a-z])|weeks?|wks?|months?|mos?(?![a-z])|years?|yrs?(?![a-z])'
    || '|أيام عمل|ايام عمل|يوم عمل|يوما|يوم|أيام|ايام|أسابيع|اسابيع|أسبوع|اسبوع|أشهر|اشهر|شهور|شهرا|شهر|سنوات|سنة|سنه|عام)');

  if v_dt is null and m is null then
    v_dt := public.fn_quote_validity_date(v, v_from);        -- a bare date: "30 Nov 2026"
    if v_dt is not null and v_since is not null and public.fn_quote_validity_date(v_since, v_from) = v_dt then
      return null;                                          -- "from 1 Nov" names a start and no end: not a validity
    end if;
  end if;

  if v_dt is not null then
    v_end := v_dt;                                          -- a stated last day wins over a period beside it
  elsif m is not null then
    v_n := m[1]::numeric; v_unit := m[2];
    if v_n <= 0 or v_n >= 1000 then return null; end if;     -- "0 days" states no validity; a four-digit number is a year
    -- a period counted from a date the text names ("30 days from 1 Nov 2026"); else from the quotation's date / the day received
    v_from := coalesce(public.fn_quote_validity_date(v_since, v_from), v_from);
    if v_unit ~ '^(working|business|يوم عمل|أيام عمل|ايام عمل)' then
      if v_n <> trunc(v_n) or v_n > 2600 then return null; end if;
      v_end := v_from; i := 0;
      while i < v_n loop
        v_end := v_end + 1;
        if extract(isodow from v_end) < 6 then i := i + 1; end if;   -- Saturday (6) and Sunday (7) are not working days
      end loop;
    elsif v_unit ~ '^(week|wk|أسبوع|اسبوع|أسابيع|اسابيع)' then
      v_end := v_from + round(v_n * 7)::int;
    elsif v_unit ~ '^(year|yr|سنة|سنه|سنوات|عام)' then
      v_end := (v_from + make_interval(months => round(v_n * 12)::int))::date;
    elsif v_unit ~ '^(month|mo|شهر|أشهر|اشهر|شهور)' then
      v_end := (v_from + make_interval(months => trunc(v_n)::int) + make_interval(days => round((v_n - trunc(v_n)) * 30)::int))::date;
    else
      v_end := v_from + round(v_n)::int;
    end if;
    if v_end > v_from + 3653 then return null; end if;   -- more than ten years is not a quotation's validity
  else
    return null;
  end if;

  return ((v_end + 1)::timestamp at time zone 'Asia/Dubai');
end $fn$;
revoke execute on function public.fn_quote_validity_until(text, date, timestamptz) from public, anon, authenticated;
comment on function public.fn_quote_validity_until(text, date, timestamptz) is
  'sales_engineer (ledger 1697): the end of the validity the supplier states in his own words (a period from the quotation''s date, else from the day received; or a last day), end of that day in Dubai. NULL when he states none we can read. No default period, no cap.';

-- ── 2. the trigger: what the supplier stated, on insert and whenever his validity changes ─────────────────────────────────
create or replace function public.trg_quote_expiry()
 returns trigger
 language plpgsql
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  if tg_op = 'INSERT' then
    if NEW.expires_at is null then
      NEW.expires_at := public.fn_quote_validity_until(NEW.validity, NEW.quotation_date, coalesce(NEW.created_at, now()));
    end if;
  elsif (NEW.validity is distinct from OLD.validity or NEW.quotation_date is distinct from OLD.quotation_date)
        and NEW.expires_at is not distinct from OLD.expires_at then
    -- his validity changed and this statement did not set an expiry of its own: read it again (NULL when he now states none)
    NEW.expires_at := public.fn_quote_validity_until(NEW.validity, NEW.quotation_date, coalesce(NEW.created_at, now()));
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_quote_expiry() from public, anon, authenticated;
-- replaced in place (no gap between a drop and a create in which a quote is written unseen)
create or replace trigger trg_quote_expiry_b before insert or update of validity, quotation_date on public.quotes
  for each row execute function public.trg_quote_expiry();

-- ── 3. the reveal period: a quotation with no stated validity has no end of its own ───────────────────────────────────────
-- Redefined from the live bodies (pg_get_functiondef, md5-equal to production on 15 Nov 2026); the only change in each is the
-- 14-day fill for a missing expiry.
create or replace function public.fn_sales_engineer_reveal_period_until(p_inquiry uuid, p_cap timestamptz)
 returns timestamptz
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select least(p_cap, coalesce(max(coalesce(q.expires_at, p_cap)), now()))
    from public.quotes q
   where q.inquiry_id = p_inquiry
     and coalesce(q.status, '') not in ('withdrawn', 'expired', 'revealed', 'rejected', 'cancelled')
     and (coalesce(q.status, '') <> 'draft'
          or exists (select 1 from public.quote_quality_hold h where h.quote_id = q.id and h.released_at is null))
     and (q.expires_at is null or q.expires_at > now())
     and not exists (select 1 from public.transactions x where x.quote_id = q.id and x.fee_status = 'paid')
$fn$;
revoke execute on function public.fn_sales_engineer_reveal_period_until(uuid, timestamptz) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_live_quotes_left(p_inquiry uuid)
 returns integer
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select count(*)::int from public.quotes q
   where q.inquiry_id = p_inquiry
     and coalesce(q.status, '') not in ('withdrawn', 'expired', 'revealed', 'rejected', 'cancelled')
     and (coalesce(q.status, '') <> 'draft'
          or exists (select 1 from public.quote_quality_hold h where h.quote_id = q.id and h.released_at is null))
     and (q.expires_at is null or q.expires_at > now())
     and not exists (select 1 from public.transactions x where x.quote_id = q.id and x.fee_status = 'paid')
$fn$;
revoke execute on function public.fn_sales_engineer_live_quotes_left(uuid) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_tells_unchosen_suppliers(p_inquiry uuid, p_event text, p_until timestamptz)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare i public.inquiries; c public.customers; v_fx boolean; l record; v_why text; v_d jsonb; v_key text; v_round int;
  v_type text; v_subject text; v_body text; v_no text; v_out jsonb := '[]'::jsonb;
begin
  if p_event not in ('reveal_open', 'ended', 'reopened') then raise exception 'event is reveal_open, ended or reopened, not %', p_event; end if;
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return v_out; end if;
  select * into c from public.customers where id = i.customer_id;
  v_fx := coalesce(public.fn_seat_clock_customer_is_fixture(c), false);
  v_no := coalesce(i.rfq_no::text, '-');
  -- an ending after a re-opening is a new event: the round is the number of re-openings so far
  select count(*) into v_round from public.company_event e where e.event_type = 'request.reopened' and e.payload->>'inquiry_id' = p_inquiry::text;
  v_type := case p_event when 'reveal_open' then 'quote_not_selected' when 'ended' then 'request_ended' else 'request_reopened' end;
  for l in select le.id, coalesce(public.fn_supplier_address(le.claimed_by, le.email), '') as to_email
             from (select distinct q.supplier_id from public.quotes q
                    where q.inquiry_id = p_inquiry and q.supplier_id is not null
                      and coalesce(q.status, '') not in ('withdrawn')
                      and (coalesce(q.status, '') <> 'draft'
                           or exists (select 1 from public.quote_quality_hold h where h.quote_id = q.id and h.released_at is null))
                      -- a supplier the customer paid to reveal on this request is not one of "the others"
                      and not exists (select 1 from public.transactions t
                                       where t.inquiry_id = p_inquiry and t.supplier_id = q.supplier_id and t.fee_status = 'paid')) x
             join public.leads le on le.id = x.supplier_id
            where not coalesce(le.banned, false) and not public.fn_is_sanctioned_lead(le.id) loop
    v_key := case p_event when 'reveal_open' then v_type || ':' || p_inquiry || ':' || l.id
                          else v_type || ':' || p_inquiry || ':' || l.id || ':r' || v_round end;
    -- ONE MESSAGE PER SUPPLIER PER EVENT: a second paid reveal on the request tells nobody again
    if exists (select 1 from public.notifications n where n.dedupe_key = v_key)
       or exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                   and a.target_id = 'delivery.request:' || v_key) then
      continue;
    end if;
    -- the hire already told this supplier (job_awarded_other): the end of the period is not a second message
    if p_event = 'ended' and exists (select 1 from public.notifications n where n.inquiry_id = p_inquiry and n.lead_id = l.id and n.type = 'job_awarded_other') then
      continue;
    end if;
    -- "open again" only to a supplier who was told it had ended
    if p_event = 'reopened' and not exists (select 1 from public.notifications n where n.inquiry_id = p_inquiry and n.lead_id = l.id and n.type = 'request_ended') then
      continue;
    end if;
    -- "remains available" is said only to a supplier whose quotation IS still live, and with no date: the date moves
    -- (a withdrawal, a moved expiry, a second reveal) and a supplier is never told again (coordinator's ruling, 13 Nov 2026)
    if p_event in ('reveal_open', 'reopened') and not exists (
         select 1 from public.quotes q where q.inquiry_id = p_inquiry and q.supplier_id = l.id
            and coalesce(q.status, '') not in ('withdrawn', 'expired', 'revealed', 'rejected', 'cancelled')
            and (coalesce(q.status, '') <> 'draft'
                 or exists (select 1 from public.quote_quality_hold h where h.quote_id = q.id and h.released_at is null))
            and (q.expires_at is null or q.expires_at > now())) then
      continue;
    end if;
    if p_event = 'reveal_open' then
      v_subject := 'Update on request ' || v_no || ' — QuotesDone';
      v_body := 'The customer has opened one quotation on request ' || v_no
        || '. Your quotation remains available to the customer while it is valid. Nothing is needed from you now.';
    elsif p_event = 'ended' then
      v_subject := 'Request ' || v_no || ' has ended — QuotesDone';
      v_body := 'Request ' || v_no || ' has ended.'
        || case when i.hired_supplier_id is not null and i.hired_supplier_id <> l.id then ' The customer went ahead with another supplier.' else '' end
        || ' Nothing is needed from you. Thank you for your quotation.';
    else
      v_subject := 'Request ' || v_no || ' is open again — QuotesDone';
      v_body := 'Request ' || v_no || ' is open again. Your quotation is available to the customer while it is valid. Nothing is needed from you now.';
    end if;
    v_why := public.fn_seat_clock_refusal(v_fx, l.to_email, v_type);
    if v_why is not null then
      v_out := v_out || jsonb_build_array(jsonb_build_object('lead_id', l.id, 'event', p_event, 'status', 'not_told', 'why', v_why));
      continue;
    end if;
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', v_type, 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', l.to_email, 'to_role', 'supplier',
      'lead_id', l.id, 'inquiry_id', p_inquiry, 'lang', 'en', 'subject', v_subject, 'body', v_body, 'dedupe_key', v_key)));
    v_out := v_out || jsonb_build_array(jsonb_build_object('lead_id', l.id, 'event', p_event,
      'status', coalesce(v_d->0->>'status', 'unknown'), 'handoff_id', v_d->0->'handoff_id', 'notification_id', v_d->0->'notification_id'));
  end loop;
  return v_out;
end $fn$;
revoke execute on function public.fn_sales_engineer_tells_unchosen_suppliers(uuid, text, timestamptz) from public, anon, authenticated;

-- BACKFILL: none in this file, by design. The 3 quotes on production (15 Nov 2026) all state "30 days" and already carry
-- created_at + 30 days; read again they would end at the close of the same day in Dubai instead (a few hours later), all three
-- in October 2026, already past. Rows this file's reading would move are counted, never written, by:
--   select count(*) from public.quotes
--    where expires_at is distinct from public.fn_quote_validity_until(validity, quotation_date, created_at);
-- If the founder wants them re-read, that is its own statement, run on its own after this file:
--   update public.quotes set expires_at = public.fn_quote_validity_until(validity, quotation_date, created_at)
--    where expires_at is distinct from public.fn_quote_validity_until(validity, quotation_date, created_at);
