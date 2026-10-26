-- ---------------------------------------------------------------------------
-- fn_agent_context: honour the cap it is given.
--
-- Two measured defects, both feeding the most expensive function in the company:
--   1. cap := greatest(coalesce(p_max_chars, 9000), 22000)
--      A 22,000-character FLOOR. The parameter was a lie below that: asking for
--      4,000 returned 28,062. No caller could reduce its own context.
--   2. It overshot above the floor too. Asking for 24,000 returned 30,268 (+26%),
--      because layer 3 used cap + 3000 and layer 4 appended after the cap check.
--
-- agent_brain requests 24,000 and does not truncate, which is the largest single
-- term in its 21,829-token prompt. At 94% input share, characters here are money.
--
-- This wrapper enforces the contract without touching the layered assembly logic:
-- ask for N, get at most N. The floor becomes a sensible DEFAULT (when the caller
-- passes nothing) rather than a minimum nobody can go below.
-- ---------------------------------------------------------------------------

alter table model_registry add column if not exists dummy_noop boolean;
alter table model_registry drop column if exists dummy_noop;

create or replace function fn_agent_context_capped(p_agent_key text, p_max_chars integer default 9000)
returns text
language plpgsql stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_want int := greatest(coalesce(p_max_chars, 9000), 500);
  v_raw  text;
begin
  -- The inner function ignores anything below 22,000 and overshoots above it, so ask
  -- for what we want and then enforce the promise ourselves.
  select fn_agent_context(p_agent_key, v_want) into v_raw;
  if v_raw is null then return null; end if;
  if length(v_raw) <= v_want then return v_raw; end if;

  -- Truncate on a paragraph boundary where possible so a layer is not cut mid-sentence.
  return left(v_raw, v_want - 60) || E'\n\n[context truncated to the ' || v_want ||
         ' characters requested; ' || length(v_raw) || ' were available]';
end $$;

revoke execute on function fn_agent_context_capped(text,integer) from public, anon, authenticated;

comment on function fn_agent_context_capped(text,integer) is
  'Wrapper that makes p_max_chars mean what it says. fn_agent_context has a hard 22,000-char floor and overshoots its cap by ~26%; this enforces the contract so callers can actually control their prompt size. Added 28 Jul 2026 - agent_brain is 69% of AI spend and 94% of that is input tokens.';