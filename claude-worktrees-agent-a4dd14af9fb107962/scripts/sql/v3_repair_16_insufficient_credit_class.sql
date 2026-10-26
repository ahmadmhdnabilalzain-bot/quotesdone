-- V3 REMEDIATION — the taxonomy meets its first real-world failure and has no name for it.
--
-- At 14:24 UTC on 14 Aug 2026 every model route began failing during the internal regression run.
-- 160 attempts across both rungs of the ladder, every one classified 'unclassified'. The error text
-- was unambiguous and had nothing to do with this codebase:
--
--   {"message":"This request requires more credits, or fewer max_tokens. You requested up to 8000
--    tokens, but can only afford 1454. ..."}
--
-- The provider account ran out of credit mid-run. That is a BILLING event, and it is the single
-- most important class to name correctly, because:
--   * in every monitor we have it is indistinguishable from a model outage;
--   * it is NOT retryable - each retry fails identically and eats the wall budget;
--   * the remedy is a human topping up an account, not any engineering change.
--
-- 'unclassified trending to zero' is the taxonomy's own acceptance criterion, and this is precisely
-- the case it exists to surface. It surfaced it. Naming it is the follow-through.
--
-- The classifier is patched by INSERTING one arm at the head of its existing CASE rather than by
-- retyping the body, so the other twelve classes are untouched.

begin;

insert into public.llm_failure_class
  (class_key, layer, description, retryable, max_retries, retry_backoff_ms,
   trips_breaker, opens_on_first, operator_note)
values
  ('insufficient_credit', 'provider',
   'Provider refused the request for lack of account credit: HTTP 402, or a body naming credits / '
   'affordability / quota exceeded / payment required.',
   false, 0, 0, true, true,
   'NOT a model fault and NOT retryable - every retry fails identically and burns the wall budget. '
   'Opens on the FIRST occurrence because the remedy is a human topping up the account. First '
   'observed 14 Aug 2026 during the V3 remediation regression run: 160 attempts across '
   'anthropic/claude-opus-4.8 and anthropic/claude-sonnet-5, all of which had been landing in '
   'unclassified.')
on conflict (class_key) do update set
  description = excluded.description, retryable = excluded.retryable,
  max_retries = excluded.max_retries, trips_breaker = excluded.trips_breaker,
  opens_on_first = excluded.opens_on_first, operator_note = excluded.operator_note;

do $$
declare v_def text; v_new text; v_anchor text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_classify_llm_failure';
  if v_def is null then raise exception 'fn_classify_llm_failure not found'; end if;

  if position('insufficient_credit' in v_def) > 0 then
    raise notice 'classifier already carries the insufficient_credit arm; nothing to do';
    return;
  end if;

  -- The existing head of the CASE. Billing goes ABOVE it: an out-of-credit refusal can arrive with
  -- a 4xx that the credential arm would otherwise claim, and it must never be reported as an auth
  -- problem or a transient provider error.
  v_anchor := '  k := case';
  if position(v_anchor in v_def) = 0 then
    raise exception 'could not find the CASE head in fn_classify_llm_failure; refusing to guess';
  end if;

  v_new := replace(v_def, v_anchor, v_anchor || E'\n' ||
    E'    -- BILLING FIRST (added 14 Aug 2026). Stable across every OpenRouter model, and not\n' ||
    E'    -- retryable: retrying an out-of-credit request cannot succeed and burns the wall budget.\n' ||
    E'    when p_http_status = 402\n' ||
    E'      or e ~* ''(requires more credits|insufficient[_ ]credit|can only afford|quota exceeded|payment required)''\n' ||
    E'      then ''insufficient_credit''');

  execute v_new;
  raise notice 'classifier patched with the insufficient_credit arm';
end $$;

commit;
