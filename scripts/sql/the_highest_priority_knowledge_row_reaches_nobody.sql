-- THE COMPANY'S HIGHEST-PRIORITY KNOWLEDGE ROW REACHES NOBODY, AND NOTHING SAYS SO.
--
-- MEASURED ON PRODUCTION, 14 Aug 2026. agent_knowledge holds, at agent_key='_global':
--
--     ## Company FAQ (canonical answers)          197,956 chars   priority 96
--     ## Asset text: DATABASE_SCHEMA.md             8,000 chars   priority 45
--     ## Asset text: EDGE_FUNCTIONS_REFERENCE.md    8,000 chars   priority 45
--     ## Asset text: 01_EXECUTIVE_SUMMARY.md        8,000 chars   priority 45
--     …and several more at exactly 8,000
--
-- LAYER 1 of fn_agent_context appends these whole:
--
--     piece := '## '||r.topic||E'\n'||r.content||E'\n\n';
--     if length(out)+length(piece) <= cap then out := out||piece; end if;
--
-- The guard is per ITEM against the WHOLE-context cap, and it DROPS rather than truncates. So the
-- 197,956-character row can never satisfy it — not at cap 24,000, not at any cap this function is
-- ever called with — and it is skipped on every call, for every employee, silently. Lower-priority
-- rows that happen to fit are delivered in its place. Measured: LAYER 1 for `procurement` is 11,139
-- characters and contains no part of the FAQ.
--
-- priority 96 is the highest of any global row. Whoever wrote it marked it as the thing employees
-- should know before anything else, and it is the one thing they have never seen. Nothing logs the
-- skip, nothing counts it, and no check looks for it — the row exists, the loop runs, the context
-- is produced, and the only symptom is an absence.
--
-- THE FIX IS TO TRUNCATE INSTEAD OF DROP, AND TO SAY THAT IT DID.
-- 1,500 characters per item: enough for a canonical answer or the head of an asset, small enough
-- that no single row can crowd out the doctrine sections (AI Constitution, brand wording, pricing,
-- RFQ completeness) that share this layer. A truncated item announces its own truncation with the
-- true original length, so an employee that needs the rest knows there IS a rest and can ask —
-- which is strictly better than today, where it cannot know the row exists at all.
--
-- IT ALSO CUTS TOKENS, WHICH IS WHY IT SURFACED DURING A SPEND AUDIT. `## company:self_knowledge`
-- is 4,027 characters and lands in every employee's prompt on every turn; capped at 1,500 that is
-- ~1,100 tokens back on the agent_brain path. But the reason to do it is the FAQ, not the money:
-- this change makes LAYER 1 deliver MORE knowledge, not less, and may cost slightly more on agents
-- whose LAYER 1 was previously under-filled.
--
-- SCOPE. Only the two `agent_key='_global'` loops are touched. The department-scoped loop above
-- them uses an identical `piece :=` line but a different budget (own_cap + 2200) and is left alone:
-- it has no oversized rows and changing it was not measured.
--
-- PATCHED, NOT RETYPED. fn_agent_context is 400+ lines with a documented history of one inserted
-- line silently evicting knowledge from 19 employees. Two exact anchors, both asserted.

do $mig$
declare
  src text; before text;
  -- The truncating replacement, shared by both loops.
  new_piece constant text :=
       '    piece := ''## ''||coalesce(r.topic,'''')||E''\n''||' || E'\n'
    || '             case when length(coalesce(r.content,'''')) > 1500' || E'\n'
    || '                  then left(r.content, 1500)||E''\n''||''[… truncated here at 1,500 of ''' || E'\n'
    || '                       ||length(r.content)||'' characters. This item exists in full in ''' || E'\n'
    || '                       ||''agent_knowledge; ask for the rest if you need it.]''' || E'\n'
    || '                  else coalesce(r.content,'''') end||E''\n\n'';';
  a_hi constant text :=
       '  for r in select topic,content from agent_knowledge' || E'\n'
    || '           where agent_key=''_global'' and coalesce(priority,0)>=90 order by priority desc nulls last, updated_at desc loop' || E'\n'
    || '    piece := ''## ''||coalesce(r.topic,'''')||E''\n''||coalesce(r.content,'''')||E''\n\n'';';
  a_lo constant text :=
       '  for r in select topic,content from agent_knowledge' || E'\n'
    || '           where agent_key=''_global'' and coalesce(priority,0)<90 order by priority desc nulls last, updated_at desc loop' || E'\n'
    || '    piece := ''## ''||coalesce(r.topic,'''')||E''\n''||coalesce(r.content,'''')||E''\n\n'';';
begin
  src := pg_get_functiondef('public.fn_agent_context(text,integer)'::regprocedure);

  before := src;
  src := replace(src, a_hi,
       '  -- TRUNCATE, DO NOT DROP. See the migration header: the per-item guard below compares one' || E'\n'
    || '  -- item against the WHOLE-context cap, so "Company FAQ (canonical answers)" — 197,956 chars' || E'\n'
    || '  -- at priority 96, the highest global row there is — could never fit and was silently' || E'\n'
    || '  -- skipped on every call for every employee.' || E'\n'
    || '  for r in select topic,content from agent_knowledge' || E'\n'
    || '           where agent_key=''_global'' and coalesce(priority,0)>=90 order by priority desc nulls last, updated_at desc loop' || E'\n'
    || new_piece);
  if src = before then raise exception 'anchor 1 (LAYER 1 priority>=90 loop) not found in fn_agent_context — refusing to apply a partial patch'; end if;

  before := src;
  src := replace(src, a_lo,
       '  for r in select topic,content from agent_knowledge' || E'\n'
    || '           where agent_key=''_global'' and coalesce(priority,0)<90 order by priority desc nulls last, updated_at desc loop' || E'\n'
    || new_piece);
  if src = before then raise exception 'anchor 2 (LAYER 1 priority<90 loop) not found in fn_agent_context — refusing to apply a partial patch'; end if;

  execute src;
end $mig$;
