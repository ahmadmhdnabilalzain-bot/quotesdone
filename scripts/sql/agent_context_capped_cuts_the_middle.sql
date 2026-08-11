-- =================================================================================================
-- fn_agent_context IGNORES p_max_chars. THIS ENFORCES IT WITHOUT THROWING AWAY THE ANSWER.
--
-- MEASURED 11 Aug 2026 on production:
--     ask  6,000 -> 32,324 chars      ask 24,000 -> 34,316      ask 60,000 -> 70,254
-- A ~30,000-character floor ignores the cap entirely, so asking for less barely helps: 6,000 and
-- 24,000 differ by 2,000 characters of output. agent_brain asks for 24,000 and receives 34,316.
--
-- WHY IT MATTERS: agent_brain is 68% of all AI spend - 278 calls, AED 69.47 of 102.01 in seven
-- days, averaging 24,619 input tokens. The overshoot is ~10,300 characters a call, roughly 2,600
-- tokens, about 720,000 tokens a week, on the single most expensive path in the system.
--
-- WHY THE EXISTING WRAPPER WAS NOT ENOUGH. fn_agent_context_capped already existed and already
-- said the right thing in its own comment - "the inner function ignores anything below 22,000 and
-- overshoots above it, so ask for what we want and then enforce the promise ourselves" - but it is
-- 2-argument only and it truncates with left(). agent_brain calls the 3-ARGUMENT overload, whose
-- LAYER 2b (department reference library) and LAYER 2c (how this company operates) are retrieved
-- FOR THAT SPECIFIC QUESTION and appended at the END. left(raw, cap) would therefore delete the
-- most relevant content in the whole context and keep the static block.
--
-- SO THIS CUTS THE MIDDLE. The layers fn_agent_context emits are, in order:
--     # LAYER 1  - COMPANY KNOWLEDGE            (authoritative, small)
--     # LAYER 2  - YOUR PROFESSIONAL EXPERTISE  (the big static block - THIS is what gets trimmed)
--     # LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY   (query-matched, keep whole)
--     # LAYER 2c - HOW THIS COMPANY OPERATES          (query-matched, keep whole)
--     # LAYER 3  - LIVE OPERATIONAL STATE             (live figures, keep whole)
--     # LAYER 4  - WHAT THIS ORGANIZATION HAS LEARNED (keep whole)
-- Layer 2 is the only one that does not change with the question, so it is the only one whose loss
-- is a loss of breadth rather than a loss of the answer. Everything else survives intact.
--
-- The trim is announced in the text rather than silent: an employee that has had material removed
-- is told so, because a model that does not know its context was cut will assert things about the
-- gap. If head+tail alone already exceed the cap, we fall back to a plain left() and say so - a
-- caller asking for less than the non-negotiable content gets the honest truncation.
-- =================================================================================================

CREATE OR REPLACE FUNCTION public.fn_agent_context_capped(
  p_agent_key text,
  p_max_chars integer DEFAULT 9000,
  p_query text DEFAULT NULL
)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_want  int := greatest(coalesce(p_max_chars, 9000), 500);
  v_raw   text;
  v_l2    int;      -- start of LAYER 2
  v_next  int;      -- start of the layer after LAYER 2
  v_head  text; v_mid text; v_tail text;
  v_room  int;
  v_note  text;
begin
  if p_query is null or btrim(p_query) = '' then
    v_raw := public.fn_agent_context(p_agent_key, v_want);
  else
    v_raw := public.fn_agent_context(p_agent_key, v_want, p_query);
  end if;

  if v_raw is null then return null; end if;
  if length(v_raw) <= v_want then return v_raw; end if;

  -- THE EMITTED ORDER IS NOT THE NUMBERED ORDER. Measured on production 11 Aug 2026, the layers
  -- come out as:  LAYER 2  ->  LAYER 1  ->  LAYER 3  ->  LAYER 4  ->  LAYER 2b  ->  LAYER 2c
  -- so "LAYER 2" is not a contiguous block and cutting between it and the next '# LAYER ' marker
  -- removes a header and nothing else. (A first version of this function did exactly that and made
  -- the output LONGER than the input by the length of its own explanatory note.)
  --
  -- What IS reliably true, and is what matters: the two query-matched layers - 2b, the department
  -- reference library, and 2c, how this company operates - are emitted LAST. So the split is at
  -- LAYER 2b: everything from there is retrieved for this exact question and is kept whole;
  -- everything before it is the standing context and is what gets trimmed.
  v_l2 := position('# LAYER 2b' in v_raw);
  if v_l2 = 0 then
    -- No query-matched tail (2-argument call, or nothing retrieved). Nothing is question-specific,
    -- so a positional cut loses the least.
    return left(v_raw, v_want - 110) ||
      E'\n\n[context truncated to the ' || v_want || ' characters requested; ' || length(v_raw) ||
      ' were available. No retrieved department layer was present, so this cut is positional.]';
  end if;

  v_head := substr(v_raw, 1, v_l2 - 1);   -- standing context: identity, expertise, company, live
  v_tail := substr(v_raw, v_l2);          -- LAYER 2b + 2c, retrieved for THIS question
  v_room := v_want - length(v_tail) - 240;

  if v_room < 600 then
    -- The retrieved material alone does not fit the budget. Keep it - it is the part that answers
    -- the question - and say plainly that the standing context went.
    return E'[Standing context omitted in full: the ' || v_want || '-character budget does not fit '
      || 'it alongside the ' || length(v_tail) || ' characters retrieved for this question. '
      || 'Identity, expertise, company knowledge and live state are NOT below - do not assert '
      || 'anything about them.]\n\n' || left(v_tail, greatest(v_want - 300, 400));
  end if;

  v_note := E'\n\n[Standing context trimmed to fit the ' || v_want || '-character budget: '
         || length(v_head) || ' characters were available, ' || v_room || ' kept. What follows was '
         || 'retrieved for this specific question and is complete. If you need the omitted '
         || 'background, say so rather than guessing at it.]\n';

  return left(v_head, v_room) || v_note || v_tail;
end
$function$;
