-- ROW #5 §16 §24 — THE SUPPLIER'S CERTIFICATES, EACH WITH ITS STATUS AND WHAT IT COSTS THEM.
--
-- The portal had a documents tab that listed files. §16 asks for something else: every certificate
-- carrying a VALIDITY STATUS and an IMPACT, so a supplier can see at a glance which missing piece
-- of paper is actually costing them work and which is merely untidy.
--
-- ── document_status IS A FIELD, NOT AN ADJECTIVE ────────────────────────────────────────────────
-- valid / expiring / expired / missing, computed from the expiry the supplier uploaded. "expiring"
-- is within 60 days, which is roughly the lead time on a UAE renewal — a warning that arrives on
-- the expiry date is not a warning.
--
-- ── AND `impact` IS A STATED POLICY, NOT A MEASUREMENT ──────────────────────────────────────────
-- It says what each document GATES, and it is a rule this platform applies rather than a number
-- derived from data. That distinction is in the payload (`impact_basis`), because an invented
-- score dressed as an observation is the failure mode this row keeps guarding against. A trade
-- licence is critical because approval literally cannot happen without it — that is a fact about
-- save_profile's licence gate, not an opinion.
create or replace function public.fn_supplier_certifications(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  docs as (
    select * from (values
      ('trade_licence',      'Trade licence',              'critical', 'Approval is impossible without it — the licence gate refuses every profile that has none.'),
      ('insurance',          'Insurance',                  'high',     'Many customers will not award work to an uninsured supplier.'),
      ('vat',                'VAT certificate',            'high',     'Needed before you can invoice with VAT.'),
      ('iso',               'ISO certification',           'medium',   'Strengthens your capability score and unlocks quality-gated requests.'),
      ('manufacturer_auth', 'Manufacturer authorisation',  'medium',   'Proves you are authorised for the brands you carry.'),
      ('establishment',     'Establishment card',          'low',      'Administrative record. Does not gate work.'),
      ('bank_iban',         'Bank details (IBAN)',         'medium',   'We cannot pay you without it.')
    ) d(key, label, impact, impact_why)
  ),
  held as (
    select d.key, d.label, d.impact, d.impact_why,
      case d.key
        when 'trade_licence'      then (select license_doc_path from me)
        when 'insurance'          then (select insurance_doc_path from me)
        when 'vat'                then (select vat_doc_path from me)
        when 'iso'                then (select iso_doc_path from me)
        when 'manufacturer_auth'  then (select manufacturer_auth_doc_path from me)
        when 'establishment'      then (select egr_doc_path from me)
        when 'bank_iban'          then (select iban_doc_path from me)
      end as path,
      case d.key
        when 'trade_licence'     then (select license_expiry from me)
        when 'insurance'         then (select insurance_expiry from me)
        when 'iso'               then (select iso_expiry from me)
        when 'manufacturer_auth' then (select manufacturer_auth_expiry from me)
        else null
      end::date as expiry
    from docs d
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'certifications', coalesce((select jsonb_agg(jsonb_build_object(
        'key', h.key, 'label', h.label,
        'held', h.path is not null,
        'expiry', h.expiry,
        'days_left', case when h.expiry is null then null else (h.expiry - current_date) end,
        -- THE FIELD §16 ASKS FOR. A document with no expiry column is 'valid' when held: it does
        -- not expire, so calling it 'unknown' would invent a problem the supplier cannot fix.
        'document_status', case
          when h.path is null then 'missing'
          when h.expiry is null then 'valid'
          when h.expiry < current_date then 'expired'
          when h.expiry < current_date + 60 then 'expiring'
          else 'valid' end,
        'impact_level', h.impact,
        'impact_why', h.impact_why)
      order by case h.impact when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end, h.label)
      from held h), '[]'::jsonb),
    'impact_basis', 'impact_level is a stated QuotesDone policy about what each document gates — not a number derived from your history',
    'summary', jsonb_build_object(
      'held', (select count(*) from held where path is not null),
      'total', (select count(*) from held),
      'expired', (select count(*) from held where path is not null and expiry is not null and expiry < current_date),
      'expiring', (select count(*) from held where path is not null and expiry is not null
                     and expiry >= current_date and expiry < current_date + 60),
      -- The one number that decides whether they can trade at all, surfaced on its own.
      'blocking_missing', (select count(*) from held where path is null and impact = 'critical'))
  );
$function$;
