-- THE FIVE CORPORATE-KIT CHUNKS IN kb_chunks GIVE THE PUBLIC NUMBERS AND NEVER THE FOUNDER'S MOBILE.
--
-- Agent: ceo. 2 Nov 2026. Ruling ledger 1482: public calling +971 56 791 8605, WhatsApp +1 218 316 6814; the founder's personal mobile is
-- shown to nobody by the live system. Companion of the_live_system_gives_out_the_public_numbers_and_never_the_founders_mobile.sql.
--
-- MEASURED (read only, 2 Nov 2026): kb_chunks is 54,360 rows, 77 MB heap + 141 MB TOAST (not the 8 GB it once was), with no trigram index
-- on content (only a GIN on the generated tsvector, which tokenises a phone number into digit groups and cannot find one). It was read in
-- ELEVEN id-range batches of at most 5,000 rows (ids 3557 to 3,070,421), statement_timeout 15 s, one call per batch, searching
-- (50[ .-]?931[ .-]?9355|509319355|Arabic-Indic 50 931) in content and title. Ten batches found nothing; batch 1 (ids 3557-177586) found
-- exactly FIVE chunks, all source_kind 'trade', category _global, the "Asset text: ..." copies of the corporate-kit files (brand quick
-- reference, README, letterhead, brand details, email signature). They are retrievable by every assistant, so a visitor could be quoted
-- the mobile. Every other store with the number was checked the same day (see the companion file).
--
-- WHAT THIS CHANGES: the contact sentence in those five chunks only. Each update is guarded by the md5 of the row as read, so a row edited
-- since is left alone, and sets embedding_gte = null so the LIVE embedding pipeline re-embeds ONLY these five. That pipeline exists and runs:
-- pg_cron job 580 kb_embed_daily (02:20 UTC, active, succeeded on each of the last five days) calls fn_kb_embed_scheduled_run ->
-- fn_kb_embed_tick = fn_kb_embed_harvest (writes the vectors of the previous tick's requests) then fn_kb_embed_dispatch, which picks
-- kb_chunks WHERE embedding_gte IS NULL and posts left(title + newline + content, 1200) to ai_gateway {action:'embed'} (gte-small, mean-pooled,
-- normalised, 384-d: the window every existing vector was built from). This file also calls fn_kb_embed_dispatch once, so the five requests
-- leave at commit instead of waiting for 02:20; the harvest then writes them (next tick, or run select public.fn_kb_embed_harvest() a
-- minute after the apply). Until it does, the chunks stay findable by full text (the generated fts column follows the new text by itself).
-- READ-BACK after the harvest: select id, vector_dims(embedding_gte) from public.kb_chunks where id in (177478,177480,177482,177483,177484)
-- expects five rows of 384. trg zz_knowledge_library_mirror carries the change to knowledge_library.
-- The same wording is in supabase/seeds/agent_knowledge.seed.sql and ai-organization/org-as-code/agent_knowledge.json (already changed).
-- No begin/commit: the applier runs the file as one transaction. Ends with a verdict row (PROBE OK or PROBE FAILED).
--   node scripts/apply_sql.mjs scripts/sql/the_corporate_kit_chunks_give_the_public_numbers_and_never_the_founders_mobile.sql --apply --seat ceo

update public.kb_chunks set embedding_gte = null,
  content = replace(content, 'Mobile/WhatsApp: +971 50 931 9355', 'Phone: +971 56 791 8605  ·  WhatsApp: +1 218 316 6814')
 where id = 177478 and md5(content) = 'af61aea7a07a2a065678b23a6f990e8b';

update public.kb_chunks set embedding_gte = null,
  content = replace(content, 'management@quotesdone.com · +971 50 931 9355', 'management@quotesdone.com · +971 56 791 8605 · WhatsApp +1 218 316 6814')
 where id = 177480 and md5(content) = '9811a853c885d264b51a0a747e7e4c7d';

update public.kb_chunks set embedding_gte = null,
  content = replace(content, 'management@quotesdone.com · +971 50 931 9355', 'management@quotesdone.com · +971 56 791 8605 · WhatsApp +1 218 316 6814')
 where id = 177482 and md5(content) = 'ccf4ea982414a85cde7481898dde07a4';

update public.kb_chunks set embedding_gte = null,
  content = replace(content, 'Mobile/WA  : +971 50 931 9355', E'Phone      : +971 56 791 8605\n  WhatsApp   : +1 218 316 6814')
 where id = 177483 and md5(content) = '9e4c07048b508443b7b5bd51f38136d0';

update public.kb_chunks set embedding_gte = null,
  content = replace(content, '<a href="tel:+971509319355" style="color:#475569;text-decoration:none">+971 50 931 9355</a>', '<a href="tel:+971567918605" style="color:#475569;text-decoration:none">+971 56 791 8605</a>')
 where id = 177484 and md5(content) = '2ab3f06ca52d7d216cc0b9659e1f760d';

-- fire the five embed requests now (pg_net sends them at commit); nothing else is nulled, so the batch is these five
do $e$ begin perform public.fn_kb_embed_dispatch(20, 4); end $e$;

-- verdict
select case when
       (select count(*) from public.kb_chunks where id in (177478, 177480, 177482, 177483, 177484)
          and content !~ '(50[ .-]?931[ .-]?9355|509319355)' and content like '%+971 56 791 8605%'
          and md5(content) not in ('af61aea7a07a2a065678b23a6f990e8b', '9811a853c885d264b51a0a747e7e4c7d', 'ccf4ea982414a85cde7481898dde07a4', '9e4c07048b508443b7b5bd51f38136d0', '2ab3f06ca52d7d216cc0b9659e1f760d')) = 5
   and (select count(*) from public.kb_chunks where id in (177478, 177480, 177482, 177483, 177484) and (embedding_gte is null or vector_dims(embedding_gte) = 384)) = 5
  then 'PROBE OK' else 'PROBE FAILED: a corporate-kit chunk still carries the founder''s mobile, was edited since it was read, or lacks the public calling number' end as verdict;
