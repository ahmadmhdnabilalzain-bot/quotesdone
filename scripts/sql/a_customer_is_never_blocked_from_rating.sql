-- A CUSTOMER IS NEVER BLOCKED FROM RATING
--
-- MEASURED FIRST (17 Sep 2026, production journey PR #755/#759). `customer_api:rate_supplier`
-- returns HTTP 500 for every customer who touches a star. An aborted-transaction probe reproduced
-- it exactly: SQLSTATE 23514, constraint `reviews_reason_required`. The star widget
-- (src/components/me/CustomerPortal.tsx) sends `comment: null` and offered no box to type one in,
-- and the constraint demanded a comment of at least 10 characters. `public.reviews` holds 0 rows —
-- not "few", zero — so no rating has EVER succeeded on this platform. It stayed hidden because no
-- crawler reached the button until that journey.
--
-- WHAT THIS CHANGES, AND WHY IT IS NOT A WEAKENED GUARD. The constraint was added 8 Aug 2026 on the
-- founder's words — "he need to specify a reason. he need to write anything. Like, even if it's,
-- like, five words would be enough" — and the intent behind it was sound: a bare star is worth
-- little to the next customer reading it. But a CHECK is the wrong instrument for that intent,
-- because the only thing it can do when the intent is unmet is REFUSE THE RATING ENTIRELY. What it
-- bought was not better reviews; it was zero reviews.
--
-- The operator's decision, 17 Sep 2026: a customer must never be blocked from rating. Stars alone
-- are enough; a written comment is optional. So the rule inverts from "a comment is required" to
-- "a comment, IF GIVEN, must be worth reading":
--
--     comment IS NULL  OR  length(btrim(comment)) >= 10
--
-- The 10-character floor is NOT removed — it still refuses a one-character "review", which is the
-- part of the original guard that protects the next customer. It simply no longer stands between a
-- customer and the act of rating. A stars-only row is accepted; a 3-character comment is refused
-- and the handler now says so in words (customer_api returns 400 with a readable message rather
-- than the raw 500 this constraint was producing).
--
-- WHAT THIS DOES NOT CHANGE. Who may rate and when is untouched: `rate_supplier` still requires a
-- `transactions` row for this customer on this quote (you rate a supplier you revealed and dealt
-- with), `reviews_rating_range` still bounds 1..5, `reviews_one_per_job` still allows one rating
-- per customer per job, and Support still solicits the rating three weeks after the reveal date
-- (fn_support_request_ratings_due). No conversation is purged. The trigger that notifies the sales
-- engineer on every reviews row (a_customer_rating_notifies_the_sales_engineer.sql) is keyed on the
-- row, not on the comment, so a stars-only rating reaches Sales exactly as a commented one does.
--
-- VALIDATED, NOT `NOT VALID`. The predecessor was declared NOT VALID; with 0 rows in the table
-- validation costs nothing and an unvalidated constraint is a constraint nobody has proved.

begin;

alter table public.reviews
  drop constraint if exists reviews_reason_required;

alter table public.reviews
  add constraint reviews_reason_required
  check (comment is null or length(btrim(comment)) >= 10);

comment on constraint reviews_reason_required on public.reviews is
  'A comment is OPTIONAL (operator, 17 Sep 2026: a customer must never be blocked from rating); when one IS given it must be at least 10 characters, so a one-character "review" is still refused.';

commit;

-- ── PROOF, AS A ROW ────────────────────────────────────────────────────────────────────────────
-- `raise notice` is DISCARDED by the management API, so the verdict comes back as a result set.
-- Read it after applying: stars_only_accepted must be true and short_comment_refused must be true.
select
  (select not exists (
     select 1 from pg_constraint
      where conrelid = 'public.reviews'::regclass
        and conname  = 'reviews_reason_required'
        and not convalidated)) as constraint_is_validated,
  -- The predicate itself, evaluated directly: no row is written by this check.
  (null is null or length(btrim(null)) >= 10)              as stars_only_accepted,
  not ('abc' is null or length(btrim('abc')) >= 10)        as short_comment_refused,
  ('a real ten-plus character review' is null or length(btrim('a real ten-plus character review')) >= 10) as long_comment_accepted,
  (select count(*) from public.reviews)                    as reviews_rows;
