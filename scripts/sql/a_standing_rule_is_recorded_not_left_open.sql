-- Seat: ceo. Founder instruction 709 (22 Sep 2026): "that 66 should be zero" -- the count of open
-- founder_instruction rows. Measured 23 Sep 2026: 54 open, of which 9 are standing rules, not tasks.
-- Root cause: founder_instruction_status_check had no value for a standing rule, so every rule the
-- founder gave ("keep that as a rule", "from now on", "never ...") could only sit at 'open' forever and
-- the open count could never reach zero however much work was finished. A standing rule is recorded
-- and enforced elsewhere (memory file / routine); it is not a pending task.
-- Closed by exact id only (lesson: close by key, never by title match). The remaining 45 open rows are
-- genuine pending work (drawings, knowledge build, pre-sandbox items) and stay open.
begin;

alter table public.founder_instruction drop constraint founder_instruction_status_check;
alter table public.founder_instruction add constraint founder_instruction_status_check
  check (status = any (array['open','done','deferred_by_founder','superseded','refused','standing']));

-- fn_founder_instruction_needs_evidence sets closed_at for any non-open status.
update public.founder_instruction f
   set status = 'standing',
       evidence = coalesce(nullif(btrim(f.evidence), ''), '') || v.ev
  from (values
    (717, 'Standing rule: memory agent-worktrees-fill-the-founders-disk.md (remove finished worktrees).'),
    (720, 'Standing rule: memory agent-worktrees-fill-the-founders-disk.md (delete folders once on GitHub/Supabase).'),
    (855, 'Standing rule: memory every-founder-message-is-an-instruction.md (done items leave the pending list).'),
    (863, 'Standing rule: do not re-register the WhatsApp sender; memory use-edge-browser-and-act-without-founder.md.'),
    (864, 'Standing until the founder lifts it: memory launch-only-when-perfect-sandbox.md (sandbox paused).'),
    (890, 'Standing rule: no word matching; memory pre-sandbox-seat-audit-23-sep.md.'),
    (918, 'Standing until the founder lifts it: memory never-raise-openrouter-again.md.'),
    (942, 'Standing rule: at most 10 agents at a time; skill quotesdone-parallel-agents.'),
    (953, 'Standing until the founder lifts it: knowledge build paused, resume point kb/PROGRESS.md.')
  ) as v(id, ev)
 where f.id = v.id and f.status = 'open';

do $$ declare n int; begin
  select count(*) into n from public.founder_instruction where status = 'standing' and closed_at is not null
   and id in (717,720,855,863,864,890,918,942,953);
  if n <> 9 then raise exception 'expected 9 standing rows closed, got %', n; end if;
end $$;

commit;
