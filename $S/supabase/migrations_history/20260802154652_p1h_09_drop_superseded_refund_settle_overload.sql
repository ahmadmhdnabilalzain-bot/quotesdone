-- Adding two defaulted parameters to fn_refund_settle created a SECOND function rather than
-- replacing the first: Postgres overloads on argument list, not on name. Both were callable, and
-- the six-argument one still carried the rank-based logic with no transition matrix and no
-- quarantine - so the weaker path was live beside the stronger one, which is exactly the pattern
-- the Control Mode work exists to avoid. Dropped.
drop function if exists public.fn_refund_settle(text, text, bigint, text, text, text);
