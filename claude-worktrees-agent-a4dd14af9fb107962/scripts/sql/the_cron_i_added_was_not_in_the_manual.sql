-- The cron job I added this afternoon was not in the manual
-- ========================================================
--
-- Re-scoring Row #3 after this session's work returned 126/152, DOWN one from 127. The regression
-- was mine: s38-manual-always-current went MET -> MISSING, reading
--
--     "1 active cron job(s) are undocumented and 0 documented job(s) no longer exist,
--      against 174 active job(s) and 190 registrations"
--
-- I registered kb_embed_priority_kinds with cron.schedule and never added it to cron_registry.
-- The check is exactly right and it caught me within hours: a scheduled job nobody has written
-- down is a job nobody can explain when it misbehaves, which is the whole point of the manual.
--
-- Worth recording rather than quietly fixing, because the lesson generalises: every cron.schedule
-- in this estate needs a cron_registry row in the same change. Applied to both projects; verified
-- by the check's own predicate afterwards - 0 undocumented active, 0 documented-but-gone, against
-- 174 active jobs and 191 registrations.

insert into public.cron_registry (jobname, human_name, category, purpose)
values ('kb_embed_priority_kinds',
        'Embed the priority knowledge kinds',
        'knowledge',
        'Drains the finite backlog of kb_chunks whose source_kind is trade, regulation or material - 2,090 rows that sat at 0% embedded because kb_embed''s source_kinds filter, added 11 Aug for exactly these rows, had no caller. They arrived after the 115,148-row pack import, so a strict FIFO left UAE regulations and trade knowledge days behind a queue of pack chunks. Separate from kb_embed_backfill so the fair FIFO is never starved. Self-limiting: once the set is drained kb_embed finds nothing matching and the job is a no-op. Batch stays at 5 - 8 returns HTTP 546 on this edge worker - so throughput comes from invocation count, never batch size. Embedding is the free in-region gte-small model.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
