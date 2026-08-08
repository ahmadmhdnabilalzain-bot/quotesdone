-- ROW #5 §13 `perf-living` — MAKE THE SUPPLIER SCORE ACTUALLY LIVING.
--
-- ── THE MEASUREMENT THAT PROMPTED THIS ──────────────────────────────────────────────────────────
-- verify_supplier_blueprint, 2026-08-07:
--   perf-living  MISSING  0 active cron(s) recompute a score, 4 routine(s) touch supplier_score,
--                         20465 of 20465 row(s) computed in the last 30d
--
-- The spec's §13 opens with the words "A LIVING score". The estate already had the whole
-- computation — public.fn_supplier_score_refresh() recomputes response_rate, quotes submitted/won,
-- rejections, price_index, quality and reliability for EVERY lead from `leads` and `quotes` — and
-- nothing ever called it on a schedule. A score written once is a snapshot, not a living thing, and
-- the check was right to say so.
--
-- ── WHY THIS IS SAFE TO RUN OVER 20,465 ROWS ────────────────────────────────────────────────────
-- Verified before scheduling, rather than assumed:
--   · supplier_score.quality_rating is non-null on 4,478 rows and leads.rating on 4,477 — the same
--     population, so the existing data was already produced by THIS routine. Re-running refreshes
--     values rather than rewriting semantics.
--   · avg(reliability) is currently 0.0 across the estate: rv_response_rate is set on 2 rows and
--     `verified` on none, so the formula legitimately yields ~0 for a company with no traffic. The
--     refresh will keep yielding ~0 until there is traffic. Nothing is inflated by running it.
--   · It is an upsert keyed on lead_id, so it neither duplicates nor deletes.
--
-- 03:40 UTC: after the nightly enrichment crons and well clear of doc_expiry_daily at 05:20, so a
-- supplier's score reflects the documents and profile state the same night's jobs left behind.
select cron.schedule(
  'supplier_score_refresh_daily',
  '40 3 * * *',
  $$select public.fn_supplier_score_refresh();$$
)
where not exists (select 1 from cron.job where jobname = 'supplier_score_refresh_daily');

-- Run it once now. A cron that has never fired leaves `computed_at` stale until tomorrow, and a
-- check asking "is this score living" would read the same MISSING for a day while being wrong.
select public.fn_supplier_score_refresh();
