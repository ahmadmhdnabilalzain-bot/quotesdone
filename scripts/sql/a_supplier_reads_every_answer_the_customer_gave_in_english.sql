-- A SUPPLIER READS EVERY ANSWER THE CUSTOMER GAVE, IN ENGLISH (12 Nov 2026, sales_engineer; final audit of 12 Nov,
-- customer_journey B2 / fix group Q2; founder ledger 1642 "Proceed with fixes"; suppliers are written in English only,
-- ledger 993 and ruling 1008). Follows an_arabic_spec_answer_reaches_suppliers_only_in_english.sql in MANIFEST: this
-- file redefines scrub_inquiry_contacts and is the canonical copy from here on.
--
-- MEASURED (final audit, run d9a04dbc, 11-12 Nov 2026): both inquiry PDFs a supplier downloads said "Required by: Not
-- stated" and "The customer's answers on materials, installation, warranty and the required date were not recorded",
-- while inquiries.spec.customer_requirements held them (15 Dec 2026 and 2 years; 31 Jan 2027, a Japanese brand, a
-- 5-year compressor warranty) and the new_inquiry e-mail carried them. 2 of 2 requests of that day lost the key; the 3
-- September requests kept it (they were recorded before the intake wrote the Arabic display rows).
--
-- CAUSE: scrub_inquiry_contacts built spec_masked by dropping every TOP-LEVEL spec key whose value contained Arabic
-- script anywhere inside it. customer_requirements always carries display.ar, label_ar and choice_ar beside the English,
-- so the whole key went, English and all. The supplier PDF (_shared/quote_documents/inquiry_document.ts) and the
-- portal's "requested" block (supplier_api/quote_review_actions.ts inquiry_detail) read only that key.
--
-- NOW: the Arabic is removed MEMBER BY MEMBER, at every depth, by fn_jsonb_without_arabic: a member named `ar` or ending
-- in `_ar` goes, any string carrying Arabic script goes (an object member or an array element), everything else stays.
-- So customer_requirements reaches the supplier copy with display.en, label_en, choice_en, required_by, warranty and
-- installation, and no Arabic at all. A top-level value that is Arabic text still goes, exactly as before. Every identity
-- protection is unchanged: the same mask_contacts_jsonb and mask_project_identity_jsonb run first, on the whole spec.
--
-- DATA REPAIR (guarded, at the end): a row whose spec has customer_requirements and whose spec_masked lacks it is
-- re-saved (`spec = spec`), so this trigger rewrites its supplier copy. Measured before writing, 12 Nov 2026: 3 rows in
-- public.inquiries, all ZZ DEMO, all three keep the key; the statement touches 0 rows today and exists for any row
-- written between this measurement and the apply. A re-save changes no content column: trg_version_rfq writes no
-- version when nothing it tracks changed, and trg_rfq_complete recomputes the same completeness.
--
-- New routine fn_jsonb_without_arabic(jsonb): pinned search_path, EXECUTE revoked from public, anon and authenticated
-- (CREATE grants PUBLIC). scrub_inquiry_contacts is CREATE OR REPLACE: its ACL is preserved. No new table.
-- Probe: a_supplier_reads_every_answer_the_customer_gave_in_english_probe.sql (pure, rolls back).
-- prevented by: scripts/checks/a_supplier_reads_every_answer_the_customer_gave_in_english.test.mjs

create or replace function public.fn_jsonb_without_arabic(j jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
declare ar constant text := '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]';
begin
  -- SQL null means "drop this member"; a JSON null is kept as it is.
  if j is null then return null; end if;
  case jsonb_typeof(j)
    when 'string' then return case when (j #>> '{}') ~ ar then null else j end;
    when 'array' then
      return (select coalesce(jsonb_agg(s.x order by s.o), '[]'::jsonb)
                from (select public.fn_jsonb_without_arabic(e) as x, o from jsonb_array_elements(j) with ordinality t(e, o)) s
               where s.x is not null);
    when 'object' then
      return (select coalesce(jsonb_object_agg(s.k, s.x), '{}'::jsonb)
                from (select t.k, public.fn_jsonb_without_arabic(t.v) as x from jsonb_each(j) t(k, v)
                       where lower(t.k) <> 'ar' and lower(t.k) !~ '_ar$' and t.k !~ ar) s
               where s.x is not null);
    else return j;
  end case;
end $function$;

revoke execute on function public.fn_jsonb_without_arabic(jsonb) from public, anon, authenticated;

create or replace function public.scrub_inquiry_contacts()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare changed boolean := false; v_name text; v_spec jsonb;
begin
  new.summary_masked      := public.mask_project_identity(public.mask_contacts(new.summary));
  new.raw_input_masked    := public.mask_project_identity(public.mask_contacts(new.raw_input));
  new.budget_masked       := public.mask_project_identity(public.mask_contacts(new.budget));
  v_spec                  := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.spec));
  -- Suppliers read English only (ledger 993, ruling 1008): no Arabic reaches the supplier copy, member by member, so the
  -- English beside it stays (customer_requirements.display.en, label_en, choice_en). An answer written only in Arabic
  -- reaches them in English on the held note (fn_inquiry_add_missing_specs, surface sales_engineer.supplier_english).
  new.spec_masked         := case when jsonb_typeof(v_spec) = 'object'
                               then coalesce(public.fn_jsonb_without_arabic(v_spec), '{}'::jsonb)
                               else v_spec end;
  new.boq_masked          := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.boq));
  new.completeness_masked := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.completeness));

  if new.customer_id is not null then
    begin
      select nullif(btrim(c.full_name), '') into v_name from public.customers c where c.id = new.customer_id;
    exception when others then v_name := null; end;
    if v_name is not null then
      new.summary_masked   := public.mask_name(new.summary_masked, v_name);
      new.raw_input_masked := public.mask_name(new.raw_input_masked, v_name);
      new.budget_masked    := public.mask_name(new.budget_masked, v_name);
    end if;
  end if;

  -- The alert is about contacts and project identity; dropping an Arabic value is not a masking event.
  changed := (new.summary_masked is distinct from new.summary)
          or (new.raw_input_masked is distinct from new.raw_input)
          or (new.budget_masked is distinct from new.budget)
          or (v_spec is distinct from new.spec)
          or (new.boq_masked is distinct from new.boq)
          or (new.completeness_masked is distinct from new.completeness);
  if changed then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn', 'inquiry_contact_masked',
        'Masked customer contact details and/or project identity (consultant, client, building, '
        || 'location, plot, drawing numbers) in the supplier-facing copy of inquiry '
        || coalesce(new.id::text, '?') || ' from customer ' || coalesce(new.customer_id::text, '?') || '.',
        'system');
    exception when others then null; end;
  end if;
  return new;
end $function$;

-- DATA REPAIR: re-save each request whose supplier copy lost the customer's answers (0 rows measured 12 Nov 2026).
update public.inquiries
   set spec = spec
 where jsonb_typeof(spec) = 'object' and spec ? 'customer_requirements'
   and not coalesce(spec_masked ? 'customer_requirements', false);

select case
  when exists (select 1 from public.inquiries
                where jsonb_typeof(spec) = 'object' and spec ? 'customer_requirements'
                  and not coalesce(spec_masked ? 'customer_requirements', false))
    then 'PROBE FAILED: a request still has the customer''s answers missing from its supplier copy'
  when exists (select 1 from public.inquiries where spec_masked::text ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]')
    then 'PROBE FAILED: a supplier copy of a request carries Arabic'
  when has_function_privilege('anon', 'public.fn_jsonb_without_arabic(jsonb)', 'execute')
    then 'PROBE FAILED: anon can execute fn_jsonb_without_arabic'
  else 'PROBE OK' end as verdict;
