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
  // Saves the whole hop state (fn_table_export_save) before each page is read; see PAGE SIZE below.
  checkpoint?: () => Promise<void>;
};

// PAGE SIZE (15 Sep 2026, it_engineer). A page used to be a fixed 1,000 rows. The first full copy then
// died with 546 "CPU Time exceeded" on every resume at ops_knowledge page 7 (hop 865). ops_knowledge holds
// 9,140 rows; measured read-only the same day as to_jsonb text (vector columns included, which the export
// strips): the 1,000 rows from page 7 on are 21 MB, the widest row 601 kB, the widest 100 rows in a row
// 3.4 MB. A page is read, parsed, stringified and escaped whole before the 12 MB hop budget is checked. A 546 kills the worker before any catch, so
// the day never moved. Now the page's row count follows the bytes actually written:
//   * a table starts at FIRST_ROWS rows; after each stored page the next count aims at PAGE_TARGET bytes
//     of escaped output (at most double the last count, at most PAGE_ROWS, the RPC's cap);
//   * before each read the slot records `tried` = the page it is about to read and the state is saved
//     (deps.checkpoint). Every clean end of a hop clears `tried`, so a saved slot still holding
//     tried === page means the worker was killed reading or writing that page: the resume halves the
//     count (down to 1 row) and tries again. A CPU kill heals itself, one stalled heartbeat per halving.
//     A single row too wide to escape even alone keeps dying at 1 row; that is not silent: every stale
//     resume raises duty:table_export:chain_stalled (fn_table_export_due v3) naming the table and page.
// Paging is keyset on the primary key (slot.after), so page files may hold different row counts and the
// resume point stays exact: page P is always the P-th file written, starting after the saved key.
export const PAGE_ROWS = 1000;
export const FIRST_ROWS = 100;
export const PAGE_TARGET = 4_000_000;
// `max` is the row count that last survived a kill: growth never passes it again for this table, or the
// doubling would walk straight back into the page that killed the worker.
// ponytail: `max` holds for the rest of the table even past its wide rows; a byte-capped
// fn_table_export_page would lift that if a table ever needs it.
export type SizedSlot = Slot & { limit?: number; tried?: number; max?: number };
export const pageRows = (slot: Slot) => (slot as SizedSlot).limit ?? FIRST_ROWS;
export function nextRows(rows: number, bytes: number, current: number, max = PAGE_ROWS): number {
  if (rows <= 0 || bytes <= 0) return current;
  return Math.max(1, Math.min(PAGE_ROWS, max, current * 2, Math.floor(rows * PAGE_TARGET / bytes)));
}

// Exports one table from its saved point. Returns true when the table is finished, false when the slice
// ran out. The slot moves only after a page is safely stored, so on any throw it still names the page
// that failed and the key before it: a resumed chain starts at that page and clears nothing.
export async function exportSlot(stamp: string, slot: SizedSlot, deadline: number, deps: Deps,
                                 onBytes: (n: number) => void = () => {},
                                 budget: HopBudget = { spent: 0, max: Infinity }): Promise<boolean> {
  if (slot.page === 0 && slot.after == null) await deps.clear(stamp, slot.t);
  for (;;) {
    // Checked before reading the next page, after the last one is stored: the slot then names exactly
    // the next page and the key before it, so the next hop continues with no gap and no duplicate.
    if (deps.now() > deadline || budget.spent >= budget.max) return false;
    if (slot.tried === slot.page) slot.max = slot.limit = Math.max(1, Math.floor(pageRows(slot) / 2));
    slot.tried = slot.page;
    await deps.checkpoint?.();
    const r = await deps.readPage(slot);
    const rows = Array.isArray(r?.rows) ? r.rows : [];
    // An empty table (or an incremental day with no changes) still writes page_0000 containing [].
    if (rows.length || slot.page === 0) {
      const body = wafSafeJson(rows);
      await deps.upload(`${stamp}/${slot.t}/page_${String(slot.page).padStart(4, '0')}.json`, body);
      slot.page++; slot.rows += rows.length; onBytes(body.length); budget.spent += body.length;
      slot.limit = nextRows(rows.length, body.length, pageRows(slot), slot.max);
    }
    if (r?.done) return true;
    // No rows and not done: the source made no progress. End the hop now rather than re-reading the same
    // key for the rest of the 30 s; runHop's idle guard turns repeated idle hops into a failure.
    if (!rows.length) return false;
    slot.after = r.last;
  }
}

// NO-PROGRESS GUARD (15 Sep 2026, review of #689). A hop that stores nothing still counts a hop, so a
// page source that kept answering "no rows, not done" would burn every hop to MAX_HOPS (2000, ~16.7 h)
// before anything said so. After IDLE_HOPS hops in a row with no page stored and no table finished, the
// day fails with cause 'internal', naming the table and page, through the caller's settle() path. The
// count lives in the saved state (st.idle), so it survives hops and resumes; any progress resets it.
export const IDLE_HOPS = 3;
export type Failure = { table: string; error: string; cause: Cause };
export type HopState = {
  stamp: string; bytes: number; queue: SizedSlot[]; idle?: number;
  tables: Record<string, { rows: number; pages: number; mode: string }>; errors: Record<string, string>;
};

// One hop: export tables from the head of the queue until the wall clock or the byte budget ends it.
// A failing table stays at the head of the queue with its resume point, named in st.errors.
// Every way out of a hop that is not a killed worker clears `tried`, so only a kill leaves it saved.
export async function runHop(st: HopState, deps: Deps, deadline: number, budget: HopBudget): Promise<Failure | null> {
  try { return await hop(st, deps, deadline, budget); } finally { for (const s of st.queue) delete s.tried; }
}

async function hop(st: HopState, deps: Deps, deadline: number, budget: HopBudget): Promise<Failure | null> {
  const before = st.queue.length;
  while (st.queue.length && deps.now() < deadline && budget.spent < budget.max) {
    const slot = st.queue[0];
    try {
      if (!(await exportSlot(st.stamp, slot, deadline, deps, (n) => { st.bytes += n; }, budget))) break;
      st.tables[slot.t] = { rows: slot.rows, pages: slot.page, mode: slot.since ? 'changes_since ' + slot.since : 'full' };
      delete st.errors[slot.t];
    } catch (e) {
      const error = String((e as Error)?.message || e).slice(0, 300);
      const failure: Failure = { table: slot.t, error, cause: e instanceof ExportError ? e.cause_ : 'internal' };
      st.errors[slot.t] = `${failure.cause}: ${failure.error}`;
      return failure;
    }
    st.queue.shift();
  }
  st.idle = budget.spent > 0 || st.queue.length < before ? 0 : (st.idle ?? 0) + 1;
  if (st.queue.length && st.idle >= IDLE_HOPS) {
    const s = st.queue[0];
    const failure: Failure = { table: s.t, cause: 'internal',
      error: `no page stored for ${st.idle} hops in a row at page ${s.page} (after ${JSON.stringify(s.after)}): the page source returned no rows and not done` };
    st.errors[s.t] = `internal: ${failure.error}`;
    return failure;
  }
  return null;
}
