-- NO MARKETING OR AI-VISIBILITY TEXT NAMES A SUPPLIER (30 Sep 2026). Seat: marketing.
--
-- Founder ruling 1020: never name suppliers in marketing or AI-visibility content. MEASURED (ledger reconciliation,
-- 30 Sep 2026): the only enforcement was the CEO seat's review criterion no_supplier_named, and only for blog articles
-- (marketing_articles.ts). A social post, its per-platform variant, a comment or DM reply, a reply-library answer or a
-- legacy social post had no guard at all; and the blog guard was a model's judgement, not a rule.
--
-- THE GUARD. One routine, fn_supplier_named_in(text), returns the first supplier the text names; a trigger on every
-- table that holds text the company publishes refuses the write when it names one:
--   blog_posts (title, excerpt, meta_desc, body_html)                       - the blog and its AI-answer pages
--   marketing_article (titles, excerpts, meta descriptions, bodies, en+ar)  - the CEO-reviewed market articles
--   marketing_post (title, text_en, text_ar)                               - the month's social posts
--   marketing_post_variant (title, caption, body, first_comment, alt_text) - each platform's copy
--   social_message, direction 'out', author 'seat' (body)                  - the seat's comment and DM replies
--     (a reply a PERSON already sent from the Meta inbox is recorded as it was sent: the record is kept whole)
--   social_reply_library (reply_en, reply_ar)                              - the standard replies
--   social_posts (content)                                                 - the legacy post queue
-- There is no newsletter table and no stored GEO answer text on production (marketing_geo_check holds what an
-- engine said about us, which we do not publish), so nothing else is written that the public reads.
--
-- WHAT COUNTS AS NAMING A SUPPLIER. A company in public.leads (registered, invited or only on file) whose name
-- carries a company form - LLC, FZE, FZCO, Est., Trading, Contracting, Co., Company, Group, Ltd, Industries, Factory,
-- Enterprises - and is at least 10 characters, appearing whole in the text as a run of its words, case- and punctuation-insensitive. 12,452
-- names on 30 Sep 2026. Measured against every blog post, article, post and variant on file: 0 hits. The bare
-- names without the company form were measured too and are unusable: leads holds names such as "Landscaping",
-- "Specialist" and "The Home", which matched 31 existing texts - a rule that refuses the word "landscaping" is not
-- this ruling. A name made only of company forms and generic words ("General Trading LLC") is not a name either.
-- ponytail: a name written without its company form ("Acme" for "Acme Trading LLC") is not caught;
-- catching it needs a curated distinctive-name list per supplier, which does not exist yet.
--
-- prevented by: scripts/checks/no_marketing_or_ai_visibility_text_names_a_supplier.test.mjs

create or replace function public.fn_supplier_named_in(p_text text)
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  -- A NAME LOOKUP, not a scan. The text and every name are cut into the same words (letters, digits, '.', '&', '-';
  -- trailing full stops dropped, so "LLC." at a sentence end is "llc"), the text's runs of 1 to 12 words are formed,
  -- and a name is named when one run EQUALS it - a hash join. A substring scan of every name over every text (tried
  -- first) timed out on 30 Sep 2026: 20k names x a 10 KB article is 200 MB of scanning per write.
  with w as (
    select array_agg(regexp_replace(tok, '\.+$', '') order by ord) a
      from regexp_split_to_table(lower(coalesce(p_text, '')), '[^[:alnum:].&-]+') with ordinality s(tok, ord)
     where regexp_replace(tok, '\.+$', '') <> ''),
  g as (
    select distinct array_to_string(w.a[i:i + n - 1], ' ') run
      from w, generate_series(1, coalesce(cardinality(w.a), 0)) i, generate_series(1, 12) n
     where i + n - 1 <= cardinality(w.a)),
  names as (
    select l.company_name,
           (select string_agg(regexp_replace(tok, '\.+$', ''), ' ' order by ord)
              from regexp_split_to_table(lower(l.company_name), '[^[:alnum:].&-]+') with ordinality s(tok, ord)
             where regexp_replace(tok, '\.+$', '') <> '') norm
      from public.leads l
     where length(l.company_name) >= 10
       and l.company_name ~* '\m(llc|l\.l\.c|fze|fzco|fzc|fz-llc|est|establishment|trading|contracting|contractors|co|company|group|ltd|limited|industries|factory|enterprises)\M')
  -- a name made only of company forms and generic words ("General Trading LLC", "Building Materials Trading") names
  -- nobody: without this, "a general trading licence" in an article would be refused (code review of #1164)
  select names.company_name from names join g on g.run = names.norm
   where regexp_replace(names.norm, '\m(llc|l\.l\.c|fze|fzco|fzc|fz-llc|est|establishment|trading|contracting|contractors|co|company|group|ltd|limited|industries|factory|enterprises|general|building|materials|technical|services|service|maintenance|works|and|the|of|for|uae|dubai|abu|dhabi|sharjah|ajman|international|global|middle|east)\M', '', 'g') ~ '[[:alpha:]]{3,}'
   limit 1
$fn$;
revoke execute on function public.fn_supplier_named_in(text) from public, anon, authenticated;
grant execute on function public.fn_supplier_named_in(text) to service_role;

create or replace function public.trg_published_text_names_no_supplier()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_text text; v_name text;
begin
  if tg_table_name = 'social_message' then   -- nested: new.direction exists only on social_message
    if new.direction is distinct from 'out' or new.author is distinct from 'seat' then
      return new;   -- what a person wrote, to us or from our inbox, is recorded as written; the seat's replies are guarded
    end if;
  end if;
  -- one IF per table: PL/pgSQL plans each statement when it runs, so a column another table lacks is never read
  if    tg_table_name = 'blog_posts'             then v_text := concat_ws(' ', new.title, new.excerpt, new.meta_desc, new.body_html);
  elsif tg_table_name = 'marketing_article'      then v_text := concat_ws(' ', new.title_en, new.title_ar, new.excerpt_en, new.excerpt_ar,
                                                                           new.meta_desc_en, new.meta_desc_ar, new.body_html_en, new.body_html_ar);
  elsif tg_table_name = 'marketing_post'         then v_text := concat_ws(' ', new.title, new.text_en, new.text_ar);
  elsif tg_table_name = 'marketing_post_variant' then v_text := concat_ws(' ', new.title, new.caption, new.body, new.first_comment, new.alt_text);
  elsif tg_table_name = 'social_message'         then v_text := new.body;
  elsif tg_table_name = 'social_reply_library'   then v_text := concat_ws(' ', new.reply_en, new.reply_ar);
  elsif tg_table_name = 'social_posts'           then v_text := new.content::text;
  end if;
  v_name := public.fn_supplier_named_in(v_text);
  if v_name is not null then
    raise exception '%: this text names the supplier "%"; marketing and AI-visibility content never names a supplier (ruling 1020)',
      tg_table_name, v_name using errcode = 'P0001';
  end if;
  return new;
end
$fn$;
revoke execute on function public.trg_published_text_names_no_supplier() from public, anon, authenticated;

drop trigger if exists a06_names_no_supplier on public.blog_posts;
create trigger a06_names_no_supplier before insert or update of title, excerpt, meta_desc, body_html on public.blog_posts
  for each row execute function public.trg_published_text_names_no_supplier();
drop trigger if exists a06_names_no_supplier on public.marketing_article;
create trigger a06_names_no_supplier before insert or update of title_en, title_ar, excerpt_en, excerpt_ar, meta_desc_en, meta_desc_ar, body_html_en, body_html_ar on public.marketing_article
  for each row execute function public.trg_published_text_names_no_supplier();
drop trigger if exists a06_names_no_supplier on public.marketing_post;
create trigger a06_names_no_supplier before insert or update of title, text_en, text_ar on public.marketing_post
  for each row execute function public.trg_published_text_names_no_supplier();
drop trigger if exists a06_names_no_supplier on public.marketing_post_variant;
create trigger a06_names_no_supplier before insert or update of title, caption, body, first_comment, alt_text on public.marketing_post_variant
  for each row execute function public.trg_published_text_names_no_supplier();
drop trigger if exists a06_names_no_supplier on public.social_message;
create trigger a06_names_no_supplier before insert or update of body, direction, author on public.social_message
  for each row execute function public.trg_published_text_names_no_supplier();
drop trigger if exists a06_names_no_supplier on public.social_reply_library;
create trigger a06_names_no_supplier before insert or update of reply_en, reply_ar on public.social_reply_library
  for each row execute function public.trg_published_text_names_no_supplier();
drop trigger if exists a06_names_no_supplier on public.social_posts;
create trigger a06_names_no_supplier before insert or update of content on public.social_posts
  for each row execute function public.trg_published_text_names_no_supplier();

-- No verdict scan here: fn_supplier_named_in over every published text took about 50 s in one statement (the names
-- are folded per call), and a long apply holds its locks. The same measurement was run before this file: 0 of the
-- blog posts, articles, posts and variants on file name a supplier (30 Sep 2026).
