-- WHY: The founder maintains a "scoreboard of how much documentation each supplier has shared",
-- but no per-supplier documentation score existed. supplier_score covers response/quality only, and
-- leads.capability_score is 0/20464 populated (dead column). The doc_reminder agent already nudges
-- suppliers but had no way to tell WHO is furthest behind.
-- WHY A VIEW, NOT A COLUMN: a stored column would need a trigger/cron to stay in sync with nine
-- different document path columns plus the documents table, and would silently go stale the moment
-- one of those write paths was missed. A view is recomputed on read and can never drift.
-- WEIGHTS (sum = 100): the trade licence is the mandatory document for a UAE supplier, so it carries
-- the single largest weight (30). An EXPIRED document scores zero for its item and is reported in
-- `missing` separately from a never-supplied one, matching how doc_reminder already phrases it.
create or replace view public.v_supplier_doc_score as
with docs as (
  -- Documents can arrive either as a path column on leads or as a row in public.documents
  -- (email-attachment extraction path). Either counts as "shared".
  select (d.ref_id)::bigint as lead_id,
         bool_or(d.kind = 'licence') as doc_licence,
         bool_or(d.kind = 'catalog') as doc_catalog,
         bool_or(d.kind = 'profile') as doc_profile,
         count(*)::int              as doc_rows
  from public.documents d
  where d.ref_table = 'leads' and d.ref_id ~ '^[0-9]+$'
  group by 1
),
f as (
  select
    l.id                          as lead_id,
    l.company_name,
    coalesce(nullif(btrim(l.claimed_by),''), nullif(btrim(l.email),'')) as contact_email,
    l.approval_status,
    coalesce(l.claimed,false)     as claimed,
    coalesce(l.banned,false)      as banned,
    l.lifecycle_stage,
    cc.name                       as primary_category,
    coalesce(dd.doc_rows,0)       as extracted_doc_rows,
    (coalesce(btrim(l.license_doc_path),'') <> '' or coalesce(dd.doc_licence,false))            as has_licence,
    (l.license_expiry is not null and l.license_expiry < current_date)                          as licence_expired,
    l.license_expiry,
    (coalesce(btrim(l.egr_doc_path),'') <> '')                                                  as has_egr,
    (coalesce(btrim(l.iban_doc_path),'') <> '')                                                 as has_iban,
    (coalesce(btrim(l.vat_doc_path),'') <> '')                                                  as has_vat_doc,
    (coalesce(btrim(l.trn),'') <> '' or coalesce(btrim(l.vat_number),'') <> '')                 as has_vat_no,
    (coalesce(btrim(l.insurance_doc_path),'') <> '')                                            as has_insurance,
    (l.insurance_expiry is not null and l.insurance_expiry < current_date)                      as insurance_expired,
    l.insurance_expiry,
    (coalesce(btrim(l.company_profile_doc_path),'') <> '' or coalesce(dd.doc_profile,false))    as has_profile,
    (coalesce(array_length(l.catalog_doc_paths,1),0) > 0 or coalesce(dd.doc_catalog,false))     as has_catalogue,
    (coalesce(btrim(l.iso_doc_path),'') <> '')                                                  as has_iso,
    (l.iso_expiry is not null and l.iso_expiry < current_date)                                  as iso_expired,
    (coalesce(btrim(l.manufacturer_auth_doc_path),'') <> '')                                    as has_mfa,
    (l.manufacturer_auth_expiry is not null and l.manufacturer_auth_expiry < current_date)      as mfa_expired,
    (coalesce(btrim(l.signed_terms_path),'') <> '')                                             as has_signed_terms
  from public.leads l
  left join docs dd on dd.lead_id = l.id
  left join public.lead_category lc on lc.lead_id = l.id and lc.is_primary
  left join public.catalog_supplier_categories cc on cc.slug = lc.slug
),
s as (
  select f.*,
    ( (case when f.has_licence   and not f.licence_expired   then 30 else 0 end)   -- mandatory, weighs most
    + (case when f.has_egr                                    then 12 else 0 end)
    + (case when f.has_iban                                   then 10 else 0 end)
    + (case when f.has_vat_doc then 10 when f.has_vat_no then 5 else 0 end)        -- certificate beats bare TRN
    + (case when f.has_insurance and not f.insurance_expired  then 10 else 0 end)
    + (case when f.has_profile                                then 10 else 0 end)
    + (case when f.has_catalogue                              then 10 else 0 end)
    + (case when f.has_iso and not f.iso_expired              then  5 else 0 end)
    + (case when f.has_mfa and not f.mfa_expired              then  3 else 0 end)
    )::int as score,
    array_remove(array[
      case when not f.has_licence then 'Trade licence (mandatory)'
           when f.licence_expired then 'Trade licence EXPIRED on '||f.license_expiry::text end,
      case when not f.has_egr        then 'Establishment card' end,
      case when not f.has_iban       then 'Bank IBAN letter' end,
      case when not f.has_vat_doc and not f.has_vat_no then 'VAT certificate / TRN'
           when not f.has_vat_doc                      then 'VAT certificate (TRN on file, document missing)' end,
      case when not f.has_insurance   then 'Insurance certificate'
           when f.insurance_expired   then 'Insurance certificate EXPIRED on '||f.insurance_expiry::text end,
      case when not f.has_profile    then 'Company profile' end,
      case when not f.has_catalogue  then 'Product catalogue' end,
      case when not f.has_iso        then 'ISO certificate'
           when f.iso_expired        then 'ISO certificate EXPIRED' end,
      case when not f.has_mfa        then 'Manufacturer authorisation'
           when f.mfa_expired        then 'Manufacturer authorisation EXPIRED' end,
      case when not f.has_signed_terms then 'Signed Terms & Conditions' end
    ], null) as missing
  from f
)
select
  s.lead_id, s.company_name, s.contact_email, s.primary_category,
  s.approval_status, s.claimed, s.banned, s.lifecycle_stage,
  s.score,
  case when s.score >= 85 then 'A' when s.score >= 70 then 'B'
       when s.score >= 50 then 'C' when s.score >= 25 then 'D' else 'F' end as grade,
  cardinality(s.missing) as missing_count,
  s.missing,
  s.has_licence, s.licence_expired, s.has_egr, s.has_iban,
  s.has_vat_doc, s.has_vat_no, s.has_insurance, s.insurance_expired,
  s.has_profile, s.has_catalogue, s.has_iso, s.has_mfa, s.has_signed_terms,
  s.extracted_doc_rows
from s;

comment on view public.v_supplier_doc_score is
  'Per-supplier documentation completeness, 0-100, recomputed on every read. Weights: trade licence 30 (mandatory), establishment card 12, bank IBAN 10, VAT certificate 10 (5 for TRN only), insurance 10, company profile 10, catalogue 10, ISO 5, manufacturer authorisation 3. Expired documents score 0 and are flagged in `missing`. Source of truth for doc_reminder targeting.';

grant select on public.v_supplier_doc_score to authenticated, service_role;