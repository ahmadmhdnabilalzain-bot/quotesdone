-- a_quote_is_held_until_every_detail_is_stated_exactly.sql
-- Assigned: sales_engineer — the supplier-portal hold desk (founder, 14 Sep 2026: "its always the
-- sales agent. no other agent is involved in customer or supplier portal").
--
-- THE RULES (founder, 14 Sep 2026, verbatim in public.founder_instruction):
--   "in fitout quotation for example, we need to make sure that exact specs of the material used,
--    what type of wood, what thickness, etc. this is a rule, and if a supplier submits missing
--    information, then the sales agent will notify him that the quotation will be on hold until he
--    mentions the exact details" — and the details are: material specs per line and per trade, a
--    concrete delivery date or lead time, installation if applicable, warranty if applicable.
--   "if a supplier wanted to share 2 options on his quote, they will be considered two different
--    quotations, they cant be merged in one. so each will have its own ID in the system."
--
-- MEASURED BEFORE (production, 14 Sep 2026):
--   * quote_items had brand / model / specification as free text and nothing per attribute;
--     category_quote_specs matched 141 English regexes against the whole quote as one blob.
--   * quotes was UNIQUE (inquiry_id, supplier_id): one supplier, one quote per request, so a second
--     option could only ever overwrite the first.
--   * 0 quotes, 0 claimed and 0 approved suppliers, and no routine inserts into quotes or relies on
--     the (inquiry_id, supplier_id) pair — so the uniqueness can move to (inquiry_id, supplier_id,
--     option_no) with nothing live depending on the old pair. supplier_api is the only writer; its
--     new code (same PR) no longer upserts on the pair.
--   * fn.supplier_api's internal credential was not scoped to pdf_native, so the regenerated
--     quotation could not be drawn.
--
-- WHAT THIS CHANGES:
--   1. quote_items.spec / spec_source — each line's specification by attribute code, and whether each
--      value was read from the supplier's own text ('extracted') or entered on the portal
--      ('supplier_portal'). The attribute catalogue is supabase/functions/_shared/line_specs/model.ts.
--   2. quotes.option_no / submission_id — each option its own quote row and id, linked to the
--      submission it came in on; quotes.terms_spec — delivery / installation / warranty as the
--      supplier confirmed them on the portal.
--   3. public.quote_spec_hold — one row per hold episode: the audit trail of original submission,
--      supplier-entered values, regenerated version, approval (who, when). Service role only.
--   4. fn.supplier_api may call pdf_native (the regenerated quotation's PDF).
--
-- WHAT IT DOES NOT CHANGE: no routine is created or replaced; a held quote stays status 'draft',
-- which every customer-facing read already excludes (customer_api, quote_compare filter
-- status <> 'draft'), so no customer surface needed a new filter.

alter table public.quote_items
  add column if not exists spec jsonb not null default '{}'::jsonb,
  add column if not exists spec_source jsonb not null default '{}'::jsonb;
comment on column public.quote_items.spec is 'Line specification by attribute code (line_specs/model.ts), e.g. {"material":"MDF","thickness_mm":"18","finish":"HPL"}. Owner: sales_engineer.';
comment on column public.quote_items.spec_source is 'Per attribute: extracted (read from the supplier''s own text) or supplier_portal (entered by the supplier on the portal).';

alter table public.quotes
  add column if not exists option_no integer not null default 1,
  add column if not exists submission_id uuid,
  add column if not exists terms_spec jsonb,
  add column if not exists price_ex_vat numeric,
  add column if not exists vat_treatment text,
  add column if not exists vat_amount numeric,
  add column if not exists supplier_trn text,
  add column if not exists amount_as_stated numeric;
alter table public.quotes drop constraint if exists quotes_option_no_range;
alter table public.quotes add constraint quotes_option_no_range check (option_no between 1 and 20);
alter table public.quotes drop constraint if exists quotes_price_ex_vat_positive;
alter table public.quotes add constraint quotes_price_ex_vat_positive check (price_ex_vat is null or price_ex_vat > 0);
alter table public.quotes drop constraint if exists quotes_vat_treatment_known;
alter table public.quotes add constraint quotes_vat_treatment_known check (vat_treatment is null or vat_treatment in ('exclusive', 'inclusive', 'not_registered', 'not_stated', 'confirmed_on_portal'));
alter table public.quotes drop constraint if exists quotes_supplier_trn_shape;
alter table public.quotes add constraint quotes_supplier_trn_shape check (supplier_trn is null or supplier_trn ~ '^100[0-9]{12}$');
comment on column public.quotes.price_ex_vat is 'The price EXCLUDING VAT: what the customer compares and the 3% reveal fee is taken on (founder, 14 Sep 2026). quote_amount is set to it once known. Null = not determinable, and the quote is held.';
comment on column public.quotes.vat_treatment is 'INTERNAL RECORD ONLY, never served to a customer: how the supplier stated VAT (line_specs/vat.ts).';
comment on column public.quotes.vat_amount is 'INTERNAL RECORD ONLY, never served to a customer: the VAT amount the supplier stated.';
comment on column public.quotes.supplier_trn is 'INTERNAL RECORD ONLY, never served to a customer: the supplier''s TRN identifies them on a public register (founder, 14 Sep 2026).';
comment on column public.quotes.amount_as_stated is 'INTERNAL RECORD ONLY: the total exactly as the supplier stated it, before the ex-VAT price was determined.';
comment on column public.quotes.option_no is 'Founder 14 Sep 2026: each option a supplier offers is its own quotation. 1 for a single-option quote.';
comment on column public.quotes.submission_id is 'The submission this quote (option) arrived on; options of one submission share it, for audit.';
comment on column public.quotes.terms_spec is 'Delivery / installation / warranty as confirmed by the supplier on the portal (line_specs/assess.ts TermsSpec).';

do $$
begin
  if exists (select 1 from pg_constraint where conrelid = 'public.quotes'::regclass and conname = 'quotes_inquiry_id_supplier_id_key') then
    alter table public.quotes drop constraint quotes_inquiry_id_supplier_id_key;
  end if;
end $$;
drop index if exists public.quotes_inquiry_id_supplier_id_key;
create unique index if not exists quotes_inquiry_supplier_option_key on public.quotes (inquiry_id, supplier_id, option_no);

create table if not exists public.quote_spec_hold (
  id bigint generated always as identity primary key,
  quote_id uuid not null references public.quotes(id) on delete cascade,
  inquiry_id uuid,
  supplier_id bigint,
  submission_id uuid,
  option_no integer not null default 1,
  state text not null check (state in ('open', 'awaiting_approval', 'released', 'superseded')),
  missing jsonb not null default '[]'::jsonb,
  note_en text,
  note_ar text,
  original_snapshot jsonb not null,
  supplier_values jsonb not null default '[]'::jsonb,
  regenerated jsonb,
  regenerated_at timestamptz,
  pdf_bucket text,
  pdf_path text,
  approved_at timestamptz,
  approved_by text,
  released_at timestamptz,
  superseded_at timestamptz,
  notified_at timestamptz,
  notification_ids jsonb,
  owner_seat text not null default 'sales_engineer' check (owner_seat = 'sales_engineer'),
  opened_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.quote_spec_hold is 'A quote held until every required detail is stated exactly (founder, 14 Sep 2026). One row per episode: original submission, supplier-entered values, regenerated standardised quotation, approval. Owned by the sales_engineer seat, service role only.';
create unique index if not exists quote_spec_hold_one_live on public.quote_spec_hold (quote_id) where state in ('open', 'awaiting_approval');
create index if not exists quote_spec_hold_by_inquiry on public.quote_spec_hold (inquiry_id, state);

alter table public.quote_spec_hold enable row level security;
drop policy if exists quote_spec_hold_service_role_only on public.quote_spec_hold;
create policy quote_spec_hold_service_role_only on public.quote_spec_hold as permissive for all to public using (false) with check (false);
revoke all on public.quote_spec_hold from anon, authenticated;

update public.internal_credential
   set scope = array_append(scope, 'pdf_native')
 where context = 'fn.supplier_api' and not (scope @> array['pdf_native']);

-- PROBE. This file defines things, so it ends in a notice; it raises only on a genuine failure,
-- where rolling the whole file back is the right outcome. It writes no row of its own.
do $$
declare n int;
begin
  select count(*) into n from information_schema.columns
   where table_schema = 'public'
     and ((table_name = 'quote_items' and column_name in ('spec', 'spec_source'))
       or (table_name = 'quotes' and column_name in ('option_no', 'submission_id', 'terms_spec', 'price_ex_vat', 'vat_treatment', 'vat_amount', 'supplier_trn', 'amount_as_stated')));
  if n <> 10 then raise exception 'CHK<<expected 10 new columns, found %>>', n; end if;
  if exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'quotes' and indexname = 'quotes_inquiry_id_supplier_id_key') then
    raise exception 'CHK<<the (inquiry_id, supplier_id) uniqueness is still there; a second option could not be stored>>';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'quotes_inquiry_supplier_option_key') then
    raise exception 'CHK<<no uniqueness on (inquiry_id, supplier_id, option_no)>>';
  end if;
  if (select relrowsecurity from pg_class where oid = 'public.quote_spec_hold'::regclass) is not true
     or not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'quote_spec_hold') then
    raise exception 'CHK<<quote_spec_hold without RLS and its policy>>';
  end if;
  if not exists (select 1 from public.internal_credential where context = 'fn.supplier_api' and scope @> array['pdf_native']) then
    raise exception 'CHK<<fn.supplier_api is not scoped to pdf_native>>';
  end if;
  raise notice 'CHK<<quote lines carry specs; options are separate quotes; quote_spec_hold ready; supplier_api may draw the regenerated PDF>>';
end $$;
