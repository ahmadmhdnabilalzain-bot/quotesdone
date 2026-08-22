-- E39 - the guard authenticated a string, not an actor
--
-- Third attack on the same control, and the auditor is right that this one is strictly worse than
-- the two before it. No fake identity, no DDL, no owner rights, nothing to clean up afterwards:
--
--     set local role service_role;
--     update public.phase_c_freeze_amendment
--        set approved_by = 'ahmadalzain1993@admin.quotesdone.com', approved_at = now()
--      where approved_by is null;                                   -- ACCEPTED, 4 rows
--
-- Freeze board 1 red -> 0, and it STAYS green, because the approval genuinely does resolve. E38's
-- "ask the question fresh on every read" derivation cannot help: there is no forensic difference
-- between this and a real signature. The founder's email is also a plaintext literal in E36's own
-- committed header, so revoking SELECT on the register would not have closed it either.
--
-- E36 and E38 authenticate the STRING. They never authenticated the ACTOR.
--
-- The same auditor found the second half: service_role could INSERT an amendment born already
-- approved, and could DELETE all four (which turns this row green at "0 of 0" while
-- frozen_subjects_drifted goes red at 4 of 25 -- self-limiting, but it defeats the named row).
--
-- WHAT THIS FILE CLOSES, AND WHAT IT DOES NOT.
--
-- CLOSED: service_role's write access to public.phase_c_freeze_amendment. Measured first -- NO
-- routine in the estate writes this table; every row in it was written by a migration applied as
-- the owner. So INSERT, UPDATE and DELETE go, from PUBLIC first because a grant held through PUBLIC
-- makes a revoke from a named role a silent no-op. SELECT stays: the drift board, the approver guard
-- and CI all read it. After this, all three of the auditor's service_role vectors -- approve in his
-- name, insert pre-approved, delete the lot -- are refused at the grant layer, before E36's trigger
-- is even consulted.
--
-- NOT CLOSED, AND IT IS THE LARGER FINDING: public.fn_phase_c_require_founder(p_actor text)
-- resolves a CALLER-SUPPLIED STRING against the same register, with no binding to a session or a
-- credential. As service_role, fn_phase_c_require_founder('management@quotesdone.com') returns
-- PASSED_AS. That routine gates fn_refund_decide and fn_founder_command_submit, and the founder's
-- standing rule is that every refund needs him at any amount. So the estate's model of "the founder
-- approved this" is, today, "somebody typed his email".
--
-- I am NOT fixing that here and I am not going to pretend a grant revoke did. Closing it needs a
-- binding the database cannot manufacture on its own -- a token he redeems, a signed nonce, or a
-- confirmation arriving on the channel he already uses (his registered mobile, admin_mfa_phone).
-- Every one of those needs a secret only he holds, and inventing one and calling it authentication
-- would be exactly the shape this session has spent the day removing: a claim with no mechanism
-- behind it. It is written up for him in the hand-over instead, with the vector reproduced.
--
-- The narrower true statement, which is what the board should be read as saying: an amendment's
-- approval is now recorded only by an actor holding OWNER rights on this database, and it must name
-- an identity in the founder register. Whether the person at the keyboard was the founder is not
-- something this estate can yet prove.

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_freeze_amendment FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_freeze_amendment FROM anon, authenticated, service_role;

COMMENT ON TABLE public.phase_c_freeze_amendment IS
  'AMENDMENTS TO FROZEN PHASE C CONTRACTS. Every row was written by a migration applied as the '
  'owner; no routine in the estate writes this table. E39 revoked INSERT/UPDATE/DELETE from '
  'service_role, anon, authenticated and PUBLIC after an acceptance auditor, holding only '
  'service_role, approved all four rows by typing the founder''s registered email -- and separately '
  'inserted an amendment born approved, and deleted all four. E36''s trigger still requires the '
  'approver to resolve to an active founder identity, and fn_phase_c_freeze_drift re-resolves it on '
  'every read (E38). What NONE of that establishes is that the person at the keyboard was the '
  'founder: fn_phase_c_require_founder takes a caller-supplied string, and it also gates '
  'fn_refund_decide. That binding is an open item for the founder, recorded rather than papered over.';
