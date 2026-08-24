-- DOWN for O02. Every object O02 created, and the register row it added, reversed.
-- Classification: ADDITIVE_DDL — one column, one FK, one trigger, three routines, one register row.
-- The two frozen Phase C refund routines were not touched by O02 and are not touched here.

DROP TRIGGER IF EXISTS z05_refund_execution_requires_decision ON public.refunds;
DROP FUNCTION IF EXISTS public.fn_phase_c_refund_execution_requires_decision();
DROP FUNCTION IF EXISTS public.fn_kernel_refund_ledger_state();

DELETE FROM public.kernel_write_authority
 WHERE routine_name = 'fn_kernel_refund_decision_record'
   AND table_name   = 'phase_c_refund_decision';

DROP FUNCTION IF EXISTS public.fn_kernel_refund_decision_record(jsonb);

-- The column is dropped LAST: the guard above reads it. Dropping it also drops its FK.
-- A refund row citing a decision loses that citation; with public.refunds at 0 rows when O02 was
-- applied, this is a no-op on the data that exists. If rows exist at rollback time, read
-- fn_kernel_refund_ledger_state() FIRST -- the citation is not recoverable after this statement.
ALTER TABLE public.refunds DROP COLUMN IF EXISTS refund_decision_id;
