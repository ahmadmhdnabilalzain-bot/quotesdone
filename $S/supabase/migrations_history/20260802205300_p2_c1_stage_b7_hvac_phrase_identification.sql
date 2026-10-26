-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802205300   name: p2_c1_stage_b7_hvac_phrase_identification
-- SHA-256 of the applied SQL: 12aa50147a63e974b40d1dd8af2dcfded32f06d0ea432f7521160b2b1cce098b
-- Recovered by scripts/recover_one.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.7 (4/6) - PART 3: HVAC phrase identification and the ambiguous abbreviation.
--
-- "Central AC units and electrical panels." confirmed electrical and missed HVAC. In Arabic the
-- same enquiry confirmed both, because مكيف is a trade name and the plural tolerance reaches
-- مكيفات. So the English reader lost a trade the Arabic reader kept - the same parity defect as
-- the container words, in the opposite direction.
--
-- The temptation is to add `ac` as a trade name. That is the wrong fix and Stage B deliberately
-- refused it: `ac` is alternating current, air changes, and the first two letters of access
-- control. A two-letter token that auto-confirms a workstream is a wrong dispatch waiting for the
-- right enquiry.
--
-- The distinction the model already has is exactness, so the correction uses it:
--
--   MULTI-TOKEN, UNAMBIGUOUS  ("central ac", "ac unit", "split ac")  -> trade_name, confirms.
--     Nothing else in this domain is called a central AC. The phrase carries its own context.
--   SHORT AND AMBIGUOUS       ("ac", "a/c")                          -> trade_hint, proposes.
--     Raised for confirmation at conventional-term strength, exactly like `mechanical`. It never
--     activates a workstream on its own, so the answer to a bare "AC" is a question, not a supplier.
--   INSIDE A LONGER TERM      ("access control", "hvac")             -> nothing.
--     Word-boundary matching already guarantees this; the regression suite now proves it, because
--     an invariant nobody tests is an invariant nobody keeps.
--
-- No evidence weight is added or changed. The hint reuses customer_text.trade_hint at 0.400, the
-- weight Stage B.5 already established for a conventional term that implies a trade without
-- naming it.

insert into public.mep_trade_pattern (trade_key, kind, pattern, lang) values
  ('hvac','trade_name','central ac','en'),
  ('hvac','trade_name','central a/c','en'),
  ('hvac','trade_name','central a\.c','en'),
  ('hvac','trade_name','central air conditioner','en'),
  ('hvac','trade_name','central cooling','en'),
  ('hvac','trade_name','ac unit','en'),
  ('hvac','trade_name','a/c unit','en'),
  ('hvac','trade_name','ac system','en'),
  ('hvac','trade_name','split ac','en'),
  ('hvac','trade_name','split a/c','en'),
  ('hvac','trade_name','window ac','en'),
  ('hvac','trade_name','ducted ac','en'),
  ('hvac','trade_name','package ac','en'),
  ('hvac','trade_name','packaged ac','en'),
  ('hvac','trade_name','تكييف مركزي','ar'),
  ('hvac','trade_name','مكيفات مركزيه','ar'),
  ('hvac','trade_name','تبريد مركزي','ar'),
  ('hvac','trade_hint','ac','en'),
  ('hvac','trade_hint','a/c','en'),
  ('hvac','trade_hint','a\.c','en')
on conflict (kind, pattern, lang) do nothing;

comment on table public.mep_trade_pattern is
  'Deterministic surface forms, matched with word boundaries, never substring - "ac" must not fire inside "access control" or "hvac", and "fire" must not fire on "fireproofing" unless listed. Exactness decides authority: a multi-token unambiguous phrase is a trade_name and confirms; a short ambiguous abbreviation is a trade_hint and asks.';
;