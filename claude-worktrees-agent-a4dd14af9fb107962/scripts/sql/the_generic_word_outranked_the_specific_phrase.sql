-- THE GENERIC WORD OUTRANKED THE SPECIFIC PHRASE, SO TWO ARABIC REQUESTS COULD NOT BE ROUTED.
--
-- fn_kb_route_test_run has been reporting 342 of 344 for some time. The two failures are both
-- Arabic, both on the revenue path, and both are the same defect:
--
--   ar-017  "أحتاج أسقف مستعارة في دبي"   (I need FALSE CEILINGS in Dubai)
--           expected route_or_ask_scope_details, got ask_clarifying_question
--           candidates: Gypsum & False Ceiling Suppliers | Roofing Suppliers
--
--   ar-009  "أحتاج نظام تكييف في دبي"      (I need an AIR CONDITIONING SYSTEM in Dubai)
--           expected route_or_ask_scope_details, got ask_clarifying_question
--           candidates: MEP Suppliers / Electromechanical | HVAC Suppliers
--
-- MEASURED CAUSE, exactly:
--
--   أسقف           (roofs/ceilings)      -> Roofing (7)                  weight 3
--   أسقف مستعارة   (FALSE ceilings)      -> Gypsum & False Ceiling (17)  weight 2
--
-- The one-word generic outranks the two-word phrase that disambiguates it. "مستعارة" is precisely
-- the word that makes it an interior ceiling and not a roof, and carrying it earned the customer a
-- LOWER score than leaving it out.
--
--   تكييف / نظام تكييف / تشيلر / air conditioning
--        -> HVAC Suppliers (9)                          weight 3
--        -> MEP Suppliers / Electromechanical (8)       weight 3   <-- also 3
--
-- A dead tie by construction, so the router can never choose, and correctly asks. But the tie is
-- wrong: the convention in this table is that weight 3 means the term IDENTIFIES THE CATEGORY ON
-- ITS OWN. "air conditioning" identifies HVAC on its own. It does not identify MEP on its own —
-- MEP is the umbrella that also covers electrical, plumbing and fire, and a customer who says
-- "تكييف" has named the specific trade, not the umbrella.
--
-- THE CLASS, NOT THE TWO ROWS. Querying every alias_norm held at weight 3 on more than one
-- category returns a short list, and it is the same shape each time — a specific trade term that
-- is also weight 3 on the broader category that contains it:
--
--   air conditioning / تكييف / تشيلر            HVAC          vs  MEP
--   gypsum boards partitions drywall            Gypsum & FC   vs  Fit-Out
--   متطلبات gypsum boards (+ …drywall variant)  Gypsum & FC   vs  Fit-Out
--   soft fm cleaning janitorial waste           Cleaning      vs  Facilities Management
--
-- Each umbrella drops to 2. The term still contributes to the umbrella's score — a customer asking
-- for a full MEP package that mentions air conditioning still scores MEP — it simply no longer
-- claims to identify it outright, which is what weight 3 asserts.
--
-- DELIBERATELY LEFT ALONE: `متطلبات corporate` ("corporate requirements") is weight 3 on both
-- Catering and Law Firms. That is genuinely generic on both and neither is an umbrella for the
-- other, so there is no principled winner and a clarifying question is the right outcome. Changing
-- it would be inventing a preference.
--
-- NOTHING IS DELETED and no alias is removed from any category. Only four weights move down and
-- one moves up.

-- MATCH ON `alias`, NOT `alias_norm`, FOR THE ARABIC ROWS. First attempt targeted alias_norm with
-- the literal Arabic and updated ZERO rows in silence: the normaliser strips the hamza and folds
-- ta-marbuta, so `أسقف` is stored as `اسقف` and `أسقف مستعارة` as `اسقف مستعاره`. The raw `alias`
-- column keeps the customer-facing spelling and is what was measured, so it is what is matched.
-- Every statement below is verified by re-running fn_kb_route_test_run, not by assuming it applied.

-- 1. The specific phrase earns the rank its precision deserves.
update kb_operational_alias
   set weight = 3
 where catalog_num = 17 and language = 'ar' and alias = 'أسقف مستعارة' and weight < 3;

-- 2. Umbrella categories stop claiming to be identified by a specific trade's own vocabulary.
update kb_operational_alias
   set weight = 2
 where weight = 3
   and (   (catalog_num = 8  and alias_norm in ('تكييف','نظام تكييف','تشيلر','air conditioning','chiller'))
        or (catalog_num = 16 and alias_norm like '%gypsum boards%') );

-- 3. AND THE WORD THAT IS BOTH. Re-measured after steps 1 and 2: ar-009 passes, ar-017 still
-- asks, because `أسقف` is a SUBSTRING of `أسقف مستعارة` — writing the disambiguating phrase scores
-- Roofing a full 3 as well, leaving Gypsum 4 against Roofing 3 and a confidence of 0.571, under
-- the routing threshold.
--
-- The data is what is wrong, not the router. `أسقف` is ceilings OR roofs in Arabic and is used for
-- both; by this table's own convention it does not identify Roofing ON ITS OWN and so is not a 3.
-- Roofing keeps `نظام سقف` ("roof system") at weight 3 as its identifying term, which is the more
-- precise phrase anyway, plus `تسقيف` and nine other roofing-specific aliases at 2. No Arabic route
-- test targets Roofing, so nothing is being tuned to a test.

update kb_operational_alias
   set weight = 2
 where catalog_num = 7 and language = 'ar' and alias = 'أسقف' and weight = 3;

-- Facilities Management by NAME, not by a guessed number. 8 and 16 above are read off the measured
-- collision list; this one was not, so it is resolved rather than assumed.
update kb_operational_alias a
   set weight = 2
  from catalog_supplier_categories c
 where c.num = a.catalog_num
   and c.name ilike 'Facilities Management%'
   and a.weight = 3
   and a.alias_norm = 'soft fm cleaning janitorial waste';
