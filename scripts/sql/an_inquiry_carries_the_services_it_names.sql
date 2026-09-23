-- AN INQUIRY CARRIES THE SERVICES IT NAMES (22 Sep 2026, agent: sales_engineer, finding SP-F-01).
--
-- THE DEFECT. The founder calls the Services tab "our cross matching main source" (instruction 438,
-- 15 Sep 2026) and public.fn_match_capability has taken p_services since then: when the inquiry names
-- a service, only a supplier whose CONFIRMED service list (plus one curated implication level, minus
-- its removals — fn_services_effective) covers one of them is a candidate. MEASURED 22 Sep 2026: not
-- one caller passed it. sales_engineer (the only production matcher), customer_api's preview,
-- inquiry_intake's supplier count and public_site all sent 8 arguments, so p_services defaulted to
-- '{}', the service gate never fired, and every request in production was matched at TRADE level.
-- The services a supplier spends its Services tab confirming decided nothing.
--
-- WHAT THIS COLUMN IS. The '<trade>.<code>' keys the inquiry's own brief and BOQ name, read with the
-- SAME exact-alias matcher that reads the supplier's sentence (_shared/service_rewrite.ts
-- servicesFromText, through _shared/service_vocabulary.ts). Exact or none (founder, 14 Sep 2026):
-- no similarity, no stemmer, no nearest service.
--
--   null  the keys were never derived (an inquiry older than this column, or one nothing has matched
--         since). sales_engineer derives and stores them the first time it matches the inquiry.
--   '{}'  derived, and the brief names no service this taxonomy knows.
--
-- BOTH ARE SAFE. An empty p_services leaves every candidate through, so an inquiry whose words the
-- vocabulary does not recognise falls back to trade-level matching exactly as today. Nothing is ever
-- dropped for want of a service key; the gate only ever applies when the inquiry really named one.
--
-- NOT A NEW TABLE, so there is no new RLS to write: inquiries' own policies already govern every
-- reader of this row, and this column is served to a supplier only through the scrubbed
-- inquiries_supplier_safe view, which does not select it.

alter table public.inquiries add column if not exists service_keys text[];

comment on column public.inquiries.service_keys is
  'The taxonomy service keys (<trade>.<code>) this inquiry names, read by the exact-alias matcher in '
  '_shared/service_vocabulary.ts and passed to fn_match_capability as p_services. null = never derived; '
  '{} = derived and no service named (trade-level matching). Written by sales_engineer''s match action. '
  'The derivation happens ONCE: null is derived and stored on the first match, and {} is then kept as the '
  'answer, so an inquiry stored as {} stays trade-level even after taxonomy_trade_service gains a service '
  'its brief would now name (211 active rows, added to during Sep 2026). To force a re-read, set the '
  'column back to null -- update public.inquiries set service_keys = null where id = ... -- and the next '
  'match derives it again against the current vocabulary.';

-- ── BACKFILL ────────────────────────────────────────────────────────────────────────────────────
-- Every inquiry that existed when this column was added: 3 rows, all ZZ DEMO founder-tour requests
-- (measured 22 Sep 2026). Their keys were derived OFFLINE with the very function the runtime uses —
-- serviceKeysOf(brief, boq, serviceVocab()) over production's 211 active services — rather than with
-- a second SQL implementation of the matcher, because a second reader of the same vocabulary is a
-- second answer about who receives a request. The brief is the same string the match action builds:
-- summary, raw_input, category and keywords, then every string in the BOQ.
--
--   d958e1ea  "Gypsum partitions and false ceiling for an office fit-out in Business Bay, Dubai"
--   8b287960  "False ceilings and gypsum cornice for a private villa in Khalifa City, Abu Dhabi"
--   a179ea8d  "Internal painting for a retail unit handover in Al Nahda, Sharjah"
--
-- A row that has since been deleted simply updates nothing; a row added after this file was written
-- keeps null and is derived on its first match.
update public.inquiries set service_keys = '{flooring.tiling,gypsum.acoustic_ceiling,gypsum.false_ceiling,gypsum.partitions,interior_fitout.office}'
 where id = 'd958e1ea-54f4-45a1-9214-d622ac52dce1' and service_keys is null;
update public.inquiries set service_keys = '{electrical.lighting,gypsum.acoustic_ceiling,gypsum.decorative,gypsum.false_ceiling,gypsum.partitions}'
 where id = '8b287960-ce32-4a2d-9b79-0cfa8804514a' and service_keys is null;
update public.inquiries set service_keys = '{flooring.epoxy,painting.decorative,painting.exterior,painting.interior}'
 where id = 'a179ea8d-f94a-4cd1-9bf4-19227d089b53' and service_keys is null;
