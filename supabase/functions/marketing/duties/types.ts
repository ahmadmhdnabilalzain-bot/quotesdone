// The duty list's shared types (split out of duties.ts, 9 Nov 2026; a pure move).
// deno-lint-ignore no-explicit-any
export type Admin = any;
export interface DutyContext {
  admin: Admin;
  sec: (key: string) => Promise<string | undefined>;
  now: Date;
  /** The epoch ms this beat must be done by (index.ts runDuties, MARKETING_BEAT_BUDGET_MS); model calls are bounded by it. */
  deadline?: number;
}
export interface Duty {
  name: string;
  owner_seat: 'marketing';   // every duty names the seat that owns it
  run: (ctx: DutyContext) => Promise<Record<string, unknown>>;
}
