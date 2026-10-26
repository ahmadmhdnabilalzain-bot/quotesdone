-- Rehearsal: the function raises after doing all the work, so the enclosing transaction is
-- guaranteed to abort. Nothing here can commit.
select public.fn_p2c1_rollback_stage_b7('rehearse','ops:part3-verification');
