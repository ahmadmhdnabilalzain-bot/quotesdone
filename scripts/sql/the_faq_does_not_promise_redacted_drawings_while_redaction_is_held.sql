-- THE FAQ DOES NOT PROMISE REDACTED DRAWINGS WHILE REDACTION IS HELD — customer_support, 23 Sep 2026.
-- Independent content review of PR #870. Four approved public FAQ answers (16, 20, 116, 126) and one
-- internal one (289) said drawings are automatically redacted before suppliers see them. Drawing
-- redaction needs the model behind drawing_redact, which is held; a page not confirmed clean is not
-- shared at all. The same answers on /faq (src/content/marketing.json) were corrected in the same PR,
-- and scripts/checks/site_copy_claims_only_what_matching_and_redaction_do.test.mjs keeps the site copy
-- honest. Each update is guarded on the old text, so a re-run changes nothing.

update public.company_faq
   set answer = replace(answer, 'Uploaded drawings are automatically redacted to remove identifying details.',
         'A drawing is shared with suppliers only once it is confirmed free of your details; until then they quote on the scope and quantities.'),
       updated_at = now()
 where id = 16 and answer like '%Uploaded drawings are automatically redacted%';

update public.company_faq
   set answer = replace(answer, 'Drawings are automatically redacted to strip any identifying details before suppliers see them.',
         'A drawing is shared with suppliers only once it is confirmed free of your details; until then they quote on the scope and quantities.'),
       updated_at = now()
 where id = 20 and answer like '%Drawings are automatically redacted%';

update public.company_faq
   set answer = replace(answer, 'and customer drawings are automatically redacted to remove identifying details before any supplier sees them.',
         'and a customer drawing is shared with suppliers only once it is confirmed free of identifying details.'),
       updated_at = now()
 where id = 116 and answer like '%customer drawings are automatically redacted%';

update public.company_faq
   set answer = replace(answer, 'and it automatically redacts identifying details before any supplier sees it — keeping you anonymous.',
         'and a drawing reaches suppliers only once it is confirmed free of your details — keeping you anonymous.'),
       updated_at = now()
 where id = 126 and answer like '%automatically redacts identifying details%';

update public.company_faq
   set answer = 'Drawings live in a private store. They can be converted (CAD/large formats normalised) and read to extract a structured bill of quantities. A drawing is shared with suppliers only once its pages are confirmed free of the customer''s identifying details; a page not confirmed clean is not shared, and suppliers then quote on the scope and quantities. Very large drawings upload directly to storage and are linked, and suppliers reach any shared page only through a signed link.',
       updated_at = now()
 where id = 289 and answer like '%Suppliers only ever see the redacted%';
