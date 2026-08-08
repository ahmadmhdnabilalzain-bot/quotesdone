-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726232423   name: catalogue_centric_coverage_view
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Measure coverage from the CATALOGUE side, not the agent side.
-- v_knowledge_compliance keys on category_agents.slug, so a catalogue category served by a
-- legacy agent under a different slug reads as covered while holding no standard knowledge.
create or replace view public.v_category_coverage as
select c.num, c.slug as catalog_slug, c.name, c.regulated,
       m.agent_slug,
       (m.agent_slug = c.slug) as agent_is_canonical,
       coalesce((select count(*) from agent_knowledge k
                 where k.agent_key = 'cat:'||c.slug
                   and k.topic in (select module from knowledge_module_standard where required)),0) as standard_modules,
       coalesce((select count(*) from agent_knowledge k
                 where k.agent_key = 'cat:'||coalesce(m.agent_slug,'~none~')),0) as legacy_rows_elsewhere,
       (select count(distinct l.id) from lead_trade_map t
          join leads l on l.invite_trades && array[t.trade_key]
         where t.catalog_slug = c.slug) as supplier_supply,
       case
         when coalesce((select count(*) from agent_knowledge k where k.agent_key='cat:'||c.slug
                        and k.topic in (select module from knowledge_module_standard where required)),0) = 14
              then 'COMPLIANT'
         when m.status = 'mapped' then 'MAPPED_NOT_TO_STANDARD'
         else 'NO_AGENT' end as coverage
from catalog_supplier_categories c
left join category_agent_map m on m.catalog_slug = c.slug;

comment on view public.v_category_coverage is 'Honest coverage of the 84 catalogue categories: COMPLIANT requires 14 standard modules under the canonical slug.';
