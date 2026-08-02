-- Stacked rehearsal: roll B.7 back for real inside a transaction, then roll B.6 back on top of it,
-- then abort the whole thing. This is the order an operator would actually use, and it is the only
-- way to prove B.7's restoration leaves B.6's rollback able to run.
begin;
select public.fn_p2c1_rollback_stage_b7('commit','ops:stacked-rehearsal') is not null as b7_rolled_back;
select public.fn_p2c1_rollback_stage_b6('commit','ops:stacked-rehearsal') as b6_report;
rollback;
