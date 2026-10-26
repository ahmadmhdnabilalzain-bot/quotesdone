-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706015936   name: qualification_playbooks
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists qualification_playbooks (
  id bigint generated always as identity primary key,
  category text not null,
  version int not null default 1,
  status text not null default 'active',   -- active | draft | superseded
  questions jsonb not null default '[]'::jsonb,
  effective_date date default current_date,
  created_at timestamptz default now(),
  unique (category, version)
);
alter table qualification_playbooks enable row level security;
revoke all on qualification_playbooks from anon, authenticated;

create or replace function playbook_for(p_category text)
returns jsonb language sql stable as $$
  select questions from qualification_playbooks
  where category = p_category and status = 'active'
  order by version desc limit 1;
$$;
revoke all on function playbook_for(text) from anon, authenticated;

insert into qualification_playbooks (category, questions) values
('cctv-security', $j$[
 {"key":"environment","label":"Indoor, outdoor, or both?","type":"choice","required":true,"options":["Indoor","Outdoor","Both"]},
 {"key":"premise_type","label":"Residential, commercial, retail, industrial or warehouse?","type":"choice","required":true,"options":["Residential","Commercial","Retail","Industrial","Warehouse"]},
 {"key":"num_cameras","label":"Approximately how many cameras / coverage points?","type":"number","required":true},
 {"key":"entrances","label":"How many entrances/exits must be covered?","type":"number","required":false},
 {"key":"resolution","label":"Required camera resolution?","type":"choice","required":false,"options":["2MP / 1080p","4MP","5MP","8MP / 4K"]},
 {"key":"night_vision","label":"Night vision / low-light required?","type":"bool","required":true},
 {"key":"facial_recognition","label":"Facial recognition needed?","type":"bool","required":false},
 {"key":"anpr","label":"Number-plate recognition (ANPR) at gates/entries?","type":"bool","required":false},
 {"key":"retention_days","label":"How many days of recording must be retained?","type":"choice","required":true,"options":["7","14","30","31+ (regulated)","90"],"decision":"31+ days or regulated premises => SIRA-compliant retention required"},
 {"key":"sira_regulated","label":"Is this a SIRA-regulated premises (bank, jewellery, hotel, mall, etc.)?","type":"bool","required":true,"decision":"If yes: only SIRA-licensed installers, SIRA camera/retention/connectivity standards apply"},
 {"key":"remote_view","label":"Remote viewing on mobile/PC required?","type":"bool","required":true},
 {"key":"ndaa","label":"NDAA / government-compliant equipment required?","type":"bool","required":false,"depends_on":{"key":"premise_type","equals":"Commercial"}},
 {"key":"existing_infra","label":"Any existing cabling, NVR or infrastructure to reuse?","type":"bool","required":false},
 {"key":"power","label":"Is power / PoE available at the camera points?","type":"bool","required":false},
 {"key":"mount","label":"Ceiling, wall or pole mounting?","type":"choice","required":false,"options":["Ceiling","Wall","Pole","Mixed"]},
 {"key":"budget","label":"Approximate budget (AED)?","type":"text","required":false},
 {"key":"timeline","label":"Required completion date / timeline?","type":"text","required":false},
 {"key":"drawings","label":"Do you have a floor plan or site layout?","type":"bool","required":false}
]$j$::jsonb),

('electrical', $j$[
 {"key":"work_type","label":"New installation, addition, or repair/maintenance?","type":"choice","required":true,"options":["New installation","Addition/upgrade","Repair/maintenance"]},
 {"key":"premise_type","label":"Residential, commercial or industrial?","type":"choice","required":true,"options":["Residential","Commercial","Industrial"]},
 {"key":"scope","label":"What is required? (wiring, DB/panel, lighting, power points, load upgrade, etc.)","type":"text","required":true},
 {"key":"dewa_connection","label":"Does this involve a DEWA/utility connection, meter or load change?","type":"bool","required":true,"decision":"If yes: DEWA-registered contractor + DEWA approval/inspection required"},
 {"key":"load_kw","label":"Approximate electrical load (kW) if known?","type":"text","required":false},
 {"key":"area_sqft","label":"Approximate area (sq ft) served?","type":"text","required":false},
 {"key":"existing_drawings","label":"Do you have electrical drawings / single-line diagram?","type":"bool","required":false},
 {"key":"certification","label":"Do you need certified completion / DEWA inspection sign-off?","type":"bool","required":true},
 {"key":"budget","label":"Approximate budget (AED)?","type":"text","required":false},
 {"key":"timeline","label":"Required completion date?","type":"text","required":false}
]$j$::jsonb),

('interior-design', $j$[
 {"key":"space_type","label":"What type of space? (office, retail, F&B, villa, apartment, clinic, etc.)","type":"text","required":true},
 {"key":"area_sqft","label":"Approximate area (sq ft)?","type":"number","required":true},
 {"key":"scope","label":"Full turnkey fit-out or specific trades only?","type":"choice","required":true,"options":["Full turnkey fit-out","Specific trades only"]},
 {"key":"location_type","label":"Is it in a mall, tower, free zone or standalone building?","type":"choice","required":false,"options":["Mall","Tower/Building","Free zone","Standalone"],"decision":"Mall/free zone => landlord + authority (DCD/Trakhees) approvals needed"},
 {"key":"approvals","label":"Are authority approvals (Civil Defence / Municipality / landlord) required?","type":"bool","required":true,"decision":"If yes: contractor must handle DCD + Municipality/landlord approvals"},
 {"key":"mep","label":"Does it include MEP (AC, electrical, plumbing, fire)?","type":"bool","required":true},
 {"key":"drawings","label":"Do you have design drawings / a concept, or need design too?","type":"choice","required":false,"options":["Have drawings","Need design + build"]},
 {"key":"handover_date","label":"Required handover date?","type":"text","required":false},
 {"key":"budget","label":"Approximate budget (AED)?","type":"text","required":false}
]$j$::jsonb);

select category, jsonb_array_length(questions) as num_questions from qualification_playbooks order by category;
