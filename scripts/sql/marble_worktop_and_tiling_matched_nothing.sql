-- "MARBLE", "WORKTOP", "TILING" AND "BATHROOM" MATCHED NOTHING IN THE ROUTING LEXICON.
--
-- MEASURED ON PRODUCTION, 14 Aug 2026, through fn_kb_route_decide — the deterministic router the
-- intake assistant uses before any model call:
--
--   "marble worktops for a villa kitchen in Dubai"
--        top_score 2, matched aliases: ["Kitchen"] only.
--        action: ask_clarifying_question, "only a weak fragment matched; not enough to act on"
--
--   "I need bathroom tiling for a villa"
--        top_score 0, candidates: [], "no deterministic alias matched the customer wording"
--        action: ask_clarifying_question, and the question asked back is the generic
--        "Could you tell me in your own words what you need supplied or done?"
--
-- kb_operational_alias holds 4,212 aliases across all 86 categories and NOT ONE of `marble`,
-- `granite`, `quartz`, `worktop`, `worktops`, `countertop`, `tiles`, `tiling` or `bathroom` is
-- among them. Of that whole sentence only the word "kitchen" resolved. These are among the most
-- ordinary things a UAE customer asks a fit-out marketplace for, and a customer who types one is
-- asked to rephrase.
--
-- WHY THE GAP EXISTS. There is no marble/stone category in the 86 — checked. So the terms have no
-- obvious single home and were never given one, while the categories that DO serve the work
-- (Flooring 18, Joinery & Carpentry 20, Kitchen & Bathroom 24) each carry 39-126 aliases about
-- their own vocabulary and none about the material a customer names.
--
-- WEIGHTS FOLLOW THE EXISTING CONVENTION: 3 for a term that identifies the category on its own,
-- 2 for a supporting term that should contribute to a score without deciding it. `marble` and
-- `granite` are deliberately weight 2 on all three categories — a material name genuinely does not
-- decide between a floor, a worktop and a vanity top, and the router's multi-category clarification
-- is the right outcome when the customer has not said which. `worktop` is 3 on Kitchen & Bathroom
-- and 2 on Joinery, because a worktop is more often bought as a kitchen than as carpentry.
--
-- alias_norm is set to the alias itself: every term added here is a single lowercase English word
-- or a two-word phrase with no punctuation, so the normalisation the existing rows use (lowercase,
-- punctuation to spaces) is the identity on all of them. Nothing is guessed about the normaliser.
--
-- ADDITIVE AND IDEMPOTENT. `where not exists` on (catalog_num, language, alias_norm) so re-running
-- changes nothing and no existing alias, weight or negative flag is touched.

insert into kb_operational_alias (catalog_num, language, alias, alias_norm, weight, negative, source)
select v.catalog_num, 'en', v.alias, v.alias, v.weight, false, 'qd_fitout_vocab_2026_08_14'
from (values
  -- 18 Flooring Suppliers
  (18,'marble',2),(18,'granite',2),(18,'quartz',2),(18,'terrazzo',2),
  (18,'tiles',3),(18,'tiling',3),(18,'tiler',2),(18,'floor tiles',3),
  (18,'porcelain tiles',3),(18,'ceramic tiles',3),(18,'vinyl flooring',3),(18,'parquet',3),
  (18,'skirting',2),(18,'screed',2),
  -- 24 Kitchen & Bathroom Suppliers
  (24,'marble',2),(24,'granite',2),(24,'quartz',2),
  (24,'worktop',3),(24,'worktops',3),(24,'countertop',3),(24,'countertops',3),
  (24,'bathroom',3),(24,'bathrooms',3),(24,'sanitaryware',3),(24,'vanity unit',3),
  (24,'shower tray',2),(24,'backsplash',2),(24,'splashback',2),(24,'kitchen cabinets',3),
  (24,'wet room',2),(24,'bathroom tiling',3),
  -- 20 Joinery & Carpentry Suppliers
  (20,'marble',2),(20,'granite',2),(20,'quartz',2),
  (20,'worktop',2),(20,'worktops',2),(20,'countertop',2),(20,'countertops',2),
  (20,'wardrobe',3),(20,'wardrobes',3),(20,'built in wardrobe',3),(20,'millwork',3),
  (20,'veneer',2),(20,'laminate',2)
) as v(catalog_num, alias, weight)
where not exists (
  select 1 from kb_operational_alias a
   where a.catalog_num = v.catalog_num and a.language = 'en' and a.alias_norm = v.alias);
