-- A SUPPLIER'S LETTER IS KEPT FROM THE FIRST TIME THE CUSTOMER SEES IT (15 Nov 2026, sales_engineer).
-- Seat: sales_engineer. Branch sales_engineer-the-customer-is-asked-in-plain-words-and-sees-one-letter-per-supplier, review
-- REVIEW_plain item 1.
--
-- WHY A STORED LETTER. Until this file the customer's letter for a supplier ("Supplier B") was WORKED OUT each time a surface
-- ran, first from the price order, then from the order the quotes arrived. Whatever the rule, a letter worked out again later
-- can come out different. The review reproduced three ways an arrival-order letter moved:
--   (a) X is held at 08:00 and Y goes live at 09:00, so Y is A; X's revised upload then supersedes its hold, X sorts by its old
--       created_at, and Y becomes B;
--   (b) X (A) is withdrawn, and Y moves from B to A;
--   (c) a live quote re-held on resubmission goes back to draft and is released later, so the letters swap again.
-- The letter "A" on the customer's earlier quotation PDF then names a different supplier from the one on his screen.
--
-- THE RULE NOW: the first time a supplier's quote (or its first question in the request's thread) is SHOWN to the customer, the
-- surface that shows it records (request, supplier) -> the next letter, and every customer surface reads that row afterwards.
-- The row is never updated or deleted (service_role may only read and insert it), so a withdrawal, a re-hold, a revised upload
-- or a release cannot move a letter. A supplier never shown gets no row, so the letters run A, B, C with no gap: a quote from a
-- sanctioned supplier (instruction 516) and a held quote are never given one.
--
-- WHAT THIS ADDS:
--   1. public.customer_supplier_letter: one row per (inquiry, supplier) with its letter, its 0-based place (seq), when it was
--      first shown and by which surface. UNIQUE on (inquiry_id, seq) and (inquiry_id, letter). RLS on with the service-role-only
--      policy; revoked from anon and authenticated; service_role keeps SELECT and INSERT only.
--   2. public.fn_customer_supplier_letters(uuid[], jsonb, text): records the suppliers being shown now, in the order given, then
--      returns every letter of those requests. One call serves the portal's many requests. Per request it takes a transaction
--      advisory lock (in sorted order, so two calls never deadlock), so two surfaces showing two new suppliers at once can never
--      give out one letter twice. It REFUSES to letter a supplier with no live quote and no question on the request, and a
--      sanctioned one, whatever the caller passes. The caller decides "shown" for the rest (a quote held for missing details is
--      left out by the caller: _shared/reveal_guard.ts heldQuoteIds is code, not SQL).
--   3. The export registry row for the new table.
--
-- APPLY WITH: node scripts/apply_sql.mjs scripts/sql/a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it.sql --apply --ddl
-- LOCKS: the foreign key takes SHARE ROW EXCLUSIVE on inquiries; the file starts with lock_timeout 3 s so it fails fast behind a
--   long reader instead of queueing the portal, and is simply applied again.
-- ORDER: apply BEFORE deploying customer_api, quote_compare, messages_api, stripe_checkout and sales_engineer from this branch.
--   Deployed first, they find no function: the cards and the chat say "Supplier" with no letter, and the comparison, the quotation
--   PDF and the reveal checkout refuse with a retry until the file is applied (none guesses a letter).
-- EXISTING REQUESTS: no backfill. Each request's suppliers are lettered the first time the customer opens it after the deploy, in
--   the order their quotes arrived; from then on the letters are kept.
-- prevented by: supabase/functions/_shared/quote_labels.test.ts (the three moving cases and the gap, against this function's rule),
--               scripts/sql/a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it_probe.sql (rolled back, ZZ only).

set local lock_timeout = '3s';

create table if not exists public.customer_supplier_letter (
  inquiry_id     uuid not null references public.inquiries(id) on delete cascade,
  supplier_id    bigint not null,
  seq            integer not null check (seq >= 0),
  letter         text not null check (letter ~ '^[A-Z]{1,3}$'),
  first_shown_at timestamptz not null default now(),
  shown_by       text not null check (shown_by in ('quote_card', 'comparison', 'question')),
  constraint customer_supplier_letter_pkey primary key (inquiry_id, supplier_id),
  constraint customer_supplier_letter_one_place unique (inquiry_id, seq),
  constraint customer_supplier_letter_one_letter unique (inquiry_id, letter)
);
comment on table public.customer_supplier_letter is
  'sales_engineer: the letter a customer knows each supplier by on one request ("Supplier B"), recorded the first time that supplier''s quote or question was shown to him and never changed (fn_customer_supplier_letters).';
alter table public.customer_supplier_letter enable row level security;
drop policy if exists customer_supplier_letter_service_role_only on public.customer_supplier_letter;
create policy customer_supplier_letter_service_role_only on public.customer_supplier_letter
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_supplier_letter from anon, authenticated;
-- a letter once given is never changed: the edge functions may read and add, never update or delete
revoke update, delete, truncate on public.customer_supplier_letter from service_role;
grant select, insert on public.customer_supplier_letter to service_role;

create or replace function public.fn_customer_supplier_letters(p_inquiry_ids uuid[], p_shown jsonb, p_shown_by text)
returns table(inquiry_id uuid, supplier_id bigint, letter text, seq integer)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
#variable_conflict use_column
declare
  v_inq uuid;
  v_sid bigint;
  v_next integer;
  v_n integer;
  v_letter text;
begin
  if p_shown_by is null or p_shown_by not in ('quote_card', 'comparison', 'question') then
    raise exception 'fn_customer_supplier_letters: unknown surface %', coalesce(p_shown_by, 'null') using errcode = '22023';
  end if;
  if p_shown is not null and jsonb_typeof(p_shown) = 'array' and jsonb_array_length(p_shown) > 0 then
    -- one lock per request, taken in a fixed order, before any letter of it is read
    for v_inq in
      select distinct (e->>'inquiry_id')::uuid as i from jsonb_array_elements(p_shown) e
       where e->>'inquiry_id' is not null and (e->>'inquiry_id')::uuid = any (p_inquiry_ids) order by 1
    loop
      perform pg_advisory_xact_lock(hashtextextended('customer_supplier_letter:' || v_inq::text, 0));
    end loop;
    for v_inq, v_sid in
      select (e->>'inquiry_id')::uuid, (e->>'supplier_id')::bigint
        from jsonb_array_elements(p_shown) with ordinality as x(e, o)
       where e->>'inquiry_id' is not null and e->>'supplier_id' ~ '^[0-9]+$' and (e->>'inquiry_id')::uuid = any (p_inquiry_ids)
       order by o
    loop
      continue when exists (select 1 from public.customer_supplier_letter l where l.inquiry_id = v_inq and l.supplier_id = v_sid);
      -- never shown to a customer, whatever the caller says (instruction 516)
      continue when exists (select 1 from public.sanctions_ban b where b.lead_id = v_sid);
      -- only a supplier the customer can actually see on this request: a live quote, or a question in its thread
      continue when not exists (select 1 from public.quotes q where q.inquiry_id = v_inq and q.supplier_id = v_sid
                                   and coalesce(q.status, '') not in ('draft', 'withdrawn'))
                and not exists (select 1 from public.rfq_clarification c where c.inquiry_id = v_inq and c.supplier_id = v_sid
                                   and c.kind = 'question');
      select coalesce(max(l.seq) + 1, 0) into v_next from public.customer_supplier_letter l where l.inquiry_id = v_inq;
      -- A, B ... Z, AA, AB ... (the same as _shared/quote_labels.ts letter())
      v_n := v_next; v_letter := '';
      loop
        v_letter := chr(65 + (v_n % 26)) || v_letter;
        v_n := v_n / 26 - 1;
        exit when v_n < 0;
      end loop;
      insert into public.customer_supplier_letter (inquiry_id, supplier_id, seq, letter, shown_by)
      values (v_inq, v_sid, v_next, v_letter, p_shown_by);
    end loop;
  end if;
  return query
    select l.inquiry_id, l.supplier_id, l.letter, l.seq from public.customer_supplier_letter l
     where l.inquiry_id = any (coalesce(p_inquiry_ids, '{}'::uuid[])) order by l.inquiry_id, l.seq;
end
$fn$;
revoke execute on function public.fn_customer_supplier_letters(uuid[], jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_customer_supplier_letters(uuid[], jsonb, text) to service_role;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('customer_supplier_letter', true, 'customer_support', 'The letter each customer knows each supplier by on a request, kept from the first time it was shown (what his PDFs, cards and invoice say).', 'sales_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- Verdict row (DDL file, so no raise): the table closed to the public roles with its policy, letters fixed once given, the
-- routine closed to the public roles with its search_path pinned, and the registry row.
select case
  when not (select relrowsecurity from pg_class where oid = 'public.customer_supplier_letter'::regclass)
    then 'PROBE FAILED: customer_supplier_letter has no row level security'
  when not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'customer_supplier_letter')
    then 'PROBE FAILED: customer_supplier_letter has no policy'
  when has_table_privilege('anon', 'public.customer_supplier_letter', 'select')
    or has_table_privilege('authenticated', 'public.customer_supplier_letter', 'select')
    then 'PROBE FAILED: a public role can read customer_supplier_letter'
  when has_table_privilege('service_role', 'public.customer_supplier_letter', 'update')
    or has_table_privilege('service_role', 'public.customer_supplier_letter', 'delete')
    then 'PROBE FAILED: service_role can change a letter once given'
  when has_function_privilege('anon', 'public.fn_customer_supplier_letters(uuid[], jsonb, text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_customer_supplier_letters(uuid[], jsonb, text)', 'execute')
    then 'PROBE FAILED: a public role can execute fn_customer_supplier_letters'
  when not exists (select 1 from pg_proc where oid = 'public.fn_customer_supplier_letters(uuid[], jsonb, text)'::regprocedure
                     and array_to_string(proconfig, ',') like '%search_path=public, pg_temp%')
    then 'PROBE FAILED: fn_customer_supplier_letters has no pinned search_path'
  when not exists (select 1 from public.table_export_registry where table_name = 'customer_supplier_letter' and exported)
    then 'PROBE FAILED: customer_supplier_letter is not in the export registry'
  else 'PROBE OK' end as verdict;
