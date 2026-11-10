// ONE READY INTAKE POSTS ONE REQUEST (sales_engineer, customer-journey audit 10 Nov 2026).
//
// create_inquiry posts only from a server-side inquiry_intake row that is 'ready' (the intake gate). MEASURED on
// origin/main: it READ the row's status, inserted the request(s), matched and invited suppliers, and only then marked
// the intake 'consumed' — for a request split per trade, after every child had been matched and its suppliers e-mailed,
// which is the slowest call the portal makes. Until that last write the same intake still read 'ready', so a second
// post of it (a second tab, or Send pressed again after the portal's 30 s timeout while the first call was still
// matching) passed the gate and posted the whole request again: every supplier invited twice. NewRequest's ref guard
// stops a double tap on one page and names "the server's guard on intake_id" as the backstop; this is that backstop.
//
// The intake is now CLAIMED first, by one conditional write the database decides (ready -> consumed, only while still
// ready): of two posts, exactly one gets the row. A post that loses is told the request was already sent. A post that
// claims and then fails to save hands the intake back ('consumed' -> 'ready'), so "Nothing was sent, please try again"
// stays true. prevented by: supabase/functions/customer_api/intake_claim.test.ts
// deno-lint-ignore no-explicit-any
type Admin = { from: (t: string) => any };

/** Take the ready intake for this post. True for exactly one caller; false when it was already taken (or unreadable). */
export async function claimIntake(admin: Admin, id: string, email: string): Promise<boolean> {
  try {
    const { data, error } = await admin.from('inquiry_intake').update({ status: 'consumed', updated_at: new Date().toISOString() })
      .eq('id', id).eq('email', email).eq('status', 'ready').select('id');
    return !error && Array.isArray(data) && data.length === 1;
  } catch (_e) { return false; }
}

/** Hand a claimed intake back after a post that saved nothing, so the customer can press Send again. */
export async function releaseIntake(admin: Admin, id: string): Promise<void> {
  try { await admin.from('inquiry_intake').update({ status: 'ready' }).eq('id', id).eq('status', 'consumed'); } catch (_e) { /* the post already failed; it says so */ }
}
