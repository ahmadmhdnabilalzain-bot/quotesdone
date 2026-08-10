-- spec_backlog#205: "Add the missing authority and source mappings for routes 38, 39, 41, 61, 62".
--
-- The mapping was never missing from the CORPUS -- it was missing from the COLUMN the gate reads.
-- Every uae_regulations record carries its regulator in structured_data->>'publisher' with a
-- source_id beside it ("UAE Ministry of Justice" / "UAE-MOJ", "UAE Federal Tax Authority",
-- "Dubai Health Authority", ...), and kb_stage.records.authority sat NULL on all 3,781 records
-- under those five routes. v_kb_route_regulatory_status counts distinct named authorities off
-- that column, so five of the most heavily licensed trades in the catalogue -- Accounting & Audit,
-- Tax, Law, Medical Equipment, Pharmaceuticals -- looked ungoverned.
--
-- Nothing is invented here: the authority is copied from the record's own publisher field, and
-- only where the record is a uae_regulations record that names one. A record with no publisher
-- stays NULL and its route stays blocked.
update kb_stage.records
   set authority = nullif(btrim(structured_data->>'publisher'), '')
 where module = 'uae_regulations'
   and (authority is null or btrim(authority) = '')
   and nullif(btrim(structured_data->>'publisher'), '') is not null;
