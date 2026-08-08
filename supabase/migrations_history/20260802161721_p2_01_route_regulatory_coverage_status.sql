-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260802161721   name: p2_01_route_regulatory_coverage_status
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- PHASE 2 CORRECTION 2 - REGULATORY COVERAGE IS ASSERTED, NOT INFERRED
--
-- The crosswalk inferred "no regulator" from "no authority named in the records". The founder is
-- right that this is unsound: Pharmaceuticals showing zero authorities does not mean pharmaceuticals
-- are unregulated, it means the corpus does not say so. Absence of evidence was being read as
-- evidence of absence - the same fail-open mistake the Control Mode work existed to remove, applied
-- to regulation instead of to actions.
--
-- Coverage is now an explicit, four-valued assertion that someone has to make on purpose:
--   confirmed_none    - checked, and this route genuinely carries no regulatory requirement
--   confirmed_covered - checked, and the authorities and sources present are sufficient
--   incomplete        - known to be missing mappings; work identified
--   requires_review   - nobody has checked. THE DEFAULT.
--
-- Default is requires_review because the cost is asymmetric: holding a route out of activation for
-- a week costs a week, activating a regulated route with no escalation path costs a permit, a
-- customer, or a licence.

alter table public.kb_operational_route
  add column if not exists regulatory_coverage_status text not null default 'requires_review';

alter table public.kb_operational_route drop constraint if exists kb_route_reg_coverage_chk;
alter table public.kb_operational_route add constraint kb_route_reg_coverage_chk
  check (regulatory_coverage_status in ('confirmed_none','confirmed_covered','incomplete','requires_review'));

alter table public.kb_operational_route add column if not exists regulatory_coverage_note text;
alter table public.kb_operational_route add column if not exists regulatory_reviewed_by text;
alter table public.kb_operational_route add column if not exists regulatory_reviewed_at timestamptz;

-- The five the founder named. Each shows zero named authorities in the corpus and each is, in fact,
-- a licensed profession or a controlled product class in the UAE.
update public.kb_operational_route
   set regulatory_coverage_status = 'requires_review',
       regulatory_coverage_note = case catalog_num
         when 38 then 'Zero authorities in corpus. Audit is licensed - UAE Ministry of Economy and Tourism register, ADGM/DIFC regimes. Mapping missing.'
         when 39 then 'Zero authorities in corpus. Tax agents are registered with the Federal Tax Authority. Mapping missing.'
         when 41 then 'Zero authorities in corpus. Legal practice is licensed per emirate (Dubai Legal Affairs Department, ADJD). Mapping missing.'
         when 61 then 'Zero authorities in corpus. Medical devices are controlled by MOHAP and the health authorities (DHA, DoH Abu Dhabi). Mapping missing.'
         when 62 then 'Zero authorities in corpus. Pharmaceuticals are controlled by MOHAP registration and import permits. Mapping missing.'
       end,
       regulatory_reviewed_at = now(),
       regulatory_reviewed_by = 'founder instruction 2 Aug 2026'
 where catalog_num in (38, 39, 41, 61, 62);

-- Everything else starts unreviewed, which is the honest state. Nothing is silently promoted.

create or replace function public.fn_kb_route_activation_blocked(p_catalog_num int)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; v_reasons text[] := '{}';
begin
  select * into r from public.kb_operational_route where catalog_num = p_catalog_num;
  if not found then
    return jsonb_build_object('blocked', true, 'reasons', array['no such route']);
  end if;

  if r.regulatory_coverage_status <> 'confirmed_none'
     and r.regulatory_coverage_status <> 'confirmed_covered' then
    v_reasons := v_reasons || ('regulatory coverage is ' || r.regulatory_coverage_status);
  end if;

  if not exists (select 1 from public.kb_operational_route_map m where m.catalog_num = p_catalog_num) then
    v_reasons := v_reasons || 'no mapped subcategory';
  end if;

  if not exists (select 1 from public.kb_operational_alias a
                  where a.catalog_num = p_catalog_num and a.language = 'ar') then
    v_reasons := v_reasons || 'no Arabic alias';
  end if;

  return jsonb_build_object('blocked', array_length(v_reasons, 1) is not null,
                            'reasons', coalesce(v_reasons, '{}'),
                            'regulatory_coverage_status', r.regulatory_coverage_status,
                            'route', r.catalog_name);
end $fn$;

revoke all on function public.fn_kb_route_activation_blocked(int) from public, anon, authenticated;

comment on column public.kb_operational_route.regulatory_coverage_status is
  'Asserted, never inferred. requires_review is the default because zero named authorities in the corpus means nobody checked, not that nothing applies. fn_kb_route_activation_blocked refuses activation until it is confirmed_none or confirmed_covered.';

create or replace view public.v_kb_route_regulatory_status as
select r.catalog_num, r.catalog_name, r.regulatory_coverage_status, r.regulatory_coverage_note,
       (select count(distinct nullif(btrim(k.authority),''))
          from public.kb_operational_route_map m
          join kb_stage.records k on k.subcategory_slug = m.subcategory_slug
         where m.catalog_num = r.catalog_num) as named_authorities_in_corpus,
       public.fn_kb_route_activation_blocked(r.catalog_num) as activation_gate
  from public.kb_operational_route r;

select regulatory_coverage_status, count(*) from public.kb_operational_route group by 1;
