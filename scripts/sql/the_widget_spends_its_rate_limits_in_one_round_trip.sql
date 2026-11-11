-- THE WIDGET'S RATE LIMITS IN ONE ROUND TRIP. Seat: it_engineer (11 Nov 2026, load test round 2, founder ruling 1622).
--
-- Measured: in the 02:42-02:46 UTC stubbed chat run (main 2bd2fa971) the edge log counted 727 rl_check calls for ~133
-- website chat turns. site_assistant spends four to six limiter buckets per turn (the hard per-IP ceiling, the new-
-- conversation bucket on a first turn, the conversation's depth, the global daily ceiling, then the visitor cap by
-- conversation and by IP), each its own HTTPS round trip and PostgREST transaction, on a worker whose 2 s CPU budget the
-- run exhausted: one worker was killed at cpu_time_used 2,003 ms with 17 of the 18 turns it held (HTTP 546).
--
-- What this adds: fn_rl_check_chain(p_groups jsonb), which spends a chain of buckets through the existing rl_check, in
-- order: every bucket of a group is spent, and no bucket of a later group is spent once a group refused. That is exactly
-- the order and the short-circuits site_assistant/index.ts already follows, so the counting is unchanged; the caller
-- (site_assistant/limit_chain.ts) answers each limiter question from the result and spends anything else the old way.
-- Answer: one jsonb array per group, true / false per bucket spent, null for a bucket not spent.
--
-- What it does NOT change: rl_check itself (its advisory lock per key, its window, rl_hits). Buckets are spent in one
-- transaction, so a key's lock is held until the chain ends rather than until its own call ends; every caller takes the
-- keys in the same order (hard IP, conversation, global, visitor cap), so this can wait but cannot deadlock.
-- Bounds: at most 8 groups of at most 8 buckets (the widget uses 3 to 6 buckets).
-- Until this is applied, site_assistant falls back to one rl_check call per bucket (limit_chain.ts prefetchLimits).
-- Probe: the_widget_spends_its_rate_limits_in_one_round_trip_probe.sql (pure, always raises CHK<<...>>).
create or replace function public.fn_rl_check_chain(p_groups jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  g jsonb; s jsonb; row_ jsonb; out_ jsonb := '[]'::jsonb; go boolean := true; ok boolean;
begin
  if jsonb_typeof(p_groups) is distinct from 'array' or jsonb_array_length(p_groups) > 8 then
    raise exception 'fn_rl_check_chain: p_groups must be an array of at most 8 groups';
  end if;
  for g in select value from jsonb_array_elements(p_groups) loop
    if jsonb_typeof(g) is distinct from 'array' or jsonb_array_length(g) > 8 then
      raise exception 'fn_rl_check_chain: each group must be an array of at most 8 buckets';
    end if;
    row_ := '[]'::jsonb;
    for s in select value from jsonb_array_elements(g) loop
      if go then
        ok := public.rl_check(s ->> 'k', (s ->> 'l')::int, (s ->> 's')::int);
        row_ := row_ || to_jsonb(ok);
      else
        row_ := row_ || 'null'::jsonb;
      end if;
    end loop;
    out_ := out_ || jsonb_build_array(row_);
    if go and row_ @> '[false]'::jsonb then go := false; end if;
  end loop;
  return out_;
end
$fn$;

-- CREATE grants EXECUTE to PUBLIC: closed here (service_role keeps it; site_assistant calls it with the service key).
revoke execute on function public.fn_rl_check_chain(jsonb) from public, anon, authenticated;
