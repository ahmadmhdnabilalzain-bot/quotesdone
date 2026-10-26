-- spec_backlog#205: the closing note of the 4 Aug session reported "37 confirmed_covered ... 47 still
-- requires_review". Measured against kb_operational_route on 4 Aug 14:43 UTC the live counts are
-- 35 / 2 / 49. The 37 was arithmetic, not a query: the same note says 41 routes were researched and
-- 4 were held back, and 41 - 4 held - 2 confirmed_none = 35, not 37. The two extra were counted as
-- covered and held back at the same time.
--
-- Recorded here rather than silently overwritten, because the overstated number was carried into the
-- session handoff and would have been carried forward again.
update public.spec_backlog
   set notes = notes || E'\n\nCORRECTION 4 Aug 2026 (later session): the progress note above says '
             || '"37 now confirmed_covered ... REMAINING: 47 routes still requires_review". '
             || 'Measured live at 14:43 UTC: confirmed_covered 35, confirmed_none 2, requires_review 49 '
             || '(86 total). 41 researched minus 4 held back (23, 46, 48, 55) minus 2 confirmed_none = 35. '
             || 'The two held-back routes 23 and 46 were counted both as covered and as held. '
             || 'The five routes this ticket originally named - 38, 39, 41, 61, 62 - are all '
             || 'confirmed_covered as of today, so the ticket AS ORIGINALLY SCOPED is satisfied; it stays '
             || 'open only for the rescoped remainder of 49 requires_review routes.',
       updated_at = now()
 where id = 205;;
