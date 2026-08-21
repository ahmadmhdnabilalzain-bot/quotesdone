-- F18 - the acceptance service marks the request it answered, and had no authority to
--
-- F05 registered fn_phase_d_capability_request_open as the write authority for
-- public.phase_d_capability_request and fn_phase_d_capability_result_accept as the write authority
-- for public.phase_d_capability_result. The acceptance service also does one thing to the REQUEST
-- -- it sets state = 'answered' -- and fn_kernel_write_guard refused it, correctly, on every
-- submission:
--
--     UPDATE on public.phase_d_capability_request is refused: no routine with write authority for
--     this table is on the call stack.
--
-- Measured: 21 of 21 capability fixture submissions refused this way on the first drive with F17
-- on, and the 21 steps went on reporting pd_capability_unavailable -- a refusal that looked exactly
-- like the boundary working and was in fact a missing register row. That is why the driver records
-- capability_path: without it the count would have read as "the boundary held" and nobody would
-- have looked.
--
-- The remedy is the register row, not a weakening of the guard. Two routines write that table now,
-- each for one reason, and both are named.

INSERT INTO public.kernel_write_authority (table_name, routine_name, why) VALUES
  ('phase_d_capability_request', 'fn_phase_d_capability_result_accept',
   'Marks a request answered in the same statement that records its result. It is the only other write to this table, and a request that carries a result and still reads open would be a state that disagrees with its own evidence.')
ON CONFLICT DO NOTHING;
