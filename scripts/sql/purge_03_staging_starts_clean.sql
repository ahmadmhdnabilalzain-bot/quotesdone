-- PURGE 03 — STAGING ONLY. "i want us to start clean."
--
-- RUN AGAINST STAGING ONLY. Not promoted. Production keeps its 20,465 real leads; staging has no
-- real lead data by design and never should.
--
--   node scripts/apply_sql.mjs scripts/sql/purge_03_staging_starts_clean.sql --ref=pglpqrhvozwepymcuunn
--
-- WHY A BLANKET DELETE HERE AND A FILTER ON PRODUCTION. The demo filter has now missed a family
-- TWICE. It knew 'ZZ DEMO' / @example.invalid; it missed 'QD Demo…' / @example.com /
-- source=demo_factory; and it missed these two, which carry no demo marker at all:
--
--   3178  "QD Probe Lead"             source qd_row4_verify, no email, no phone, no category
--   3251  "QD apprmshvxcdc supplier"  no source at all
--
-- Both are test probes from 6 Aug. Chasing a fourth naming convention is the wrong shape of fix:
-- on staging the correct rule is not "delete the rows that look fake", it is "there is no real
-- lead data here". A blanket delete cannot miss a family. Production keeps the filter, because
-- there the opposite is true and a wrong delete is unrecoverable.
--
-- WHAT IS DELIBERATELY KEPT:
--   category_quote_specs         141 rows, identical on both projects — reference config
--   catalog_supplier_categories   86 rows, identical on both projects — reference config
--   review_chain, os_review      the company's own governance record. Not an inquiry, customer or
--                                supplier, and it is the evidence that reviewer independence
--                                works. Deleting an audit trail to make a room look tidy is not
--                                cleaning.

begin;

-- leads and everything keyed to one
delete from lead_trade_map;
delete from supplier_score;
delete from supplier_capabilities;
delete from leads;

-- test residue from driving the product by hand
delete from artifact_review;   -- 5 rows my own alignment tests left on staging; production has 0
delete from notifications;
delete from doc_versions;
delete from wa_messages;

do $$
begin
  raise notice 'STAGING NOW: leads=% scores=% caps=% lead_trade_map=% notifications=% doc_versions=% wa_messages=% artifact_review=% | kept: category_quote_specs=% catalog_supplier_categories=%',
    (select count(*) from leads), (select count(*) from supplier_score),
    (select count(*) from supplier_capabilities), (select count(*) from lead_trade_map),
    (select count(*) from notifications), (select count(*) from doc_versions),
    (select count(*) from wa_messages), (select count(*) from artifact_review),
    (select count(*) from category_quote_specs), (select count(*) from catalog_supplier_categories);
end $$;

commit;
