// WHICH SEAT AN APPLY IS MADE FOR (22 Sep 2026, it_engineer).
//
// routine_change_log keeps application_name for every routine change, and scripts/apply_sql.mjs signs it
// 'qd-apply <rev> <worktree> <file>'. That named the commit and the folder but never the seat, so on
// 22 Sep the two open duty:unsigned_revision findings (2d34c4a, 59a3de8 -- PR #834, applied 10:54Z and
// 10:59Z from worktree agent-a3466b29cc207b137) could only be attributed by opening the pull request.
// Every branch and every commit in this repository starts with the seat that owns it (the founder's
// rule of 7 Sep: "every change names its agent"), so the apply reads it from there, and refuses to
// write to production when neither says.
//
// Order: an explicit --seat, then the branch prefix ('it_engineer/...'), then the commit subject prefix
// ('it_engineer: ...', or the first seat of 'sales_engineer + it_engineer: ...').
export const SEATS = ['ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing'];

const known = (s) => (SEATS.includes(s) ? s : null);

export function seatFor({ flag = null, branch = '', subject = '' } = {}) {
  if (flag) return known(String(flag).trim());
  return known(String(branch).split('/')[0].trim())
    || known((String(subject).match(/^([a-z_]+)[\s:+]/) || [])[1] || '');
}
