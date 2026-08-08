-- ANONYMITY MODEL (QuotesDone is an anonymous marketplace) -----------------------------------
-- A supplier must learn NOTHING identifying about a customer until the reveal fee is paid.
-- `quotes` already has a database-level backstop: BEFORE trigger trg_scrub_quote_contacts runs
-- scrub_quote_contacts(), which overwrites notes/scope/conditions/... IN PLACE with
-- public.mask_contacts(). That is safe for quotes because the raw contact string is the
-- supplier's own off-platform bypass attempt - nobody is entitled to see it, ever.
--
-- WHY INQUIRIES ARE NOT MIRRORED IN PLACE: an inquiry's free text is the CUSTOMER's own words.
-- Overwriting summary/spec/budget in place would (a) permanently destroy the customer's own view
-- of their own brief, and (b) destroy the very contact details the 3% reveal fee sells - after a
-- paid reveal supplier_api serves inquiries.summary/spec byte-identically from these same
-- columns, so an in-place mask makes the reveal flow return '[hidden]' forever. Masking here is
-- therefore NON-DESTRUCTIVE: the raw columns are untouched (customer view + reveal flow keep
-- working), and a masked shadow copy is maintained by the same trigger discipline and the SAME
-- public.mask_contacts() regexes, so a supplier-facing reader that forgets to scrub reads a
-- column that is already safe. Durability comes from the trigger, not from reader discipline.

alter table public.inquiries
  add column if not exists summary_masked      text,
  add column if not exists raw_input_masked    text,
  add column if not exists budget_masked       text,
  add column if not exists spec_masked         jsonb,
  add column if not exists boq_masked          jsonb,
  add column if not exists completeness_masked jsonb;

comment on column public.inquiries.summary_masked is
  'Supplier-safe copy of summary, maintained by trg_mask_inquiry_contact. Never write directly.';

-- Deep-mask for JSONB free text (spec / boq / completeness). Applies the EXISTING
-- public.mask_contacts() to every string leaf, so emails, URLs, messenger short links and UAE
-- phone numbers are removed by exactly the regexes already trusted on the quotes side. Numbers,
-- booleans and object KEYS are returned untouched, so BOQ quantities, prices and field names
-- are unaffected.
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

-- Mirrors scrub_quote_contacts(): same BEFORE-trigger placement, same mask_contacts() call, same
-- founder_alerts warn row when something was actually masked (so an attempted off-platform
-- bypass is visible), same swallow-all exception guard so alerting can never block a write.
-- The only deliberate difference is destination: shadow columns instead of in place.
create or replace function public.scrub_inquiry_contacts()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare changed boolean := false;
begin
  new.summary_masked      := public.mask_contacts(new.summary);
  new.raw_input_masked    := public.mask_contacts(new.raw_input);
  new.budget_masked       := public.mask_contacts(new.budget);
  new.spec_masked         := public.mask_contacts_jsonb(new.spec);
  new.boq_masked          := public.mask_contacts_jsonb(new.boq);
  new.completeness_masked := public.mask_contacts_jsonb(new.completeness);

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
$function$;

-- Named to sort AFTER the existing BEFORE triggers enrich_inquiry and rfq_complete, so the
-- masked copy is taken from the final enriched values rather than the pre-enrichment ones.
drop trigger if exists trg_mask_inquiry_contact on public.inquiries;
create trigger trg_mask_inquiry_contact
  before insert or update on public.inquiries
  for each row execute function public.scrub_inquiry_contacts();

-- Supplier-facing read surface: the masked copies presented under the ORIGINAL column names, so
-- a reader that selects summary/spec/budget/boq from here cannot emit raw customer text even if
-- it forgets to scrub. security_invoker keeps the caller's RLS - this view adds no bypass.
create or replace view public.inquiries_supplier_safe
with (security_invoker = true) as
select
  i.id, i.category, i.emirate, i.role_needed, i.status, i.created_at,
  i.scope_type, i.trades, i.keywords, i.brief_source, i.urgency,
  i.boq_confidence, i.drawing_redacted_paths, i.outcome, i.hired_supplier_id,
  i.summary_masked      as summary,
  i.raw_input_masked    as raw_input,
  i.budget_masked       as budget,
  i.spec_masked         as spec,
  i.boq_masked          as boq,
  i.completeness_masked as completeness
from public.inquiries i;

comment on view public.inquiries_supplier_safe is
  'Anonymity model: pre-reveal supplier-facing reads of inquiries. Customer free text is served from the masked shadow columns. customer_id is deliberately absent - it would let a supplier correlate a buyer across RFQs.';

-- Backfill every existing row through the same trigger.
update public.inquiries set id = id;