// workbook_remote — the workbook engine that reads in doc_extract, not here (16 Nov 2026, it_engineer).
//
// WHO USES IT. supplier_api only, registered at its entry (supplier_api/index.ts). Its upload failed 413 at 4,695,339
// bytes of local graph and SheetJS was 503,237 of them (workbook_engine.ts); with this engine SheetJS is not in its
// graph at all, and scripts/checks/every_office_reader_has_an_engine.test.mjs keeps it out.
//
// WHAT IT DOES. The bytes go, base64, to doc_extract as {__secret, op:'read_workbook' | 'read_compound_file', b64}.
// __secret is the CALLER's own credential (supplier_api: cred_fn_supplier_api), checked by doc_extract's
// requireInternal against internal_credential.scope, so that scope must name doc_extract
// (scripts/sql/the_supplier_api_reads_workbooks_through_doc_extract.sql). doc_extract reads them with the LOCAL
// engine and answers the same SheetsRead / compound-file streams workbook_local.ts would have produced here.
//
// EVERY FAILURE IS A THROW WITH A SENTENCE, which office.ts / ole.ts turn into refuse('unreadable', ...) — or
// 'encrypted' when doc_extract's reader said password — so a reader of readDocument never sees a throw:
//   more than REMOTE_READ_MAX_BYTES, or no credential        nothing is sent
//   no answer within timeoutMs (default 60 s)               'the workbook reader did not answer: <why>'
//   doc_extract's {ok:false, message}                       its message (the reader's own words)
//   any other non-2xx (401/403 credential, 5xx)             'the workbook reader answered <status>'
//   a 2xx that is not the expected shape                    'the workbook reader answered something that is not a ...'
import { decodeBase64, encodeBase64 } from 'jsr:@std/encoding@1/base64';
import { timedFetch } from '../timed_fetch.ts';
import { REMOTE_READ_MAX_BYTES, type CompoundFileRead, type SheetsRead, type WorkbookEngine } from './workbook_engine.ts';

export type RemoteEngineOptions = {
  /** SUPABASE_URL; the engine posts to <url>/functions/v1/doc_extract. */
  url: string;
  /** The calling function's own internal credential, read when a file is read (never at boot). */
  credential: () => Promise<string | null>;
  /** The caller-side deadline for one read, headers and body together (timed_fetch.ts). */
  timeoutMs?: number;
};

const DEFAULT_TIMEOUT_MS = 60_000;

export function remoteWorkbookEngine(o: RemoteEngineOptions): WorkbookEngine {
  // deno-lint-ignore no-explicit-any
  async function ask(op: 'read_workbook' | 'read_compound_file', bytes: Uint8Array): Promise<any> {
    if (bytes.length > REMOTE_READ_MAX_BYTES) throw new Error(`the file is ${bytes.length} bytes, over the ${REMOTE_READ_MAX_BYTES} bytes the workbook reader takes`);
    const secret = await o.credential();
    if (!secret) throw new Error('no credential to reach the workbook reader');
    let r: Response;
    try {
      r = await timedFetch(`${o.url}/functions/v1/doc_extract`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: secret, op, b64: encodeBase64(bytes) }),
      }, o.timeoutMs ?? DEFAULT_TIMEOUT_MS);
    } catch (e) {
      throw new Error(`the workbook reader did not answer: ${(e as Error)?.message || e}`);
    }
    const d = await r.json().catch(() => null);
    if (d?.ok === false && typeof d.message === 'string') throw new Error(d.message);
    if (!r.ok) throw new Error(`the workbook reader answered ${r.status}`);
    return d;
  }

  return {
    where: 'remote',
    async sheets(bytes: Uint8Array): Promise<SheetsRead> {
      const d = await ask('read_workbook', bytes);
      const names = d?.names, rows = d?.rows;
      if (!Array.isArray(names) || !names.every((n) => typeof n === 'string') || !Array.isArray(rows) || !rows.every((s) => s === null || Array.isArray(s))) {
        throw new Error('the workbook reader answered something that is not a workbook');
      }
      return { names, rows };
    },
    async compoundFile(bytes: Uint8Array): Promise<CompoundFileRead> {
      const d = await ask('read_compound_file', bytes);
      if (d?.entries === null) return null;
      const entries = d?.entries;
      if (!Array.isArray(entries) || !entries.every((e) => Array.isArray(e) && typeof e[0] === 'string' && typeof e[1] === 'string')) {
        throw new Error('the workbook reader answered something that is not a compound file');
      }
      return new Map(entries.map(([path, b64]: [string, string]) => [path, decodeBase64(b64)]));
    },
  };
}
