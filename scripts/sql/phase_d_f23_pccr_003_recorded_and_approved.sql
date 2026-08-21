-- F23 - PCCR-003 recorded, and approved, because he approved it in writing
--
-- F20 changed public.fn_phase_c_require_founder, which is one of the 25 frozen Phase C subjects
-- (subject `founder_authentication`). fn_phase_c_freeze_drift() went red on
-- frozen_subjects_drifted the moment it applied, correctly, and the remedy is a recorded change
-- request and a recorded amendment -- not a quieter board.
--
-- THIS IS THE ONE PHASE C AMENDMENT THE FOUNDER HAS APPROVED, and his approval is quoted rather
-- than summarised. From his ruling of 21 Aug 2026, section E, verbatim:
--
--     "Do not request a new founder secret. Do not use the founder's email address as
--      authentication proof. The approved design is Supabase Auth JWT identity. Use: verified JWT
--      -> verified auth subject (sub) -> server-side lookup against the enabled founder identity ->
--      founder action."
--
-- and, in the same message, under F: "For the founder-authentication amendment, use the approved
-- JWT-subject design above. Stop before applying any other Phase C amendment until founder approval
-- is recorded."
--
-- So: this amendment is applied and recorded as approved. PCCR-001 and PCCR-002 are NOT touched.
-- Their four amendments still read approved_by = null, the freeze board still reports
-- "4 of 4 await the founder", and nothing in this file or this session clears that row.
--
-- WHAT approved_by MEANS ON THIS ROW, stated because E39 is about exactly this. It is not a claim
-- that the founder authenticated to this database. It is the record of a written instruction he
-- gave, applied by the database OWNER through a migration -- which E39 established is what every
-- historical write to this table already was. The instruction is quoted above and the
-- change-request document holds it in full.

INSERT INTO public.phase_c_change_request (change_request_ref, document_path, subject, approved_by, approved_at)
VALUES ('PCCR-003',
        'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-003.md',
        'F20 replaced the caller-supplied founder identity in fn_phase_c_require_founder with a verified Supabase Auth subject, resolved either from auth.uid() or from a subject os_api verified and bound. Amendment 6.',
        'management@quotesdone.com', now())
ON CONFLICT (change_request_ref) DO NOTHING;

INSERT INTO public.phase_c_freeze_amendment
  (subject, object_identity, prior_digest, new_digest, reason, evidence, change_request_ref,
   approved_by, approved_at)
VALUES (
  'founder_authentication',
  'fn_phase_c_require_founder(p_actor text)',
  'b2fff88d695729ddc8134532908ca0dd9fb3697f80bd7457d8ec35ab5a601e24',
  encode(sha256(convert_to(pg_get_functiondef('public.fn_phase_c_require_founder(text)'::regprocedure),'UTF8')),'hex'),
  'The frozen body resolved a CALLER-SUPPLIED string against public.phase_c_founder_identity, so from service_role '
  || 'fn_phase_c_require_founder(''management@quotesdone.com'') returned PASSED_AS -- and that routine gates '
  || 'fn_kernel_cancel, fn_founder_command_clarify, fn_founder_command_control and the refund decision guard, under a '
  || 'standing rule that every refund needs the founder at any amount. The new body resolves the founder from a VERIFIED '
  || 'auth subject only: auth.uid() where a bearer token reached PostgREST, or a subject os_api verified with Supabase '
  || 'Auth and bound in the same transaction through fn_phase_c_founder_subject_bind. p_actor becomes an assertion that '
  || 'must match the verified identity and is never the source of it. The founder approved this exact design in writing '
  || 'on 21 Aug 2026 and instructed that no new secret be requested; none is, and none appears in source, in database '
  || 'prose, in a prompt or in a test file.',
  'Measured by execution on production, inside a transaction ending in raise exception, and recorded in '
  || 'docs/phase-d/PHASE_D_FOUNDER_AUTHENTICATION_RESULT.csv: typing the founder''s registered email as service_role is '
  || 'now REFUSED (28000); his verified auth subject is ACCEPTED and returns management@quotesdone.com; a real '
  || 'non-founder auth subject (acceptance-nonfounder@example.invalid) is REFUSED; an unknown subject is REFUSED; a '
  || 'hand-set app.phase_c_founder_auth_event is REFUSED; and four HTTP probes against the deployed os_api -- no header, '
  || 'a garbage bearer token, the anon key as a bearer token, and a forged JWT naming the founder''s subject -- all '
  || 'return 401. fn_phase_a_baseline_drift() and fn_phase_b_baseline_drift() both return 0 rows after the change.',
  'PCCR-003',
  'management@quotesdone.com',
  now())
ON CONFLICT DO NOTHING;

-- THE FROZEN DIGEST IS NOT UPDATED, AND THAT IS THE DESIGN.
--
-- My first draft ended with an UPDATE on public.phase_c_frozen_subject to move the baseline to the
-- new body. The estate refused it:
--
--     phase_c_frozen_subject is append-only and its rows are permanent: UPDATE is refused. A
--     founder approval and the frozen subjects it covers are the record that everything else is
--     measured against, so they are never edited or deleted. (phase_c_approval_immutable)
--
-- It is right and the draft was wrong. fn_phase_c_freeze_drift() already distinguishes a subject
-- whose live digest matches a RECORDED AMENDMENT's new_digest from one that simply drifted -- that
-- is what frozen_subjects_changed_under_a_recorded_amendment counts. So the amendment row above is
-- the whole remedy: the baseline keeps saying what the founder froze, and the amendment says what
-- he later approved and why. Editing the baseline would have erased the first of those.
