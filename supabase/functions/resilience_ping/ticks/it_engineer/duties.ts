// resilience_ping ticks owned by the it_engineer seat: the hourly duties tick and the scheduled-cadence duties tick. Moved out of ticks/it_engineer.ts unchanged (9 Nov 2026);
// the order the steps run in is still set in resilience_ping/index.ts (STEP_RUN).
import { takeDutyReadings } from '../../../_shared/it_duty_readings.ts';
import { takeScheduledReadings } from '../../../_shared/it_scheduled_readings.ts';
import { admin, sec } from '../../shared.ts';

// THE IT ENGINEER'S ALERT HANGS HERE FOR THE SIXTH TIME, AND FOR THE SAME REASON.
// The founder, 9 Sep 2026: "once their is an issue, he will email me directly so i can open a
// session with you to fix it ... he reports to me directly only". The delivery is deterministic and
// lives entirely in Postgres (fn_it_engineer_alert_tick, scripts/sql/
// the_it_engineer_hands_the_founder_a_session_he_can_start_from.sql); this call is only the clock.
//
// IT IS SAFE TO CALL EVERY 15 MINUTES, and that is the point rather than a tolerance: dedupe is on
// the ISSUE, not on the tick, so a problem open for a week produces ONE email, and a second only
// when a fact he was already told has changed (severity rose, affected at least doubled, it closed,
// it came back). A tick with nothing to say returns sent:0 and writes nothing.
//
// IT IS THE ONE TICK HERE THAT MUST NOT BE FULLY SWALLOWED. The other five are informational -- a
// digest or a report that fails is a missing document. This one is the monitor, and a monitor that
// fails open is worse than no monitor, because zero findings then reads as a quiet night. So the
// routine itself never raises (it records partial failure into founder_alerts and returns it), and
// its result is carried in this function's response either way, so the failure is visible in the
// watchdog's own output instead of vanishing into a catch. The watchdog still cannot be taken down
// by it: an unreachable RPC returns ok:false here rather than throwing.
// THE IT ENGINEER'S DUTIES, HOURLY (founder, 14 Sep 2026: "fine add them"). The readings Postgres
// cannot take are taken here and handed to fn_it_duties, which decides; fn_it_duties_due keeps the
// HTTP calls to once an hour. Only a count is returned: this endpoint is public and the findings
// name internals. Runs before the alert tick so a new finding goes round the loop on this pass.
export async function itDutiesTick(): Promise<unknown> {
  try {
    const { data: due, error: dueErr } = await admin.rpc('fn_it_duties_due');
    if (dueErr) return { ok: false, error: dueErr.message };
    if (due !== true) return { due: false };
    const readings = await takeDutyReadings(sec);
    const { data, error } = await admin.rpc('fn_it_duties', { p_r: readings });
    if (error) return { ok: false, error: error.message };
    // The SAME readings, no second HTTP call: fn_it_duties stores only expires_on, so a provider that
    // answers "this token has no expiry at all" (Meta debug_token expires_at 0) was measured hourly and
    // dropped, and the ledger went on asking the accountant for a date that will never exist. See
    // scripts/sql/configuration_that_is_missing_is_recorded_once_not_every_tick.sql.
    const { error: expErr } = await admin.rpc('fn_it_expiry_measured', { p_expiries: readings.expiries ?? {} });
    return { due: true, duties: Object.keys((data ?? {}) as Record<string, unknown>).length,
             expiries: expErr ? { ok: false, error: expErr.message } : true };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// DUTIES 9-15 ON THEIR OWN CADENCES (founder, 14 Sep 2026: "fine build those tasks for IT agent").
// fn_it_scheduled_due names what is due; only those readings are taken; fn_it_duties_scheduled decides.
export async function itScheduledTick(): Promise<unknown> {
  try {
    const { data: due, error: dueErr } = await admin.rpc('fn_it_scheduled_due');
    if (dueErr) return { ok: false, error: dueErr.message };
    const list = (due ?? []) as string[];
    const { data: n } = await admin.rpc('fn_it_threshold', { p_key: 'restore_sample_files' });
    const readings = await takeScheduledReadings(admin as never, sec, list, Number(n) || 5);
    const { data, error } = await admin.rpc('fn_it_duties_scheduled', { p_r: readings });
    if (error) return { ok: false, error: error.message };
    // Duty 10 settles findings; this keeps the day's numbers (scripts/sql/sender_health_is_recorded_once_a_day_and_a_breach_is_named.sql).
    let senderRow: unknown = null;
    if (readings.sender) {
      const { data: row, error: rerr } = await admin.rpc('fn_it_sender_health_record', { p_sender: readings.sender });
      senderRow = rerr ? { ok: false, error: rerr.message } : { breaches: (row as { breaches?: string[] })?.breaches ?? [] };
    }
    return { due: list, settled: Object.keys((data ?? {}) as Record<string, unknown>), sender_health: senderRow };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
