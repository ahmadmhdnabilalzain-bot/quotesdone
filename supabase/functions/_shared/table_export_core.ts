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
//
// CPU (15 Sep 2026, v2 of this function). v1 walked the JSON one character at a time in JavaScript:
// 99-331 ms per real kb_chunks page against 2-10 ms for JSON.stringify, ~10 pages a hop, and the second
// hop of backup v9 died at 00:14:39Z with "CPU Time exceeded" (546), leaving the day 'running' with no
// finding. v2 does the same rewrite with native regular expressions: each JSON string literal is found by
// an unrolled pattern (no per-character backtracking on multi-MB strings), and inside it every risky
// character becomes \uXXXX, \" \\ \/ become \u0022 \u005c \u002f, and other escapes stay as written.
// The output is byte-for-byte v1's (table_export_cpu.test.ts keeps v1 as the reference); measured on the
// same pages: 60-126 ms.
const STRING_LITERAL = /"[^"\\]*(?:\\.[^"\\]*)*"/g;
const INSIDE = /\\u[0-9a-fA-F]{4}|\\.|[<>&'\/.;|`$(){}%=*+\-#:!?@\[\],~^]/g;
const REWRITE: Record<string, string> = { '\\"': '\\u0022', '\\\\': '\\u005c', '\\/': '\\u002f' };
const escapeOne = (t: string) =>
  t[0] === '\\' ? (t[1] === 'u' ? t : REWRITE[t] ?? t) : '\\u' + t.charCodeAt(0).toString(16).padStart(4, '0');

// Only inside strings: the structure characters ({ } [ ] , : - . +) must stay raw outside them.
export function wafSafeJson(value: unknown): string {
  return JSON.stringify(value).replace(STRING_LITERAL, (m) => '"' + m.slice(1, -1).replace(INSIDE, escapeOne) + '"');
}

// A hop ends after this many bytes of escaped output as well as after the 30 s wall clock: the edge
// runtime caps CPU per request, and serialising + escaping is the CPU. ~3 kb_chunks pages (~4.3 MB each
// escaped) per hop, ~0.4 s of escaping.
export const HOP_BYTES = 12_000_000;
export type HopBudget = { spent: number; max: number };

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
                                 onBytes: (n: number) => void = () => {},
                                 budget: HopBudget = { spent: 0, max: Infinity }): Promise<boolean> {
  if (slot.page === 0 && slot.after == null) await deps.clear(stamp, slot.t);
  for (;;) {
    // Checked before reading the next page, after the last one is stored: the slot then names exactly
    // the next page and the key before it, so the next hop continues with no gap and no duplicate.
    if (deps.now() > deadline || budget.spent >= budget.max) return false;
    const r = await deps.readPage(slot);
    const rows = Array.isArray(r?.rows) ? r.rows : [];
    // An empty table (or an incremental day with no changes) still writes page_0000 containing [].
    if (rows.length || slot.page === 0) {
      const body = wafSafeJson(rows);
      await deps.upload(`${stamp}/${slot.t}/page_${String(slot.page).padStart(4, '0')}.json`, body);
      slot.page++; slot.rows += rows.length; onBytes(body.length); budget.spent += body.length;
    }
    if (r?.done) return true;
    slot.after = r.last;
  }
}
