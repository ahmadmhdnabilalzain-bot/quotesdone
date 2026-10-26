-- Rollback for kernel_k30_last_bypass_sources.
--
-- See the header of scripts/sql/kernel_k30_last_bypass_sources.sql for what it does and why. Removing a cutover means the
-- source stops handing work to the kernel; removing a reclassification replaces a measurement
-- with an older, wrong one, and should not be done for either reason.
--
-- Runs, signals and inbox rows already created are NOT deleted. They record work that really
-- happened; removing the trigger that started them does not make them not have happened, and
-- deleting them is the falsification of history the brief forbids. To stop live work, cancel it
-- through fn_kernel_cancel so the cancellation propagates and is recorded.

select 'Rollback for kernel_k30_last_bypass_sources: delete the marked "-- Kernel cutover." block or drop the z95_ trigger '
       'named in the file header, then re-apply. Keep the measured reclassifications. Runs already '
       'created are deliberately kept.' as instruction;
