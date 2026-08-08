-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706020039   name: quotation_evaluation_standard
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists quote_requirements (
  category text primary key,           -- 'default' = universal fallback
  required_sections jsonb not null default '[]'::jsonb,  -- [{key,label,mandatory}]
  updated_at timestamptz default now()
);
alter table quote_requirements enable row level security;
revoke all on quote_requirements from anon, authenticated;

-- Hard gate: score an extracted quote (jsonb) against the category standard.
create or replace function quote_gate(p_category text, p_quote jsonb)
returns jsonb language plpgsql stable as $$
declare reqs jsonb; sec jsonb; k text; mand boolean; present boolean; v jsonb;
  miss jsonb := '[]'::jsonb; pres jsonb := '[]'::jsonb; tot_m int := 0; ok_m int := 0;
begin
  select required_sections into reqs from quote_requirements where category = p_category;
  if reqs is null then select required_sections into reqs from quote_requirements where category = 'default'; end if;
  if reqs is null then return jsonb_build_object('pass', true, 'score', 100, 'missing', '[]'::jsonb, 'note', 'no standard defined'); end if;
  for sec in select * from jsonb_array_elements(reqs) loop
    k := sec->>'key'; mand := coalesce((sec->>'mandatory')::boolean, false);
    v := p_quote -> k;
    present := (v is not null) and (
       (jsonb_typeof(v) = 'string'  and length(trim(v #>> '{}')) > 0) or
       (jsonb_typeof(v) = 'array'   and jsonb_array_length(v) > 0) or
       (jsonb_typeof(v) = 'object'  and v <> '{}'::jsonb) or
       (jsonb_typeof(v) in ('number','boolean')));
    if mand then tot_m := tot_m + 1; if present then ok_m := ok_m + 1; end if; end if;
    if present then pres := pres || to_jsonb(k);
    else miss := miss || jsonb_build_object('key', k, 'label', sec->>'label', 'mandatory', mand); end if;
  end loop;
  return jsonb_build_object(
    'pass', (tot_m = 0 or ok_m = tot_m),
    'mandatory_total', tot_m, 'mandatory_present', ok_m,
    'score', case when jsonb_array_length(reqs) > 0 then round(100.0 * jsonb_array_length(pres) / jsonb_array_length(reqs)) else 100 end,
    'present', pres, 'missing', miss);
end $$;
revoke all on function quote_gate(text, jsonb) from anon, authenticated;

insert into quote_requirements (category, required_sections) values
('default', $j$[
 {"key":"company_details","label":"Company details & contact","mandatory":true},
 {"key":"trade_license","label":"Valid trade licence reference","mandatory":true},
 {"key":"scope","label":"Scope of work","mandatory":true},
 {"key":"boq","label":"Detailed BOQ / itemised breakdown","mandatory":true},
 {"key":"materials","label":"Materials specified","mandatory":false},
 {"key":"brand_model","label":"Brand & model per item","mandatory":true},
 {"key":"country_of_origin","label":"Country of origin","mandatory":false},
 {"key":"specifications","label":"Technical specifications","mandatory":false},
 {"key":"unit_price","label":"Unit price & quantity","mandatory":true},
 {"key":"compliance_statement","label":"Compliance statement","mandatory":false},
 {"key":"standards","label":"Standards followed","mandatory":false},
 {"key":"installation_method","label":"Installation / method statement","mandatory":false},
 {"key":"testing_commissioning","label":"Testing & commissioning","mandatory":false},
 {"key":"warranty","label":"Warranty","mandatory":true},
 {"key":"maintenance","label":"Preventive maintenance (if applicable)","mandatory":false},
 {"key":"exclusions","label":"Exclusions","mandatory":true},
 {"key":"assumptions","label":"Assumptions","mandatory":false},
 {"key":"lead_time","label":"Delivery / lead time","mandatory":true},
 {"key":"timeline","label":"Project timeline","mandatory":false},
 {"key":"payment_terms","label":"Payment terms","mandatory":true},
 {"key":"validity","label":"Validity period","mandatory":true},
 {"key":"datasheets","label":"Supporting datasheets / brochures","mandatory":false}
]$j$::jsonb),
('cctv-security', $j$[
 {"key":"company_details","label":"Company details & SIRA licence","mandatory":true},
 {"key":"trade_license","label":"Trade licence + SIRA licence reference","mandatory":true},
 {"key":"scope","label":"Scope: camera count, coverage, NVR","mandatory":true},
 {"key":"boq","label":"Itemised BOQ (cameras, NVR, cabling, PoE)","mandatory":true},
 {"key":"brand_model","label":"Camera/NVR brand & model","mandatory":true},
 {"key":"specifications","label":"Resolution, lens, IR, IP rating, storage/retention","mandatory":true},
 {"key":"unit_price","label":"Unit price & quantity","mandatory":true},
 {"key":"standards","label":"SIRA compliance / retention statement","mandatory":true},
 {"key":"installation_method","label":"Installation & cabling method","mandatory":false},
 {"key":"testing_commissioning","label":"Testing & commissioning","mandatory":true},
 {"key":"warranty","label":"Warranty","mandatory":true},
 {"key":"lead_time","label":"Lead time","mandatory":true},
 {"key":"payment_terms","label":"Payment terms","mandatory":true},
 {"key":"validity","label":"Validity period","mandatory":true},
 {"key":"datasheets","label":"Camera/NVR datasheets","mandatory":false}
]$j$::jsonb);

-- sanity: score an intentionally-incomplete quote
select quote_gate('cctv-security', '{"company_details":"ABC LLC","scope":"16 cameras","boq":[{"d":"x"}],"warranty":"1yr"}'::jsonb) as demo;
