-- A MASKED CONTACT IS LOGGED AS A COMPANY EVENT, NOT A FOUNDER ALERT. Seat: sales_engineer (built by it_engineer, agent L3_IT,
-- 16 Nov 2026, founder ledger 1557 and rulings 1696/1710: nothing reaches the founder that is not his).
-- MEASURED (SELECT, 7 days to 16 Nov 2026): 171 of the 197 founder_alerts rows were 'inquiry_contact_masked', channel
-- 'system' - never sent, level warn, one row on EVERY insert or update of an inquiry whose supplier copy differs from the
-- original. founder_alerts is the record of what the founder was told (fn_it_daily_line, fn_company_snapshot and the
-- founder's bell read it), so the masking log made his count read 197 when 20 messages reached him.
-- NOW: the masking is logged where operational events go, public.company_event (event_type 'inquiry.contact_masked',
-- entity inquiry, actor sales_engineer, the ids only - never the masked text), once per inquiry (dedupe_key, the house pattern
-- of fn_sales_engineer_request_step_failed). The masking itself is production's body, unchanged (md5 before the edit
-- f75a6206d746e63bb5f69db2da4e4437); only the insert at the end moved.

CREATE OR REPLACE FUNCTION public.scrub_inquiry_contacts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      new.spec_masked      := public.fn_jsonb_mask_name(new.spec_masked, v_name);
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
    -- 16 Nov 2026 (ledger 1557): an operational event, once per inquiry, never a row in the founder's alert ledger
    begin
      insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
      select 'inquiry.contact_masked', 'inquiry', new.id::text, 'sales_engineer',
             jsonb_build_object('inquiry_id', new.id, 'customer_id', new.customer_id,
               'what', 'customer contact details and/or project identity (consultant, client, building, location, plot, drawing numbers) masked in the supplier-facing copy'),
             'inquiry.contact_masked:' || new.id
       where new.id is not null
         and not exists (select 1 from public.company_event e where e.dedupe_key = 'inquiry.contact_masked:' || new.id);
    exception when others then null; end;   -- logging must never stop the inquiry being saved
  end if;
  return new;
end $function$
;
