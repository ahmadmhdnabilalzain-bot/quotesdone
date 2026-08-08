-- fn_agent_context hardening (found while verifying knowledge injection):
--  BUG 1: the loop EXITED on the first over-cap row, so one large _global row starved everything after it
--         (even agents' own knowledge). Fixed: SKIP an over-cap row and keep packing.
--  BUG 2: the shared "critical" _global band grew large and crowded out each agent's OWN expertise and
--         newer rules (e.g. writing:human_voice, canon). Fixed: reserve a guaranteed slice for the agent's
--         own knowledge (pass 1), then critical globals (pass 2), then the rest (pass 3); raise the cap floor.
--  (A pre-existing junk row "Company FAQ (canonical answers)" is ~198KB — always skipped, harmless, but worth trimming later.)
CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text DEFAULT NULL::text, p_max_chars integer DEFAULT 9000)
 RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $function$
declare out text := ''; r record; piece text; cap int; own_cap int;
begin
  cap := greatest(coalesce(p_max_chars,9000), 22000);
  own_cap := least(cap/2, 6000);
  if p_agent_key is not null then
    for r in select topic,content from agent_knowledge where agent_key=p_agent_key order by priority desc nulls last, updated_at desc loop
      piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
      if length(out)+length(piece) <= own_cap then out := out||piece; end if;
    end loop;
  end if;
  for r in select topic,content from agent_knowledge where agent_key='_global' and coalesce(priority,0)>=90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;
  for r in select topic,content from agent_knowledge where agent_key='_global' and coalesce(priority,0)<90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;
  return 'COMPANY & ROLE KNOWLEDGE (authoritative — follow this; pricing marked LIVE overrides any other figure):'||E'\n\n'||out;
end $function$;
-- writing:human_voice promoted to the critical band (92); the 8 always-on canon rows consolidated to 3 dense ones.
