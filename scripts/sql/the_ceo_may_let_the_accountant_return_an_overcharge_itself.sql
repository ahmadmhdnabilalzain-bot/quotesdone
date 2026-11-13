-- THE CEO MAY LET THE ACCOUNTANT RETURN AN OVERCHARGE ITSELF (a DATA change, not code; waits for the founder's yes).
--
-- Assigned: ceo (the grant is the CEO's); the accountant acts under it. 13 Nov 2026, coordinator ruling R4: the founder reserved
-- refund authority (ceo_standing_grant accountant.refund_decision, max_amount_aed 0, 9 Sep 2026), so today every return of
-- money charged above the reveal fee is the CEO's decision. The coordinator recommends to the founder a standing grant for
-- this one case. When this row is active, fn_reason_apply_accountant__payment_exception returns exactly the difference
-- through fn_refund_request itself (fn_payment_check_returns_difference) and the CEO is still told; without it the
-- recommendation goes to the CEO. Nothing else changes: a refund of the FEE stays the CEO's, the cap below applies, and
-- fn_ceo_refund_approval_checks_the_process still requires the amount to be exactly what the accountant's check says.
-- The cap (AED 500) is a proposal for the founder; change the number in this file before applying, never in code.

insert into public.ceo_standing_grant (grant_key, grantee_role_id, action_class, scope_note, limit_note, max_amount_aed, issued_by, active)
values ('accountant.overcharge_return', 'accountant', 'overcharge_return',
        'Return to a customer exactly the money a reveal payment took above the 3% fee (or a second payment for the same reveal), as the accountant''s payment check measures it, through fn_refund_request.',
        'Only the difference fn_payment_check_owed_back names on that payment; never the fee itself; the CEO is told of every return.',
        500, 'ceo', true)
on conflict (grant_key) do nothing;
