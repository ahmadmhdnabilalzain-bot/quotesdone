-- ROW #4 (customer portal) — spec §15. The HOUSE negotiation policy, one row.
--
-- WHY ONE ROW AND NOT 20,464. supplier_negotiation_policy was keyed by supplier_id, so the only
-- expressible policy was per-supplier: writing one for every lead would have been 20,464 rows of
-- invented judgement about suppliers nobody has traded with, to turn a "0 rows" check green. That
-- is the fabrication this project forbids. row4_intelligence_ddl.sql re-keys the table on `scope`,
-- and this seeds the single row that is genuinely knowable today: the house rule.
--
-- THE BOUNDS, AND WHY EACH ONE IS WHAT IT IS.
--   min_sample = 4                      — fn_price_confidence already refuses to emit a confidence
--                                         below 4 comparable quotes; the policy refuses to emit a
--                                         PRICE on the same evidence bar, so the assistant can never
--                                         quote a "market average" derived from one submission.
--   suspiciously_high → ask 15, cap 25  — above p75 + 1.5·IQR the quote is an outlier and worth a
--                                         hard ask. The cap is 25 because past that, in UAE trade
--                                         contracting, you lose the supplier rather than the price.
--   within_range      → ask 8,  cap 15  — outside the interquartile band but not an outlier.
--   fair              → ask 3,  cap 7   — inside the interquartile band. A courtesy trim; the real
--                                         gains here are payment terms and lead time, not price.
--   suspiciously_low  → ask 0           — below p25 − 1.5·IQR. Do NOT push. An underbid becomes a
--                                         variation claim later; the action is to verify scope.
--   never_target_below_pct_of_median=80 — a target more than 20% under the category median is a
--                                         scope gap, not a saving, so the target price is floored.
--   walk_away_above_pct_of_median=160   — above 1.6× median, re-tender instead of negotiating.
--
-- Applied to STAGING by scripts/apply_sql.mjs, then carried to production by
-- scripts/promote_rows_to_production.mjs supplier_negotiation_policy scope default — which reads
-- the verified row back out of staging rather than retyping this literal.

insert into public.supplier_negotiation_policy (scope, supplier_id, policy, approved_by, approved_at, updated_at)
values (
  'default',
  null,
  jsonb_build_object(
    'version', 1,
    'label', 'QuotesDone house negotiation policy',
    'min_sample', 4,
    'tone', 'firm_polite',
    'never_target_below_pct_of_median', 80,
    'walk_away_above_pct_of_median', 160,
    'bands', jsonb_build_object(
      'suspiciously_high', jsonb_build_object(
        'action', 'negotiate_hard', 'ask_discount_pct', 15, 'max_ask_discount_pct', 25,
        'note', 'Above p75 + 1.5 IQR. Outlier pricing: ask hard, but never past 25% or the supplier walks.'),
      'within_range', jsonb_build_object(
        'action', 'negotiate', 'ask_discount_pct', 8, 'max_ask_discount_pct', 15,
        'note', 'Outside the interquartile band but not an outlier. A straight price ask is reasonable.'),
      'fair', jsonb_build_object(
        'action', 'trim_or_accept', 'ask_discount_pct', 3, 'max_ask_discount_pct', 7,
        'note', 'Inside the interquartile band. Push terms and lead time before price.'),
      'suspiciously_low', jsonb_build_object(
        'action', 'verify_scope', 'ask_discount_pct', 0, 'max_ask_discount_pct', 0,
        'note', 'Below p25 - 1.5 IQR. Do not push price. Confirm inclusions, exclusions and warranty first.'),
      'insufficient_data', jsonb_build_object(
        'action', 'no_benchmark_yet', 'ask_discount_pct', 0, 'max_ask_discount_pct', 0,
        'note', 'Fewer comparable quotes than min_sample. Ask for scope and terms in writing; quote no market figure.'))
  ),
  'founder',
  now(),
  now()
)
on conflict (scope) do update
  set supplier_id = excluded.supplier_id,
      policy      = excluded.policy,
      approved_by = excluded.approved_by,
      approved_at = excluded.approved_at,
      updated_at  = excluded.updated_at;
