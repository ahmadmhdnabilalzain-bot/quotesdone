-- THE FOUNDER APPROVED IT ENGINEER DUTIES 19 TO 24. His ruling of 14 Sep 2026, verbatim, in the register
-- the day he gave it. The duties are built on branch it-engineer/duties-19-24; the row stays open until
-- those files are applied and scripts/checks/it_engineer_duties_19_to_24.test.mjs passes against production.
-- The same words also approved the accountant's five further duties (PR #659); one row carries them, and
-- whichever build lands second finds it already there.
--
-- Assigned: it_engineer.

insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z', v.i, v.s, 'open', 'branch it-engineer/duties-19-24; scripts/checks/it_engineer_duties_19_to_24.test.mjs'
  from (values
    ('add all for accountant and IT',
     'it_engineer duties 19 to 24: monthly restore drill, renewal watch, email deliverability, usage and bill watch, dependency security patch, unauthorised production change guard (and the accountant''s five further duties, PR #659)')
  ) v(i, s)
 where not exists (select 1 from public.founder_instruction f where f.instruction = v.i);
