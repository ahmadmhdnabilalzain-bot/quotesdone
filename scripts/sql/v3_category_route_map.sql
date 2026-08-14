-- The bridge between the customer-facing trade slug and the 86-route catalogue.
--
-- fn_kb_route_decide resolves 29 of the 56 category_specs slugs and asks a clarifying
-- question for the other 27 — which is right for customer prose ("aluminium" really could
-- be a window, a facade or a fit-out) and wrong for a system identifier that the company
-- itself assigned. So the identifier gets a deterministic map and the free-text resolver is
-- left exactly as it is: no alias is added to kb_operational_alias, and the 344 route tests
-- cannot move.
--
-- Only mappings where the route name plainly names the trade are seeded. Thirteen slugs are
-- deliberately absent — acrylic, garage-doors, demolition, general, general-building-contracting,
-- movers, marble-granite, masonry, pest, safety, tents-and-shade-structures and the rest —
-- because no single route plainly covers them. For those the checklist returns the resolver's
-- clarifying question, which is the behaviour the specification asks for.
create table if not exists category_route_map (
  category    text primary key,
  catalog_num integer not null references kb_operational_route(catalog_num) on delete cascade,
  note        text,
  decided_by  text not null default 'v3_runtime_build',
  created_at  timestamptz not null default now()
);
alter table category_route_map enable row level security;

insert into category_route_map (category, catalog_num, note) values
  ('aluminium',      19, 'route 19 is aluminium-and-glass-suppliers'),
  ('glass',          19, 'route 19 is aluminium-and-glass-suppliers'),
  ('av-systems',     33, 'route 33 is av-and-media-equipment-suppliers'),
  ('carpets',        18, 'carpet is a floor finish; route 18 is flooring-suppliers'),
  ('elevators',      86, 'route 86 is lifts-and-escalator-suppliers'),
  ('fitout',         16, 'route 16 is fit-out-contractors-interior-fit-out-suppliers'),
  ('gypsum',         17, 'route 17 is gypsum-and-false-ceiling-suppliers'),
  ('it-networking',  35, 'route 35 is it-companies-it-services-providers'),
  ('kitchens',       24, 'route 24 is kitchen-and-bathroom-suppliers'),
  ('painting',       21, 'route 21 is paints-and-finishing-materials-suppliers'),
  ('wallpaper',      21, 'a wall finish; route 21 is paints-and-finishing-materials-suppliers'),
  ('plumbing',       11, 'route 11 is plumbing-and-sanitaryware-suppliers'),
  ('signage',        85, 'route 85 is signage-and-printing-suppliers'),
  ('solar',          67, 'route 67 is renewable-energy-companies-solar-ev-battery'),
  ('steel',           2, 'route 2 is steel-and-reinforcement-suppliers'),
  ('swimming-pools', 25, 'route 25 is swimming-pool-suppliers-and-contractors')
on conflict (category) do update set catalog_num = excluded.catalog_num, note = excluded.note;
