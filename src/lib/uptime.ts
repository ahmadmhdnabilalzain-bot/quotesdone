// The uptime SLI, in one place. The Vercel cron /api/resilience-ping checks every public origin every
// 15 minutes and writes one edge_health_probe row per origin (fn_key 'uptime:<url>'); the hourly
// seat_duty it_engineer.uptime_slo (scripts/sql/the_it_engineer_holds_the_public_site_to_its_uptime_target.sql)
// computes the same ratio in SQL. This file is the reference the test pins; keep the two in step.
//
// 99.9% is the job description's number. 30 days at one check per 15 minutes is 2,880 slots, so the
// budget is 2.88 failed slots: 2 is within target, 3 is a breach.
export const UPTIME_TARGET = 0.999;
export const UPTIME_MIN_SAMPLES = 96; // one day of 15-minute checks before a verdict is given

export function uptimeVerdict(up: number, total: number, target = UPTIME_TARGET) {
  if (total < UPTIME_MIN_SAMPLES) return { ratio: null, breach: false, measured: false };
  const ratio = up / total;
  return { ratio, breach: ratio < target, measured: true };
}

/** A public URL is up when it answers below 400 (a redirect between our own origins is fine). */
export const isUp = (status: number) => status > 0 && status < 400;
