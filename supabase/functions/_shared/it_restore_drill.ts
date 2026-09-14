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

// deno-lint-ignore no-explicit-any
export async function runRestoreTable(admin: Storage, pick: any) {
  const out: Record<string, unknown> = { taken_at: new Date().toISOString(), newest_export_day: pick?.newest_export_day ?? null, table: null };
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
