// _shared/case_promises.ts — every promise a case records gets a due time (customer_support, 11 Nov 2026; ruling 1635).
//
// The summary step (support_case_memory.ts summariseExchange) already keeps only promises our reply or the earlier summary
// stated, and keeps a date only when we said it. This module turns each kept promise into what the promise ledger
// (public.support_case_promise, scripts/sql/every_promise_a_case_records_is_kept_or_its_seat_is_told_before_it_is_due.sql)
// stores: when it is due, read by CODE from the words we used, and the wording the case already recorded it in.
//   * dueFrom: "by Thursday", "tomorrow", "within 24 hours", "3-5 working days", "14 Nov", "2026-11-14" ... are dates and
//     numbers, read deterministically in Dubai time (UTC+4, no daylight saving; the UAE week is Monday to Friday). A day
//     with no time is due at the close of business, 18:00. Words it cannot read give null: the SQL then gives the promise
//     support_promise_undated_hours (default 48) from when it was made, and records the due date as 'assumed'.
//   * carryWording: the model rewrites the summary after each exchange and may reword a promise it already holds; the
//     earlier wording (and its date) is kept when most of the words match, so one promise stays one ledger row.
// prevented by: _shared/case_promises.test.ts
import type { CaseSummary } from './support_case_memory.ts';

export type PromiseKind = 'quotes' | 'other';
export interface StampedPromise { what: string; by: string | null; kind: PromiseKind; due_at: string | null }

const DUBAI_MS = 4 * 3600_000;
const CLOSE_HOUR = 18;
const DAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const DAYS_AR = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/** A Dubai wall-clock moment as a real instant. */
const dubai = (y: number, m: number, d: number, h = CLOSE_HOUR, min = 0) => new Date(Date.UTC(y, m, d, h, min) - DUBAI_MS);
/** The Dubai calendar day of an instant. */
function local(t: Date) { const x = new Date(t.getTime() + DUBAI_MS); return { y: x.getUTCFullYear(), m: x.getUTCMonth(), d: x.getUTCDate(), dow: x.getUTCDay(), h: x.getUTCHours() }; }
const addDays = (t: Date, n: number) => new Date(t.getTime() + n * 86_400_000);
const weekend = (dow: number) => dow === 0 || dow === 6;

/** "10am", "4:30 pm", "16:00" -> [hour, minute] in the day named elsewhere, or null. */
function timeOf(s: string): [number, number] | null {
  const ap = /\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b/.exec(s);
  if (ap) { let h = Number(ap[1]) % 12; if (ap[3] === 'pm') h += 12; return [h, Number(ap[2] ?? 0)]; }
  const hm = /\b([01]?\d|2[0-3]):([0-5]\d)\b/.exec(s);
  return hm ? [Number(hm[1]), Number(hm[2])] : null;
}

/** When a promise worded `by` (our own words) is due, made at `madeAt`. null when the words name no time. */
export function dueFrom(by: string | null | undefined, madeAt: Date): Date | null {
  const s = String(by ?? '').toLowerCase().replace(/\s+/g, ' ').trim();
  if (!s) return null;
  const now = local(madeAt);
  const at = (y: number, m: number, d: number) => { const t = timeOf(s); return t ? dubai(y, m, d, t[0], t[1]) : dubai(y, m, d); };
  // 2026-11-14 (with an optional time)
  const iso = /\b(20\d\d)-(\d\d)-(\d\d)\b/.exec(s);
  if (iso) return at(Number(iso[1]), Number(iso[2]) - 1, Number(iso[3]));
  // within / in N minutes, hours, days, working days (a range "3-5" reads its upper bound: the promise is kept by then)
  const span = /\b(?:\d+\s*(?:-|to|–)\s*)?(\d+)\s*(minutes?|mins?|hours?|hrs?|h|business days?|working days?|days?|weeks?)\b/.exec(s);
  if (span) {
    const n = Number(span[1]); const u = span[2];
    if (/^min/.test(u)) return new Date(madeAt.getTime() + n * 60_000);
    if (/^(hour|hr|h$)/.test(u)) return new Date(madeAt.getTime() + n * 3600_000);
    if (/^week/.test(u)) return new Date(madeAt.getTime() + n * 7 * 86_400_000);
    if (/^(business|working)/.test(u)) {
      let t = madeAt; let left = n;
      while (left > 0) { t = addDays(t, 1); if (!weekend(local(t).dow)) left--; }
      const l = local(t); return dubai(l.y, l.m, l.d);
    }
    return new Date(madeAt.getTime() + n * 86_400_000);
  }
  if (/\b(today|tonight|end of (the )?day|eod|this evening|this afternoon)\b|اليوم|الليلة/.test(s)) {
    const d = at(now.y, now.m, now.d);
    return d.getTime() > madeAt.getTime() ? d : dubai(now.y, now.m, now.d, 23, 59);
  }
  if (/\btomorrow\b|غدا|غداً|بكرة|بكره/.test(s)) { const l = local(addDays(madeAt, 1)); return at(l.y, l.m, l.d); }
  if (/\b(end of (the|this) week|this week)\b/.test(s)) {
    const ahead = (5 - now.dow + 7) % 7; const l = local(addDays(madeAt, ahead)); return dubai(l.y, l.m, l.d);
  }
  // 14 Nov / Nov 14 / 14 November 2026
  const dm = /\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:\s+(20\d\d))?\b/.exec(s)
    ?? /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(20\d\d))?\b/.exec(s);
  if (dm) {
    const [day, mon, yr] = /^\d/.test(dm[1]) ? [Number(dm[1]), dm[2], dm[3]] : [Number(dm[2]), dm[1], dm[3]];
    const m = MONTHS.indexOf(mon.slice(0, 3));
    let y = yr ? Number(yr) : now.y;
    if (!yr && (m < now.m || (m === now.m && day < now.d))) y++;
    return at(y, m, day);
  }
  // a weekday: its next occurrence; the same day counts while it is still before the close of business
  const w = DAYS.findIndex((d) => new RegExp('\\b' + d + '\\b').test(s));
  const wa = DAYS_AR.findIndex((d) => s.includes(d));
  const dow = w >= 0 ? w : wa;
  if (dow >= 0) {
    let ahead = (dow - now.dow + 7) % 7;
    if (ahead === 0 && now.h >= CLOSE_HOUR) ahead = 7;
    const l = local(addDays(madeAt, ahead)); return at(l.y, l.m, l.d);
  }
  const t = timeOf(s);
  if (t) { const d = dubai(now.y, now.m, now.d, t[0], t[1]); return d.getTime() > madeAt.getTime() ? d : addDays(d, 1); }
  return null;
}

const words = (s: string) => new Set(String(s).toLowerCase().match(/[\p{L}\p{N}]{3,}/gu) ?? []);
const overlap = (a: string, b: string) => { const x = words(a); const y = words(b); if (!x.size || !y.size) return 0; let n = 0; for (const w of x) if (y.has(w)) n++; return n / Math.min(x.size, y.size); };

/** The promises the summary text already lists ("WE PROMISED:" lines, as renderSummary writes them). */
export function recordedPromises(summaryText: string | null | undefined): { what: string; by: string | null }[] {
  const block = /WE PROMISED:\n([\s\S]*?)(?:\n[A-Z][A-Z ]+:|$)/.exec(String(summaryText ?? ''))?.[1] ?? '';
  return block.split('\n').map((l) => l.replace(/^-\s*/, '').trim()).filter((l) => l && l !== 'nothing')
    .map((l) => { const m = /^(.*?)\s*\(by ([^)]+)\)$/.exec(l); return m ? { what: m[1], by: m[2] } : { what: l, by: null }; });
}

/** A reworded promise the case already holds keeps its recorded wording and date. */
export function carryWording<P extends { what: string; by: string | null }>(promised: P[], previousText: string | null | undefined): P[] {
  const before = recordedPromises(previousText);
  return promised.map((p) => {
    const was = before.find((b) => b.what === p.what) ?? before.find((b) => overlap(b.what, p.what) >= 0.75);
    return was ? { ...p, what: was.what, by: p.by ?? was.by } : p;
  });
}

/** The summary as the ledger needs it: every promise with its kind and its due time (ISO, or null for 'assumed'). */
export function stampPromises(s: CaseSummary, o: { previousText?: string | null; madeAt?: Date } = {}): CaseSummary {
  const madeAt = o.madeAt ?? new Date();
  const promised = carryWording(s.promised, o.previousText).map((p) => {
    const due = dueFrom(p.by, madeAt);
    return { ...p, kind: (p.kind === 'quotes' ? 'quotes' : 'other') as PromiseKind, due_at: due ? due.toISOString() : null };
  });
  return { ...s, promised };
}
