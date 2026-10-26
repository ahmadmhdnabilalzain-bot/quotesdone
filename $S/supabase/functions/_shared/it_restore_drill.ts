// The IT engineer's monthly table restore drill (duty 19; founder, 14 Sep 2026: "add all for accountant and IT").
// This module only DOWNLOADS and OPENS; public.fn_it_restore_table_record restores the rows into a scratch
// table and decides (scripts/sql/the_it_engineer_restores_a_table_sample_every_month.sql). No model call.
// opensAs is also what duty 9's file sample uses to say a restored copy opens (_shared/it_scheduled_readings.ts).
// A part that could not be done says why in an `error` field; it is never left out.

// Only the one call this module makes, so it takes any supabase-js client without importing its types.
type Storage = { storage: { from(bucket: string): { download(path: string): Promise<{ data: Blob | null; error: { message: string } | null }> } } };
const text = (b: Uint8Array) => new TextDecoder().decode(b);

// Whether restored bytes open as what their name says: a PDF starts %PDF- and ends %%EOF (a truncated
// download or an error page saved under a .pdf name fails); JSON parses; anything else must not be empty.
export function opensAs(path: string, b: Uint8Array): boolean {
  if (!b.length) return false;
  if (/\.pdf$/i.test(path)) return text(b.subarray(0, 5)) === '%PDF-' && text(b.subarray(Math.max(0, b.length - 1024))).includes('%%EOF');
  if (/\.json$/i.test(path)) { try { JSON.parse(text(b)); return true; } catch { return false; } }
  return true;
}

// The dated exports are a list of rows; a wrapper object with a rows/data/records list is accepted too.
export function rowsOf(parsed: unknown): unknown[] | null {
  if (Array.isArray(parsed)) return parsed;
  const o = (parsed ?? {}) as Record<string, unknown>;
  for (const k of ['rows', 'data', 'records']) if (Array.isArray(o[k])) return o[k] as unknown[];
  return null;
}

// THE CHAIN (18 Sep 2026, founder instruction 519). The drill used to download ONE full-copy page and
// skip every 'changes_since' page, so the incremental half of the backup was checked for gaps and never
// once replayed. It now also downloads, for one change-tracked table, the base page of the newest FULL
// day plus every later day's pages for that table and that day's table_export_change pages, and
// public.fn_table_export_replay rebuilds and compares them with live. Bounded: one base page (at most
// 1,000 rows) and at most six later days, because a full copy is never more than 7 days old.
// A part that could not be downloaded says so in `error` and the drill fails; it is never left out.
async function downloadRows(admin: Storage, path: string): Promise<unknown[]> {
  const { data, error } = await admin.storage.from('backups').download(path);
  if (error || !data) throw new Error(path + ': ' + (error?.message || 'object not found'));
  const rows = rowsOf(JSON.parse(await data.text()));
  if (!rows) throw new Error(path + ': the export is not a list of rows');
  return rows;
}

// deno-lint-ignore no-explicit-any
async function loadChain(admin: Storage, chain: any) {
  const out: Record<string, unknown> = { table: chain.table, full_day: chain.full_day, base: chain.base,
    increments: chain.increments ?? [], changes: chain.changes ?? [] };
  try {
    out.base_rows = await downloadRows(admin, String(chain.base));
    // each later day is applied in order, so the files stay grouped by day
    const inc: unknown[][] = [];
    for (const p of (chain.increments ?? []) as string[]) inc.push(await downloadRows(admin, p));
    out.increment_rows = inc;
    const chg: unknown[] = [];
    for (const p of (chain.changes ?? []) as string[]) chg.push(...await downloadRows(admin, p));
    out.change_rows = chg;
  } catch (e) {
    out.error = 'the chain could not be read: ' + String((e as Error)?.message || e).slice(0, 200);
  }
  return out;
}

// deno-lint-ignore no-explicit-any
export async function runRestoreTable(admin: Storage, pick: any) {
  const out: Record<string, unknown> = { taken_at: new Date().toISOString(), newest_export_day: pick?.newest_export_day ?? null, table: null };
  if (pick?.chain?.table && pick?.chain?.base) out.chain = await loadChain(admin, pick.chain);
  const t = pick?.table;
  if (!t?.table) return out;
  const base = { table: t.table, path: t.path, day: t.day };
  try {
    const { data, error } = await admin.storage.from('backups').download(t.path);
    if (error || !data) throw new Error(error?.message || 'object not found');
    const parsed = JSON.parse(await data.text());
    const rows = rowsOf(parsed);
    out.table = rows
      ? { ...base, rows_in_file: rows.length, rows: rows.slice(0, Number(pick?.sample_rows) || 50) }
      : { ...base, error: 'the export opened but is not a list of rows (top-level keys: '
          + Object.keys((parsed ?? {}) as object).slice(0, 8).join(', ') + ')' };
  } catch (e) {
    out.table = { ...base, error: 'the export could not be opened: ' + String((e as Error)?.message || e).slice(0, 200) };
  }
  return out;
}
