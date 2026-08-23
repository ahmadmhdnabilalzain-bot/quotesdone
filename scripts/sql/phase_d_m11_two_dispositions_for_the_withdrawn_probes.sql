-- M11 — two dispositions for the probes M10 withdrew
--
-- PD-AUTH-005 and PD-LEGAL-005 were closed by branches that called
-- public.fn_phase_c_task_create, and M10 withdrew them because that routine is a
-- KERNEL_INTERNAL_PRIMITIVE reachable only from fn_kernel_*. A case that stops running and gains no
-- disposition row is a case nobody decided, and build_injected_defect_result.mjs fails the build for
-- exactly that — so this is owed, not optional.
--
-- Both reasons record what WAS observed before the route was withdrawn, because the refusal is real
-- and the next reader should not have to rediscover it.
insert into public.phase_d_injected_defect_disposition
  (defect_id, category, disposition, reason, what_would_make_it_executable)
values
  ('PD-AUTH-005', 'AUTH', 'PERMANENT_EXEMPTION',
   'The refusal exists and was observed: trigger z10_phase_c_overlay_not_accountable on public.phase_c_task refuses a category overlay presented as the accountable task owner, and the canonical owner is accepted in the same shape. What cannot be done is REACHING it. The only routine in public.kernel_write_authority permitted to write public.phase_c_task from outside the kernel''s own progression is public.fn_phase_c_task_create, and public.kernel_retired_path classifies that routine KERNEL_INTERNAL_PRIMITIVE — reachable only from fn_kernel_*. Measured 24 Aug 2026: a probe that calls it takes fn_kernel_retired_path_state from 0 of 9 to 1 of 9, which is the bypass that board exists to catch. Lengthening the board''s exclusion list to admit this estate''s own probe would be editing a kernel board to suit the code it audits.',
   'Either an authenticated API path that creates a task with a caller-supplied accountable owner — section 8''s HTTP harness reaches supplier_api, supplier_portal and customer_api, none of which opens a task — or a kernel entry point that accepts an owner and routes to fn_phase_c_task_create, so the probe can present a bad owner without calling the primitive itself.'),
  ('PD-LEGAL-005', 'LEGAL', 'PERMANENT_EXEMPTION',
   'As PD-AUTH-005, and the same route. The refusal exists and was observed: trigger z20_phase_c_task_state_guard refuses the owner of W28-S04 ("Assess compliance and privacy") as its own reviewer, and general_counsel is accepted in the same shape — so the independence rule PD-REV-001 proves for reviewers holds for a COMPLIANCE review too. Reaching it needs public.fn_phase_c_task_create, which public.kernel_retired_path classifies KERNEL_INTERNAL_PRIMITIVE.',
   'The same thing PD-AUTH-005 needs: a way to open a task with a caller-supplied owner and reviewer that does not call the kernel-internal primitive directly. A compliance-review path of its own would also do it; W28-S04 is a task step, and no Phase D route opens one.')
on conflict (defect_id) do update
   set category = excluded.category, disposition = excluded.disposition,
       reason = excluded.reason,
       what_would_make_it_executable = excluded.what_would_make_it_executable,
       decided_at = now();
