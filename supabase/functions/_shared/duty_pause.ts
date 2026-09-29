// ONE PAUSE SWITCH FOR EVERY DUTY (it_engineer, 29 Sep 2026).
//
// Before this, a duty had no real pause: the Twilio key rotation (resilience_ping step rotate_by_api) could only
// be stopped by deploying code, because its one gate is fn_it_provider_rotation_claim reading its own history.
// seat_duty.enabled stops a SQL duty but only one that has a seat_duty row, and no edge-function step has one.
//
// public.duty_pause (scripts/sql/every_duty_runner_honours_one_pause_switch.sql) holds one row per paused duty,
// with the reason and who paused it. Every runner reads it once per tick and skips what it names:
//   resilience_ping plan steps          'resilience_ping.<step>'      e.g. resilience_ping.launchpath
//   resilience_ping later-duty steps    'resilience_ping.<step>'      e.g. resilience_ping.rotate_by_api
//   marketing duties                    'marketing.<duty>'            e.g. marketing.geo_audit
//   seat_duty (fn_seat_duties_tick)     the seat_duty.duty name       e.g. it_engineer.latency_slo
// Pause:  insert into public.duty_pause (duty, reason, paused_by) values ('resilience_ping.rotate_by_api', '<why>', '<seat>');
// Resume: delete from public.duty_pause where duty = 'resilience_ping.rotate_by_api';
// scripts/checks/every_duty_runner_honours_the_pause.test.mjs fails if a runner stops reading it.
//
// A failed read pauses NOTHING (the runner does what it did before this file existed) and says so in `error`,
// so a broken table can never silently stop the company's duties.

// deno-lint-ignore no-explicit-any
type Admin = any;

export type Paused = { has: (duty: string) => boolean; error: string | null };

export async function pausedDuties(admin: Admin): Promise<Paused> {
  try {
    const { data, error } = await admin.from('duty_pause').select('duty').limit(1000);
    if (error) return { has: () => false, error: 'duty_pause unreadable: ' + error.message };
    const set = new Set(((data ?? []) as { duty: string }[]).map((r) => r.duty));
    return { has: (d) => set.has(d), error: null };
  } catch (e) {
    return { has: () => false, error: 'duty_pause unreadable: ' + String((e as Error)?.message || e) };
  }
}

export const PAUSED = { paused: true, reason: 'public.duty_pause names this duty' };
