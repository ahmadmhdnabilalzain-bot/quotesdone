-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709092754   name: uae_regulatory_catalog
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.reg_catalog (
  id bigint generated always as identity primary key,
  jurisdiction text not null,          -- federal, dubai, abu-dhabi, sharjah, ajman, rak, fujairah, uaq, free-zone
  authority text not null,
  code_name text not null,
  domain text not null,                -- fire, building, electrical, water, telecom, green, security, roads, health, product-standards, safety, environment, food, lifts
  categories text[],                   -- service slugs this governs (null = cross-cutting)
  priority int not null default 2,     -- 1 critical, 2 important, 3 niche
  copyright text not null default 'free',   -- free | copyrighted
  source_url text,
  compliance_source_id bigint,         -- link to compliance_sources when downloaded
  status text not null default 'needs_source', -- indexed | downloaded_stub | needs_source | reference_only
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(authority, code_name)
);
revoke all on public.reg_catalog from anon, authenticated;

insert into public.reg_catalog(jurisdiction,authority,code_name,domain,priority,copyright,status,notes) values
-- FEDERAL
('federal','UAE Civil Defence (MOI)','UAE Fire and Life Safety Code of Practice','fire',1,'free','needs_source','THE national fire code — critical for fire/MEP/fit-out. Dubai & ADCD apply it locally.'),
('federal','MoIAT / ESMA','UAE.S / ECAS product standards & technical regulations','product-standards',1,'free','needs_source','Emirates national standards, low-voltage/products conformity.'),
('federal','TDRA','In-building telecom infrastructure regulation','telecom',2,'free','indexed',NULL),
('federal','MOCCAE','Federal environment & climate regulations','environment',3,'free','needs_source',NULL),
('federal','GCAA','Aviation obstacle / height & crane limitations','safety',3,'free','needs_source','Near-airport height/crane NOCs.'),
('federal','MOHRE','Labour & occupational safety (heat/midday break, worker welfare)','safety',2,'free','needs_source',NULL),
('federal','FEWA','Electricity & water wiring/connection regs (Northern Emirates)','electrical',2,'free','indexed',NULL),
-- DUBAI
('dubai','Dubai Municipality','Dubai Building Code (DBC)','building',1,'free','needs_source','Consolidated civil/structural/architectural/MEP code for Dubai.'),
('dubai','Dubai Civil Defence','DCD Fire Protection & Life Safety guidelines','fire',1,'free','needs_source','Dubai application of UAE Fire Code + DCD circulars.'),
('dubai','DEWA','Regulations for electrical installations & green building (Shams Dubai/solar)','electrical',1,'free','indexed',NULL),
('dubai','Dubai Municipality','Al Sa''fat Dubai Green Building Evaluation System','green',1,'free','downloaded_stub','Partial download; needs full PDF.'),
('dubai','SIRA (Dubai Police)','Security systems standards & technical regulations','security',1,'free','indexed',NULL),
('dubai','RTA','Roads, NOC & infrastructure works standards','roads',2,'free','indexed',NULL),
('dubai','Dubai Municipality','Code of Construction Safety Practice','safety',2,'free','needs_source',NULL),
('dubai','Dubai Municipality','Drainage & irrigation / sewerage connection code','water',3,'free','needs_source',NULL),
('dubai','Trakhees (PCFC)','EHS & green building regulations (Dubai free zones)','building',2,'free','downloaded_stub',NULL),
('dubai','Dubai Development Authority (TECOM)','Building & fit-out codes (DDA free zones)','building',2,'free','downloaded_stub',NULL),
('dubai','DHA','Health facility design & guidelines','health',3,'free','downloaded_stub',NULL),
('dubai','KHDA','School/nursery facility requirements','building',3,'free','needs_source',NULL),
-- ABU DHABI
('abu-dhabi','Abu Dhabi DMT','Abu Dhabi International Building Code (ADIBC)','building',1,'free','downloaded_stub','Stub download; needs full PDF.'),
('abu-dhabi','Abu Dhabi Civil Defence (ADCD)','Fire & life safety requirements','fire',1,'free','needs_source',NULL),
('abu-dhabi','Abu Dhabi DMT','Estidama Pearl Building Rating System','green',1,'free','indexed',NULL),
('abu-dhabi','ADDC','Abu Dhabi electrical & water connection regulations','electrical',2,'free','needs_source',NULL),
('abu-dhabi','AADC','Al Ain electrical & water connection regulations','electrical',3,'free','needs_source',NULL),
('abu-dhabi','OSHAD','Occupational Safety & Health System Framework','safety',2,'free','needs_source',NULL),
('abu-dhabi','DoH Abu Dhabi','Health facility standards','health',3,'free','downloaded_stub',NULL),
('abu-dhabi','EAD','Environment, Health & Safety regulations','environment',3,'free','needs_source',NULL),
-- SHARJAH
('sharjah','Sharjah Municipality','Building & construction permit regulations','building',2,'free','downloaded_stub',NULL),
('sharjah','SEWA','Electricity, water & gas regulations','electrical',2,'free','downloaded_stub',NULL),
('sharjah','Sharjah Civil Defence','Fire & life safety requirements','fire',2,'free','needs_source',NULL),
-- NORTHERN EMIRATES
('ajman','Ajman Municipality','Building & construction regulations','building',3,'free','needs_source',NULL),
('rak','RAK Municipality','Building regulations','building',3,'free','needs_source',NULL),
('fujairah','Fujairah Municipality','Building regulations','building',3,'free','needs_source',NULL),
('uaq','Umm Al Quwain Municipality','Building regulations','building',3,'free','needs_source',NULL),
-- REFERENCED INTERNATIONAL STANDARDS (copyrighted — cite + summary only, do NOT ingest full text)
('federal','NFPA (referenced by Civil Defence)','NFPA fire codes (NFPA 13/72/101 etc.)','fire',1,'copyrighted','reference_only','Basis of UAE Fire Code. Store citation + how it applies; do not ingest full text.'),
('federal','IEC / BS 7671 (referenced by DEWA)','Wiring regulations','electrical',1,'copyrighted','reference_only','Referenced by DEWA/ADDC wiring regs.'),
('federal','ASHRAE','HVAC design standards','building',2,'copyrighted','reference_only',NULL),
('federal','ISO / EN','Product & management system standards','product-standards',2,'copyrighted','reference_only',NULL);

-- link catalog rows to existing compliance_sources by authority match (best effort)
update reg_catalog rc set compliance_source_id = cs.id, status = case when exists(select 1 from kb_chunks kc where kc.source_id like 'compliance:'||cs.id||'#%') then 'indexed' else rc.status end
from compliance_sources cs
where rc.compliance_source_id is null
  and (lower(cs.authority) = lower(rc.authority)
       or (rc.authority ilike '%DEWA%' and cs.authority ilike '%DEWA%')
       or (rc.authority ilike '%SIRA%' and cs.authority ilike '%SIRA%')
       or (rc.authority ilike '%Estidama%' and cs.authority ilike '%Estidama%')
       or (rc.authority ilike '%RTA%' and cs.authority ilike '%RTA%')
       or (rc.authority ilike '%TDRA%' and cs.authority ilike '%TDRA%')
       or (rc.authority ilike '%FEWA%' and cs.authority ilike '%FEWA%'));
