-- One canonical normalised text per lead. Everything that classifies a lead reads THIS, so a pattern
-- authored against it behaves identically at test time and at run time.
-- Notes on the normalisation, each earned from the actual data:
--   * the scrape stored HTML entities, so "&#038;" and "&amp;" become " and " before anything else;
--   * for ~5,144 leads the categories/services/capability_summary columns are literally the company
--     name echoed back, so company_name has to be part of the haystack or those leads have no signal;
--   * the string is space-padded at both ends so a pattern can be matched as ' word ' and never fire
--     on a substring (otherwise 'ac' hits 'placard' and 'it' hits 'furniture').
create or replace view v_lead_text as
select l.id,
       ' ' || regexp_replace(
                regexp_replace(
                  lower(regexp_replace(
                    concat_ws(' ',
                      l.sector, l.sub_type, l.categories, l.services, l.products,
                      l.description, l.company_name, l.capability_summary),
                    '&#0?38;|&amp;', ' and ', 'g')),
                  '[^a-z0-9]+', ' ', 'g'),
                '\s+', ' ', 'g') || ' ' as hay
from leads l;

revoke all on v_lead_text from anon, authenticated;