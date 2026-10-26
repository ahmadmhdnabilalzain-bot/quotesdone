-- The cacheable half was a different length on every call
-- =======================================================
--
-- agent_brain is the most expensive path in the system: 637 calls and AED 79.46 of the ~133 spent
-- in the last 7 days, ~60% of everything, averaging 13,189 input tokens. Its prompt-cache read
-- ratio is 0.117% - avg_cached_in of 15 tokens against avg_in of 13,189. Effectively nothing has
-- ever been cached.
--
-- The brief said the split fails because fn_agent_context_capped trims the three '# LAYER ...'
-- markers away. Measured, that is not it. agent_brain looks for
--     '\n# LAYER 3 - LIVE OPERATIONAL STATE'
--     '\n# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED'
-- and NEITHER STRING HAS EVER EXISTED. The uncapped 207,798-character context emits five markers
-- and they read '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE', '# LAYER 1 - COMPANY KNOWLEDGE (...)',
-- '# LAYER 2c - HOW THIS COMPANY OPERATES (...)' and '# LAYER 4 (EXTERNAL) - AUTHORITATIVE SOURCES
-- OUTSIDE THIS COMPANY'. There is no LAYER 3 heading anywhere, and LAYER 4 carries a different
-- suffix. The split matches nothing, cutAt is -1, sysStable is '', and agent_brain marks nothing
-- cacheable. It is a hard-coded match against prose that was renamed.
--
-- BUT FIXING THE STRINGS ALONE WOULD HAVE MADE THINGS WORSE, and this is the part worth keeping.
-- A cache_control prefix only pays if it is BYTE-IDENTICAL between calls; a prefix that changes
-- writes cache at a 25% premium and reads none of it. Measured on the same agent with two
-- different questions, the capped context's head ended at 15,727 characters one call and 16,904
-- the next, and the md5 of the two prefixes differed. Two causes, both in this function:
--
--   v_room := v_want - length(v_tail) - 240
--     The head's budget is computed from the TAIL's length, and the tail is LAYER 2b/2c, retrieved
--     for that specific question. A longer retrieval silently shortens the standing context, so the
--     head is a different length every time the question changes.
--
--   v_note embeds length(v_head) and v_room as digits, and sits BETWEEN head and tail
--     so even at an identical cut the bytes differ, and the note is inside the region a naive
--     split would call stable.
--
-- The raw context itself is fine: fn_agent_context's first 12,000 characters are byte-identical
-- across two different questions for the same agent, and correctly differ between agents. The
-- instability was manufactured entirely here.
--
-- SO: the head gets a FIXED budget, and the boundary is announced with an explicit marker instead
-- of being guessed at from a heading that can be reworded. v_tail_reserve is fixed at 4,500
-- characters - both observed retrievals (3,812 and 2,927) fit inside it with room, and a retrieval
-- that genuinely exceeds it is truncated and said so, rather than being paid for by silently
-- shrinking the standing context. The trim note moves AFTER the marker so the stable region is
-- byte-identical.
--
-- WHETHER THIS PAYS, measured rather than assumed. prompt_cache_enabled was set false on 11 Aug
-- because the read/write ratio came out 0.115 against a 0.22 break-even - but that was measured
-- while the split cached nothing, so it measured nothing. What actually governs it is how often
-- the same agent calls back inside the TTL. Over 7 days, 621 agent_brain calls across just 12
-- distinct agents:
--     median gap between one agent's calls   1 minute
--     within 5 minutes (5-min TTL breaks even at 22%)   58.5%
--     within 1 hour    (1-h TTL breaks even at 53%)     89.0%
-- Both TTLs clear their break-even with margin. The switch is deliberately NOT flipped here: the
-- founder's sequence is fix the split, re-measure over a full week, then decide, and the numbers
-- above are the prediction that week should test.

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
  v_want   int := greatest(coalesce(p_max_chars, 9000), 500);
  v_raw    text;
  v_l2     int;
  v_head   text; v_tail text;
  v_room   int;
  v_note   text;
  -- Fixed, so the stable region cannot be resized by what this particular question retrieved.
  v_reserve constant int := 4500;
  -- The one place the stable/volatile boundary is declared. agent_brain splits on this exact
  -- string. It is deliberately not a content heading: headings get reworded, and the last time
  -- the split depended on one it silently stopped matching and nobody noticed for a month.
  v_mark   constant text := E'\n# --- END STABLE CONTEXT ---\n';
begin
  if p_query is null or btrim(p_query) = '' then
    v_raw := public.fn_agent_context(p_agent_key, v_want);
  else
    v_raw := public.fn_agent_context(p_agent_key, v_want, p_query);
  end if;

  if v_raw is null then return null; end if;

  v_l2 := position('# LAYER 2b' in v_raw);

  -- No query-matched tail: the whole thing is standing context and is stable as it is.
  if v_l2 = 0 then
    if length(v_raw) <= v_want then return v_raw || v_mark; end if;
    return left(v_raw, v_want - 110) || v_mark ||
      E'\n[context truncated to the ' || v_want || ' characters requested; ' || length(v_raw) ||
      ' were available. No retrieved department layer was present, so this cut is positional.]';
  end if;

  v_head := substr(v_raw, 1, v_l2 - 1);   -- standing context: identity, expertise, company, live
  v_tail := substr(v_raw, v_l2);          -- LAYER 2b + 2c, retrieved for THIS question

  -- Everything fits: nothing is trimmed and the head is whole.
  if length(v_raw) <= v_want then return v_head || v_mark || v_tail; end if;

  v_room := v_want - v_reserve;           -- FIXED. Does not depend on this question's retrieval.

  if v_room < 600 then
    -- The budget cannot fit the standing context at all. Keep what answers the question.
    return E'[Standing context omitted in full: the ' || v_want || '-character budget does not fit '
      || 'it alongside the material retrieved for this question. Identity, expertise, company '
      || 'knowledge and live state are NOT below - do not assert anything about them.]' || v_mark
      || left(v_tail, greatest(v_want - 300, 400));
  end if;

  v_note := E'\n[Standing context trimmed to the first ' || v_room || ' characters of '
         || length(v_head) || '. What follows was retrieved for this specific question. If you '
         || 'need the omitted background, say so rather than guessing at it.]\n';

  -- head is left() to a CONSTANT length, so for a given agent and budget these bytes are identical
  -- on every call. Everything that varies - the note's digits, the retrieved layers - is after the
  -- marker.
  return left(v_head, v_room) || v_mark || v_note ||
         case when length(v_tail) > v_reserve
              then left(v_tail, v_reserve - 120) ||
                   E'\n[retrieved material truncated at ' || v_reserve || ' characters]'
              else v_tail end;
end
$function$;
