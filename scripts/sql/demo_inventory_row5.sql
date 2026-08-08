-- ROW #5 §24 — STOCK POSITION ON THE DEMO CATALOGUE, ON BOTH PROJECTS.
--
-- supplier_product has no stock columns. It has `status` and an `attributes` jsonb, and the
-- attributes are already where the catalogue's real facts live — capacity_cfm, power_kw,
-- refrigerant, compatible_projects, all extracted from the supplier's own PDF.
--
-- Adding stock COLUMNS would be the wrong move for a fact that is per-supplier, per-product and
-- constantly stale: a manufacturer holds none of a made-to-order AHU and a trader holds forty fan
-- coil units on a shelf. Availability belongs beside capacity and refrigerant, not in a new table.
-- So this seeds three attribute keys on the demo catalogue, and the Inventory surface reads them
-- and says "not stated" where a supplier has not filled them in — which is the honest reading for
-- every real supplier on the platform today, and a prompt rather than a blank.
--
-- Fenced by the same predicate as everything else in this session: the WHERE names the fixture
-- marker, so this cannot touch a product belonging to a real company.
update public.supplier_product p
set attributes = coalesce(p.attributes, '{}'::jsonb) || v.stock
from (values
  ('AHU-X500',  '{"availability":"made_to_order","stock_qty":"0","restock_weeks":"10"}'::jsonb),
  ('RTU-R200',  '{"availability":"in_stock","stock_qty":"6","restock_weeks":"4"}'::jsonb),
  ('FCU-F80',   '{"availability":"in_stock","stock_qty":"180","restock_weeks":"2"}'::jsonb),
  ('CH-C1200',  '{"availability":"made_to_order","stock_qty":"0","restock_weeks":"16"}'::jsonb)
) as v(key, stock)
where p.external_key = v.key
  and p.supplier_id in (select id from public.leads where source = 'qd_demo_fixture');
