// verify_exception_window.mjs — the 14-day licence exception, start to finish.
//
// A supplier whose trade licence cannot be read is not rejected. The licence gate puts them in
// `action_required`, an exception opens, they are reminded on days 3, 7 and 12, and if nothing
// arrives by day 14 the registration closes itself. Upload a readable licence at any point and the
// account activates with no approval queue — including AFTER the automatic rejection.
//
// None of that had ever run. Staging has 0 cron jobs by design, so `fn_supplier_exception_sweep` —
// the thing that sends every reminder and performs every auto-rejection — had never been called
// there, and production has 0 suppliers in the state to call it on.
//
// The whole lifecycle is driven by clock arithmetic against `exception_opened_at` and
// `exception_due_at`, so it is tested by BACK-DATING those columns rather than by waiting two weeks.
// That is legitimate here: the sweep reads no other clock. Note the 48-hour throttle — reminder 2
// needs `exception_last_reminder_at` moved back as well, which is exactly the kind of thing a test
// that only back-dates `opened_at` would pass while the real cron quietly sent one reminder.
//
// Zero model calls. Everything is SQL through the deployed functions.
//
//     node scripts/staging/verify_exception_window.mjs
import { mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { REF, withRun, makeLicenceGatedSupplier, num, q } from './demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(50)} ${detail}`);
};
const one = async (sql) => (await mgmtRead(REF, sql))[0];
const lead = (id) => one(`select approval_status, licence_gate_reason, exception_opened_at,
    exception_due_at, exception_reminders, exception_last_reminder_at, exception_closed_at,
    exception_outcome, rejection_reason, founding_rank, subscription_exempt, verified
  from public.leads where id=${num(id)}`);

// Move the whole exception back in time by N days. The sweep compares against opened_at and due_at
// only, so this is the same as waiting.
const backdate = (id, days) => mgmtWrite(REF,
  `update public.leads
      set exception_opened_at = exception_opened_at - make_interval(days => ${Number(days)}),
          exception_due_at    = exception_due_at    - make_interval(days => ${Number(days)}),
          exception_last_reminder_at = case when exception_last_reminder_at is null then null
            else exception_last_reminder_at - make_interval(days => ${Number(days)}) end
    where id=${num(id)}`, 'backdate exception');

const sweep = async () => JSON.parse(JSON.stringify(
  (await mgmtRead(REF, 'select public.fn_supplier_exception_sweep() s'))[0].s));

await withRun(async (run) => {
  const WINDOW = Number((await one('select public.fn_supplier_exception_days() d')).d);
  step('the exception window is configured', WINDOW > 0, `${WINDOW} days`);

  // ---- 1. refused by the gate ------------------------------------------------------------------
  const s = await makeLicenceGatedSupplier(run, { trade: 'steel' });
  step('a licence the gate cannot read lands in action_required',
    s.approval_status === 'action_required' && !!s.licence_gate_reason,
    `approval_status=${s.approval_status} reason="${String(s.licence_gate_reason).slice(0, 70)}…"`);

  // ---- 2. the exception opens ------------------------------------------------------------------
  const opened = (await one(`select public.fn_supplier_exception_open(${num(s.leadId)},
    'A trade licence is on file but no licence number could be read from it.') o`)).o;
  let l = await lead(s.leadId);
  const dueDays = Math.round(
    (new Date(l.exception_due_at) - new Date(l.exception_opened_at)) / 86400000);
  step(`the exception opens with a ${WINDOW}-day clock`,
    opened.ok === true && dueDays === WINDOW && Number(l.exception_reminders) === 0,
    `due ${dueDays} day(s) after opening, reminders=${l.exception_reminders}`);

  // Re-opening must NOT restart the clock - a supplier who uploads a second unreadable copy would
  // otherwise reset their own deadline indefinitely.
  const again = (await one(`select public.fn_supplier_exception_open(${num(s.leadId)}, 'second bad copy') o`)).o;
  const l2 = await lead(s.leadId);
  step('a repeat failure does not restart the clock',
    again.reopened === false && l2.exception_due_at === l.exception_due_at,
    `reopened=${again.reopened}, due_at unchanged=${l2.exception_due_at === l.exception_due_at}`);

  // ---- 3. the reminders at 3, 7 and 12 days ----------------------------------------------------
  const sweepAt = async (day, expectReminders) => {
    await backdate(s.leadId, day);
    const r = await sweep();
    const row = await lead(s.leadId);
    const notes = Number((await one(
      `select count(*)::int n from public.notifications
        where lead_id=${num(s.leadId)} and type='supplier_exception_reminder'`)).n);
    step(`day ${day}: a reminder goes out`,
      r.reminded === 1 && Number(row.exception_reminders) === expectReminders && notes === expectReminders,
      `sweep reminded=${r.reminded}, reminders=${row.exception_reminders}, ` +
      `queued notifications=${notes}`);
    return row;
  };
  await sweepAt(3, 1);
  // +4 more days reaches day 7. Back-dating also moves last_reminder_at, which is what clears the
  // 48-hour throttle - without that the second reminder never fires.
  await sweepAt(4, 2);
  await sweepAt(5, 3);   // day 12

  const quiet = await sweep();
  step('a fourth reminder is not sent',
    quiet.reminded === 0 && quiet.auto_rejected === 0,
    `sweep reminded=${quiet.reminded} auto_rejected=${quiet.auto_rejected} — 3 is the whole ladder`);

  // ---- 4. expiry -> automatic rejection ---------------------------------------------------------
  await backdate(s.leadId, 3);   // day 15, past the 14-day due date
  const expired = await sweep();
  l = await lead(s.leadId);
  const actions = Number((await one(
    `select count(*)::int n from public.agent_actions
      where target_table='leads' and target_id=${q(String(s.leadId))}
        and kind='supplier_exception_expired'`)).n);
  const closeMail = Number((await one(
    `select count(*)::int n from public.notifications
      where lead_id=${num(s.leadId)} and type='supplier_exception_expired'`)).n);
  step('past the due date the registration closes itself',
    expired.auto_rejected === 1 && l.approval_status === 'rejected'
      && l.exception_outcome === 'expired_auto_rejected' && !!l.exception_closed_at,
    `auto_rejected=${expired.auto_rejected} status=${l.approval_status} ` +
    `outcome=${l.exception_outcome}`);
  step('the closure is explained to the supplier and recorded for the founder',
    closeMail === 1 && actions === 1 && String(l.rejection_reason || '').includes(String(WINDOW)),
    `${closeMail} closure email, ${actions} agent_actions row, ` +
    `reason="${String(l.rejection_reason || '').slice(0, 60)}…"`);

  // A rejected supplier must be invisible to matching.
  const matchable = (await one(`select public.fn_is_matchable(verified, banned, matching_blocked,
      approval_status, permanently_closed, chat_strikes) m from public.leads where id=${num(s.leadId)}`)).m;
  step('an auto-rejected supplier cannot be matched', matchable === false,
    `fn_is_matchable=${matchable} with approval_status=${l.approval_status}`);

  // ---- 5. recovery AFTER the automatic rejection -------------------------------------------------
  // fn_leads_licence_gate_rerun is BEFORE UPDATE OF the three licence columns, so uploading a
  // readable licence reactivates the account with no approval queue - the founder's stated policy.
  await mgmtWrite(REF,
    `update public.leads
        set license_doc_path = 'supplier-docs/demo/${run.tag}/licence-clean.pdf',
            trade_license_no = '1145872',
            license_expiry   = date '2027-03-13'
      where id=${num(s.leadId)}`, 'upload readable licence');
  l = await lead(s.leadId);
  step('uploading a readable licence reactivates it with no approval queue',
    l.approval_status === 'approved' && l.exception_outcome === 'recovered_after_auto_reject'
      && !l.licence_gate_reason,
    `status=${l.approval_status} outcome=${l.exception_outcome} ` +
    `gate_reason=${l.licence_gate_reason ?? 'cleared'}`);

  // ---- 6. the founding cohort --------------------------------------------------------------------
  const limit = Number((await one(
    "select coalesce(nullif(btrim(value),'')::int, 1000) v from public.app_secrets where key='founding_free_limit'"))?.v ?? 1000);
  step('a verified supplier is ranked into the founding cohort',
    Number.isFinite(Number(l.founding_rank)) && Number(l.founding_rank) > 0
      && l.subscription_exempt === (Number(l.founding_rank) <= limit),
    `founding_rank=${l.founding_rank}, free limit ${limit}, ` +
    `subscription_exempt=${l.subscription_exempt} (rank <= limit is ${Number(l.founding_rank) <= limit})`);

  // The exemption is stamped once and never recalculated, so a second verification must not move it.
  await mgmtWrite(REF, `update public.leads set verified=true where id=${num(s.leadId)}`, 'reverify');
  const l3 = await lead(s.leadId);
  step('the founding rank is stamped once and never recalculated',
    String(l3.founding_rank) === String(l.founding_rank),
    `rank ${l.founding_rank} -> ${l3.founding_rank} after a second verification`);
});

const pass = checks.filter((c) => c.ok).length;
console.log(`\nEXCEPTION WINDOW ${pass}/${checks.length} on ${REF} (zero spend)`);
process.exitCode = pass === checks.length ? 0 : 1;
