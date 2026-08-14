-- THE FOUNDER-APPROVED ANSWERS WENT TO THE BACK OF A 26,000-ROW QUEUE.
--
-- a_198k_faq_in_a_prompt_slot_that_holds_24k.sql split the Company FAQ into 484 retrievable
-- kb_chunks. All 484 carry `fts`, so kb_search's full-text half reaches them immediately — measured,
-- 13 of them match a plain query for "reveal fee supplier pay". None carries an embedding yet.
--
-- kb_embed_priority_kinds runs every minute and names its queue explicitly:
--
--     'source_kinds', jsonb_build_array('trade','regulation','material')
--
-- 'company_faq' is not in it, so the 484 canonical answers fall to the general backfill behind
-- 26,466 other unembedded rows. The retrieval agent_brain runs on every turn is hybrid — kb_match
-- (vector) and full-text, fused with RRF — so an unembedded chunk competes on keywords alone
-- against 96,974 chunks of which 72.8% have a vector. It is reachable, and it is outranked.
--
-- These are the answers the FAQ itself says "every agent must use verbatim-in-spirit
-- (founder-approved) … Do not contradict it or invent beyond it." If any source_kind belongs in the
-- priority queue, it is this one.
--
-- SHAPE UNCHANGED, ONE ELEMENT ADDED. limit stays 5 and the fan-out stays generate_series(1, 6):
-- kb_embed returns HTTP 546 above a batch of 5, so throughput is bought with INVOCATIONS, never with
-- batch size. 484 rows at 30 embeddings a minute is about sixteen minutes, shared with the three
-- kinds already queued. Embedding is the in-region gte-small model and is free — this costs nothing
-- but the order it happens in.

select cron.unschedule('kb_embed_priority_kinds');

select cron.schedule('kb_embed_priority_kinds', '* * * * *', $job$
  select net.http_post(
    url := 'https://' || (select value from app_secrets where key = 'project_ref')
           || '.supabase.co/functions/v1/kb_embed',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_knowledge'),
                               'limit', 5,
                               'source_kinds', jsonb_build_array('company_faq','trade','regulation','material')))
  from generate_series(1, 6);
$job$);
