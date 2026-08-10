-- THE EMBEDDING DECISION, AND WHY IT IS NOT THE SPEND DECISION THE BRIEF DESCRIBES.
--
-- The brief frames embedding 115,148 pack records as a money call on a two-day OpenRouter
-- balance. Measured: kb_embed does not touch OpenRouter. Its first line says so —
-- "populate kb_chunks.embedding_gte via the free in-region gte-small" — and the code builds a
-- Supabase.ai.Session('gte-small') that runs inside the edge worker. Embedding the whole corpus
-- costs nothing beyond compute already paid for.
--
-- So the decision is NOT what to embed. It is throughput, and the number is arithmetic:
--   kb_embed_backfill fires once a minute at a batch of 5 (the function hard-caps at 8 because
--   the gte-small session grows its allocation with each run() inside one invocation — that is
--   the WORKER_RESOURCE_LIMIT fix of 28 Jul, and it must not be undone).
--   Measured rate today: 180 -> 460 pack rows in ~50 minutes = 5.6/min.
--   114,698 unembedded / 5 per minute = about SIXTEEN DAYS.
--
-- The lever is more INVOCATIONS, not a bigger batch: each invocation is a fresh worker with its
-- own session, which is exactly what the resource limit is about. Six posts a minute at the
-- function's own cap of 8 gives ~48/min, and the corpus completes in roughly two days instead of
-- sixteen. Two invocations can pick the same rows — the query takes `embedding_gte is null` with
-- no lock — so a little work is repeated; the update is idempotent and re-embedding a row costs
-- nothing, which is cheaper than adding a claim table for a backfill that ends in two days.
-- ponytail: no row-claiming, delete this job when remaining hits 0.
--
-- Until it completes, kb_search still answers: the corpus is 115,148 of 115,148 with a full-text
-- vector (fn_kb_corpus_integrity asserts it), and full text is the path kb_search falls back to.
-- Recall of vector against FTS is deliberately NOT claimed here — comparing them at 0.4% embedded
-- would measure the backfill, not the retrieval.
select cron.schedule('kb_embed_backfill_boost', '* * * * *', $job$
  select net.http_post(
    url := 'https://__PROJECT_REF__.supabase.co/functions/v1/kb_embed',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_knowledge'),
                               'limit', 8))
  from generate_series(1, 6);
$job$);
