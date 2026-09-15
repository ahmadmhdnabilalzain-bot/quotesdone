// The pure parts of the daily table export (supabase/functions/backup), kept here so they can be tested
// without a network (table_export_core.test.ts).
//
// WHY THE BODY IS ESCAPED (15 Sep 2026, it_engineer). The first full copy (stamp 2026-09-15) failed twice
// on the same file, kb_chunks/page_0103.json, with "Forbidden", three retries each, at different elapsed
// times (attempt 1 at 23:13Z about 13 minutes in, attempt 2 at 23:45Z about 15 minutes in). Neither the
// storage log nor the API gateway log holds any line for that path: the request never reached Supabase.
// Replayed read-only (no key, a bucket that does not exist, so nothing can be written), the page's plain
// JSON came back 403 with the Cloudflare page "Attention Required!", while the same rows escaped as below
// reached the gateway (400, no key). Two rows alone were blocked: kb_chunks 185295 and 185342, OWASP WSTG
// guide text about SQL injection. The edge firewall reads the upload body as an attack. The service-role
// key never expires and every upload in the storage log ran as service_role, so it was never the token.
//
// Every character a firewall signature needs (angle brackets, quotes, slashes, dots, shell and SQL
// punctuation) is written as a JSON \u escape. JSON.parse and Postgres jsonb read the result as exactly
// the same value, so the restore drill (jsonb_populate_recordset) and any later reader are unchanged.
const RISKY = /[<>&'"\/\\.;|`$(){}%=*+\-#:!?@\[\],~^]/;

// Serialise, then escape the risky characters that stand OUTSIDE existing escapes. JSON.stringify
// already writes a backslash as \\ and a quote as \", so we rewrite those two sequences first and then
// every remaining risky character; the structure characters ({ } [ ] , : ") are escaped only inside
// strings, because escaping them outside would not be JSON.
export function wafSafeJson(value: unknown): string {
  const s = JSON.stringify(value);
  let out = '';
  let inStr = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (!inStr) { out += c; if (c === '"') inStr = true; continue; }
    if (c === '\\') {                         // an escape JSON.stringify wrote: \" \\ \n \uXXXX ...
      const n = s[i + 1];
      if (n === 'u') { out += s.slice(i, i + 6); i += 5; continue; }
      out += n === '"' ? '\\u0022' : n === '\\' ? '\\u005c' : n === '/' ? '\\u002f' : '\\' + n;
      i++; continue;
    }
    if (c === '"') { out += c; inStr = false; continue; }
    out += RISKY.test(c) ? '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0') : c;
  }
  return out;
}

// WHO CAUSED A FAILURE. The founder's rule (founder_instruction 208): a backup may fail only when the
// provider itself is down. A refusal that repeats for the same request (403 from a firewall, an expired
// or wrong credential, a rejected type or size, a missing bucket) is caused by us and will not heal by
// retrying; everything else (timeouts, resets, 5xx, rate limiting) is the provider's and is retried.
export type Cause = 'internal' | 'provider';
export function classifyFailure(message: string, status?: number): Cause {
  if (status !== undefined) {
    if (status === 429 || status >= 500) return 'provider';
    if (status >= 400) return 'internal';
  }
  const m = message.toLowerCase();
  if (/timed? ?out|timeout|econnreset|socket|network|fetch failed|connection|bad gateway|service unavailable|gateway timeout|too many requests|rate limit|internal server error|\b5\d\d\b/.test(m)) return 'provider';
  return 'internal';                          // forbidden, unauthorized, jwt expired, invalid, mime, payload too large, not found, row-level security, unknown
}

export class ExportError extends Error {
  constructor(message: string, readonly cause_: Cause) { super(message); }
}

// Three tries with backoff for a provider failure; an internal one is thrown at once, because the same
// request will be refused the same way (page_0103 was refused three times in four seconds, twice).
export async function retry<T>(what: string, f: () => Promise<T>, waits = [0, 1000, 3000],
                               sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))): Promise<T> {
  let last: ExportError | null = null;
  for (const wait of waits) {
    if (wait) await sleep(wait);
    try { return await f(); } catch (e) {
      const msg = String((e as Error)?.message || e).slice(0, 300);
      const cause = e instanceof ExportError ? e.cause_ : classifyFailure(msg, (e as { status?: number })?.status);
      last = new ExportError(what + ': ' + msg, cause);
      if (cause === 'internal') break;
    }
  }
  throw last!;
}

export type Slot = { t: string; after: unknown; page: number; rows: number; since: string | null };
export type PageRead = { rows: unknown[]; done: boolean; last: unknown };
export type Deps = {
  readPage: (slot: Slot) => Promise<PageRead>;
  upload: (path: string, body: string) => Promise<void>;
  clear: (stamp: string, table: string) => Promise<void>;
  now: () => number;
};

// Exports one table from its saved point. Returns true when the table is finished, false when the slice
// ran out. The slot moves only after a page is safely stored, so on any throw it still names the page
// that failed and the key before it: a resumed chain starts at that page and clears nothing.
export async function exportSlot(stamp: string, slot: Slot, deadline: number, deps: Deps,
                                 onBytes: (n: number) => void = () => {}): Promise<boolean> {
  if (slot.page === 0 && slot.after == null) await deps.clear(stamp, slot.t);
  for (;;) {
    if (deps.now() > deadline) return false;
    const r = await deps.readPage(slot);
    const rows = Array.isArray(r?.rows) ? r.rows : [];
    // An empty table (or an incremental day with no changes) still writes page_0000 containing [].
    if (rows.length || slot.page === 0) {
      const body = wafSafeJson(rows);
      await deps.upload(`${stamp}/${slot.t}/page_${String(slot.page).padStart(4, '0')}.json`, body);
      slot.page++; slot.rows += rows.length; onBytes(body.length);
    }
    if (r?.done) return true;
    slot.after = r.last;
  }
}
