-- THE FAQ SAYS A DRAWING IS SHARED ONLY ONCE ITS DETAILS ARE COVERED — customer_support, 23 Sep 2026.
-- Supersedes the wording of the_faq_does_not_promise_redacted_drawings_while_redaction_is_held.sql
-- (same PR, #872). Its independent review found "confirmed free of your details" overclaimed: no
-- model verifies a page. What runs: for a PDF with a text layer customer_api boxes the title block and
-- the customer's name, email and phone from the file's own text, and drawing_redact paints those boxes
-- with no model; a drawing it cannot cover (photo, scan, raster CAD) is not shared. Guarded on the
-- previous text, so a re-run changes nothing.

update public.company_faq
   set answer = replace(answer, 'A drawing is shared with suppliers only once it is confirmed free of your details; until then they quote on the scope and quantities.',
         'A drawing is shared with suppliers only after your details on it are covered (the title block, your name, phone and email). A drawing we cannot cover is not shared, and suppliers then quote on the scope and quantities.'),
       updated_at = now()
 where id in (16, 20) and answer like '%confirmed free of your details%';

update public.company_faq
   set answer = replace(answer, 'and a customer drawing is shared with suppliers only once it is confirmed free of identifying details.',
         'and a customer drawing is shared with suppliers only after the identifying details on it are covered; a drawing that cannot be covered is not shared.'),
       updated_at = now()
 where id = 116 and answer like '%confirmed free of identifying details%';

update public.company_faq
   set answer = replace(answer, 'and a drawing reaches suppliers only once it is confirmed free of your details — keeping you anonymous.',
         'and a drawing reaches suppliers only after your details on it are covered (the title block, your name, phone and email) — keeping you anonymous. A drawing we cannot cover is not shared.'),
       updated_at = now()
 where id = 126 and answer like '%confirmed free of your details%';

update public.company_faq
   set answer = 'Drawings live in a private store. They can be converted (CAD/large formats normalised) and read to extract a structured bill of quantities. For a PDF with a text layer the server covers the title block and the customer''s name, email and phone from the file''s own text before a page is shared; a drawing it cannot cover (a photo, scan or raster CAD) is not shared, and suppliers then quote on the scope and quantities. Very large drawings upload directly to storage and are linked, and suppliers reach any shared page only through a signed link.',
       updated_at = now()
 where id = 289 and answer like '%confirmed free of the customer%';
