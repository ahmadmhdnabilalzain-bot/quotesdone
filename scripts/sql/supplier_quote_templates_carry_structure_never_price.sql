-- T3 — SUPPLIER QUOTE TEMPLATES: STRUCTURE, NEVER PRICE (sales_engineer, 5 Oct 2026).
-- A supplier saves the parts of a quotation retyped on every job (line headings, terms, warranty,
-- validity, inclusions, exclusions, payment terms) and applies them to a new quote. The founder
-- removed reusable price lists, so a template must never carry a price: the table has no numeric
-- column, and a CHECK refuses any text that states a figure beside a currency or a per-unit rate.
-- The same rule is in supabase/functions/supplier_api/quote_template.ts (statesAPrice); the deno
-- test there fails if either side drops it. Written only by supplier_api (service role).

create or replace function public.fn_text_states_a_price(p text)
returns boolean
language sql
immutable
set search_path = 'public', 'pg_temp'
as $$
  select coalesce(p, '') ~* '(\y(aed|dhs?|dirhams?|usd|eur|gbp|sar)\y\s*[0-9])|([0-9][0-9,.]*\s*(/-|\y(aed|dhs?|dirhams?|usd|eur|gbp|sar)\y))|(درهم\s*[0-9]|[0-9][0-9,.]*\s*درهم)|([0-9][0-9,.]*\s*/\s*(m2|m²|sqm|sq\.?\s*m|lm|m|no|nos|unit|pc|pcs|kg|ton)\y)';
$$;
revoke execute on function public.fn_text_states_a_price(text) from public, anon, authenticated;

create table if not exists public.supplier_quote_template (
  id            bigint generated always as identity primary key,
  supplier_id   bigint not null references public.leads(id) on delete cascade,
  name          text not null check (char_length(name) between 2 and 80),
  line_headings text[] not null default '{}' check (cardinality(line_headings) <= 100),
  terms         text not null default '',
  warranty      text not null default '',
  validity      text not null default '',
  inclusions    text not null default '',
  exclusions    text not null default '',
  payment_terms text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (supplier_id, name),
  constraint supplier_quote_template_never_a_price check (not public.fn_text_states_a_price(
    concat_ws(' | ', name, array_to_string(line_headings, ' | '), terms, warranty, validity, inclusions, exclusions, payment_terms)))
);
alter table public.supplier_quote_template enable row level security;
drop policy if exists supplier_quote_template_service_role_only on public.supplier_quote_template;
create policy supplier_quote_template_service_role_only on public.supplier_quote_template
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_quote_template from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('supplier_quote_template', true, 'company', 'suppliers'' saved quote templates: structure only, never a price (T3)', 'sales_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;
