-- PROBE for a_masked_contact_is_logged_as_a_company_event_not_a_founder_alert.sql (sales_engineer; built by it_engineer L3_IT,
-- 16 Nov 2026, ledger 1557). Pure probe: always raises CHK<<...>>, so its one ZZ DEMO inquiry (reserved fixture number
-- +971 50 000 0001 and an @example.invalid address) and every row it causes are rolled back. LOCAL Postgres 16 only.
-- Before the file: "the masking wrote a founder_alerts row". After it: CHK<<PROBE OK ...>>.
do $p$
declare v_fail text := ''; v_id uuid; v_fa int; v_ev int; v_masked text;
begin
  select count(*) into v_fa from public.founder_alerts where event = 'inquiry_contact_masked';
  insert into public.inquiries (summary) values ('ZZ DEMO probe: call me on +971 50 000 0001 or zz-probe@example.invalid')
  returning id, summary_masked into v_id, v_masked;
  -- the masking itself is unchanged
  if v_masked ~ '000 0001|example\.invalid' then v_fail := v_fail || 'the supplier copy still carries the contact; '; end if;
  update public.inquiries set summary = summary || ' (edited: +971 50 000 0002)' where id = v_id;
  if (select count(*) from public.founder_alerts where event = 'inquiry_contact_masked') <> v_fa then
    v_fail := v_fail || 'the masking wrote a founder_alerts row; '; end if;
  select count(*) into v_ev from public.company_event where event_type = 'inquiry.contact_masked' and entity_id = v_id::text;
  if v_ev <> 1 then v_fail := v_fail || v_ev || ' company_event rows for one inquiry (want 1, after an insert and an update); '; end if;
  if exists (select 1 from public.company_event where event_type = 'inquiry.contact_masked' and entity_id = v_id::text
              and payload::text ~ '000 000|example\.invalid') then v_fail := v_fail || 'the event carries the contact itself; '; end if;
  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: masked, 1 company_event, 0 founder_alerts rows>>';
end $p$;
