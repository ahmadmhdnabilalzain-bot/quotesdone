-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260620235745   name: seo_categories
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.seo_categories (
  slug text primary key,
  name text not null,
  search_term text,
  intro text,
  includes jsonb,
  faqs jsonb,
  sort int default 100,
  generated boolean default false,
  updated_at timestamptz default now()
);

insert into public.seo_categories(slug,name,search_term,sort) values
 ('electrical','Electrical Work & Contractors','electrician',1),
 ('plumbing','Plumbing Services','plumber',2),
 ('ac-maintenance','AC Repair & Maintenance','air conditioning repair',3),
 ('cleaning','Cleaning Services','cleaning company',4),
 ('interior-design','Interior Design & Fit-Out','interior design fit out',5),
 ('joinery-kitchens','Joinery & Kitchen Cabinets','kitchen cabinets joinery',6),
 ('waterproofing','Waterproofing Services','waterproofing',7),
 ('tiling-marble','Tiling & Marble Work','marble and tiling',8),
 ('pest-control','Pest Control','pest control',9),
 ('swimming-pools','Swimming Pool Construction & Maintenance','swimming pool contractor',10),
 ('movers','Movers & Packers','movers and packers',11),
 ('handyman','Handyman & Maintenance','handyman maintenance',12),
 ('facilities-management','Facilities Management','facilities management',13),
 ('ac-duct-cleaning','AC Duct Cleaning','ac duct cleaning',14),
 ('smart-home','Smart Home Automation','home automation',15),
 ('solar','Solar Energy Systems','solar panels installation',16),
 ('curtains-blinds','Curtains & Blinds','curtains and blinds',17),
 ('cctv-security','CCTV & Security Systems','cctv installation',18),
 ('painting','Painting & Decorating','painting services',19),
 ('flooring','Flooring (Tiles, Parquet, Epoxy)','flooring company',20),
 ('false-ceiling','False Ceiling & Gypsum Partitions','false ceiling gypsum',21),
 ('landscaping','Landscaping & Garden Design','landscaping garden',22),
 ('aluminium-glass','Aluminium & Glass Works','aluminium and glass',23),
 ('signage','Signage & 3D Letters','signage company',24)
on conflict (slug) do nothing;

select count(*) as seeded from public.seo_categories;
