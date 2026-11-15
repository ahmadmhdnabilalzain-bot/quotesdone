F1 round 4 is pushed (f8086debc on the same branch, no PR) and both blockers are fixed. The drawings branch still needs one line from its author.

- **Blocker 1 (phone in column-spaced text):** runs of 3+ blanks after text are now cut to two spaces (`capBlanks` in `identity_places.ts`, used by identity_text, reducePlaces, redactText and residualScan). A line's leading indent is kept as written. "Sales contact    050 123 4567    12,500.00" is removed again on every door, and that row is planted. Still changed where nothing is removed: a gap of 3+ blanks inside a line prints as two spaces.
- **Blocker 2 (ARJAN on a drawing):** `placeSpans(text, { drawing: true })` and `locationBelowEmirate(text, { drawing: true })` now count a cue-only name in capitals, or alone on its line, as a place. Without the option nothing changes: "Arjan model chair" passes. A test proves both.
- **The one line the drawings author must change**, in `_shared/drawing_location.ts`: call `SHARED_PLACES(t, { drawing: true })` and widen the cast to accept a second argument. With that line applied in my local three-way merge (my branch, the sibling, drawings a58c2fc45), the drawing test passes 11/11.
- **One failure in the merged tree that is not mine:** `quote_review_corpus.test.ts` fails on the drawings branch alone too ("LaserJet" leaks in office_equipment). My branch plus the sibling passes it.
- **The 80-sentence round:** all five wrong changes are fixed, "Al Wasl area rug" and "Mussafah supplier type ME-10" are kept, a removal no longer takes the following space, and "at Villa 15, Al Barsha 2, Dubai" reads "in Dubai". One judgement call: "villas no. 40 to 45 on the drawing" is now removed whole, because ruling 1683 treats villa numbers as identity.
- **Corpus (654 sentences, two name pairs measured: Falcon/Haddad and Orbit/Sara Ali):** 0 wrongly changed. The only changes are "Falcon grey" under the supplier's own name Falcon, and the villas row above.
- **Probes:** C 46 → 2, A 31 → 2 (the e-mail door, which is F2's), the reviewer's 60 → 1 (Cedre Villas), the reviewer's 40 → 1 (Khannour).
- **Timing:** the adversarial test passes in 19 s, with new inputs for a leading indent, a blank-only line and two-space columns. review_cpu_budget runs 282–342 ms.
- **Mutants:** 14 of 16 are caught, including one for each blocker. Two survive, and both are covered by other layers: M3 (the second loop already trims the lower-case lead) and N2 (the comparison PDF's last pass and the CSV fragment pass still mask that row). With the ReDoS guard reverted (N1), the test fails in 2 min 41 s instead of hanging.
- **Suites:** deno across _shared, supplier_api, messages_api, quote_extract, customer_api, drawing_boq, drawing_redact and quote_compare: 2,802 passed, 1 failed (the tesseract read permission, which fails the same way on base). The check `a_supplier_sees_only_its_own_match` passes 30/30.

**Final list for the second reader:**
- a person named without a label ("Contact Rashid Khan", "call Rashid", "ask for Rashid");
- a house brand built on the supplier's name ("Falcolux");
- initials outside the quotation number ("FT team", "UPS");
- a short name made only of common words ("Emirates Steel");
- a bank named with no bank word nearby ("transfer to Mashreq");
- sub-communities nobody listed ("Cedre Villas", "Khannour");
- a bare community name in text with no cue ("Deira", "ديرة");
- a landmark with no cue word and no listed name, and places described in prose;
- a one-word Arabic name after a label;
- a third party's firm with no legal form and no cue;
- lower-case place names typed on WhatsApp ("business bay");
- prices written in prose (F2's).