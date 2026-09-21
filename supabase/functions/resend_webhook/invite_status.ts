// What a Resend delivery event makes of a supplier lead's invite_status (22 Sep 2026, customer_support).
//
// MEASURED: a spam complaint used to be written as invite_status = 'bounced', so the complaint rate —
// the number Gmail and Yahoo reject bulk senders on above 0.3% — could not be measured at all, and a
// complaint was counted as a bounce by the bounce brake. The two are different failures with different
// thresholds; fn_invite_ramp and v_invite_deliverability_daily read them separately.
export type InviteOutcome = 'complained' | 'bounced' | null;

export function inviteStatusFor(isComplaint: boolean, isHardBounce: boolean): InviteOutcome {
  if (isComplaint) return 'complained';
  if (isHardBounce) return 'bounced';
  return null;
}
