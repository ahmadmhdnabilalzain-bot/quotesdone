// accountant — one book read as a measurement: true_zero, measured or unknown, with its observed window.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
import { admin } from '../context.ts';


// THREE DIFFERENT FACTS PRINT AS THE CHARACTER 0 ON THIS DATABASE, and the accountant grant says so
// in its own words: "An unmeasurable figure is reported as unknown, never estimated and never
// defaulted to zero." So a book is read as:
//
//   true_zero  — the table was read, it holds no rows, and the window it holds no rows over is
//                stated. This is a measurement, and it is the answer for gl_journal, expenses and
//                ap_bills today.
//   measured   — the table was read and holds rows, with the observed date window.
//   unknown    — the table could not be read (absent, or the read errored). The count is null, NOT
//                0, because "we could not look" and "we looked and found nothing" are different
//                facts and only one of them is evidence.
//
// The window is the OBSERVED extent of the date column, not a requested filter: nothing here
// filters by date, so claiming a 30-day window would be describing a query that was never run.
export async function book(table: string, dateCol: string | null): Promise<Record<string, unknown>> {
  const { count, error } = await admin.from(table).select('*', { count: 'exact', head: true });
  if (error) {
    return { table, basis: 'unknown', rows: null, window: null, reason: error.message };
  }
  const rows = count ?? 0;
  if (!dateCol) return { table, basis: rows ? 'measured' : 'true_zero', rows, window: null };
  if (!rows) {
    return {
      table, basis: 'true_zero', rows: 0,
      window: { column: dateCol, from: null, to: null, note: 'no rows at all, so the window is the whole table and it is empty' },
    };
  }
  const [lo, hi] = await Promise.all([
    admin.from(table).select(dateCol).order(dateCol, { ascending: true }).limit(1).maybeSingle(),
    admin.from(table).select(dateCol).order(dateCol, { ascending: false }).limit(1).maybeSingle(),
  ]);
  // The column is chosen at runtime, so postgrest-js types the row as a union it cannot narrow.
  // deno-lint-ignore no-explicit-any
  const pick = (r: any) => (r?.data ? (r.data as Record<string, unknown>)[dateCol] ?? null : null);
  return { table, basis: 'measured', rows, window: { column: dateCol, from: pick(lo), to: pick(hi) } };
}
