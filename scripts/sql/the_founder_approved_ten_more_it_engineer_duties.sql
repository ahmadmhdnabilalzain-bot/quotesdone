-- THE FOUNDER APPROVED TEN MORE IT ENGINEER DUTIES. His two rulings of 14 Sep 2026, verbatim, in the
-- register the day he gave them. The duties themselves (9 to 18) are built in PR #641; each row stays
-- open until that file is applied and its proofs run.
--
-- Assigned: it_engineer.

insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z', v.i, v.s, 'open', 'PR #641 (it-engineer/duties-9-18); scripts/checks/it_engineer_duties_9_to_18.test.mjs'
  from (values
    ('fine build those tasks for IT agent',
     'it_engineer duties 9 to 15: restore drills, sender health, cost and abuse, dependency security, access review, database health, credential rotation'),
    ('yea add them',
     'it_engineer duties 16 to 18: post-deploy smoke, learning loop, incident record')
  ) v(i, s)
 where not exists (select 1 from public.founder_instruction f where f.instruction = v.i);
