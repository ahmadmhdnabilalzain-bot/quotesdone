-- THE ALIGNMENT GAP, stated as a number: of 470 canonical subcategories, ZERO share a slug with any of
-- the 106 trade agents. So the taxonomy suppliers and RFQs are classified into had no relationship to
-- the agents that hold the category knowledge and answer the inquiry. This table is that bridge:
-- subcategory -> the agent whose knowledge covers it. With it, one join takes an inquiry from detected
-- subcategory to the right agent, and from that agent to the suppliers grouped under it.
create table if not exists subcategory_agent_map (
  sub_slug text primary key references catalog_subcategories(slug) on delete cascade,
  agent_slug text not null,
  confidence text not null default 'medium',   -- high | medium | low | none
  note text,
  created_at timestamptz not null default now()
);
create index if not exists subcategory_agent_map_agent_idx on subcategory_agent_map (agent_slug);
alter table subcategory_agent_map enable row level security;
revoke all on subcategory_agent_map from anon, authenticated;

-- One place that answers "who handles this supplier, and does that agent actually know the trade?"
create or replace view v_supplier_alignment as
select l.id                as lead_id,
       l.company_name,
       l.email,
       l.emirate,
       ls.sub_slug,
       cs.name            as subcategory_name,
       ls.domain_slug,
       cd.name            as domain_name,
       ls.is_primary,
       ls.score,
       m.agent_slug,
       m.confidence       as mapping_confidence,
       (ca.slug is not null)                          as agent_exists,
       (ak.modules is not null and ak.modules > 0)    as agent_has_knowledge,
       coalesce(ak.modules, 0)                        as knowledge_modules
from leads l
join lead_subcategory ls        on ls.lead_id = l.id
join catalog_subcategories cs   on cs.slug = ls.sub_slug
join catalog_domains cd         on cd.slug = ls.domain_slug
left join subcategory_agent_map m on m.sub_slug = ls.sub_slug
left join category_agents ca      on ca.slug = m.agent_slug and ca.folded_into is null
left join (select replace(agent_key,'cat:','') slug, count(*) modules
             from agent_knowledge where agent_key like 'cat:%' group by 1) ak
       on ak.slug = m.agent_slug;

revoke all on v_supplier_alignment from anon, authenticated;