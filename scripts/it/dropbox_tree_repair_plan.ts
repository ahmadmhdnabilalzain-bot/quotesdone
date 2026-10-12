// The plan of the Dropbox tree repair of 7 Oct 2026 (it_engineer verifies, sales_engineer files; founder
// gate ledger 1162). Pure: rows and a listing in, operations out, so the plan is tested without Dropbox.
// The script that reads production and (only when told) carries it out is dropbox_tree_repair.ts.
//
//   A  merge     a customer's or a request's file filed in a second folder -> the folder its first file
//                opened (the Customer Details / Inquiry Summary row)                       MOVE   (held)
//   B  ownerless a file under Storage/ whose owner row no longer exists
//                -> _archive/ownerless-<date>/<its path>                                   MOVE   (held)
//   C  demo      a file in Suppliers/ or Customers/ with no record and demo evidence in its path
//                -> _archive/demo-leftovers-<date>/<its path>                              MOVE   (held)
//   D  record    a real file in Suppliers/ or Customers/ with no record -> a doc_backups row
//                naming it (metadata only, the file is not touched)                        RECORD
// Nothing is ever deleted. Every move keeps the file's name and is checked by content_hash afterwards.

export const ROOT = '/QuotesDone Backup';
export type Row = { id: number; entity: string; entity_id: string; dropbox_path: string; dropbox_content_hash: string | null;
  dedupe_key: string; status: string; owner_exists: boolean | null;
  // the customer's NAMED folder today ('/QuotesDone Backup/Customers/<name> (<id8>)/'), null when no name is on file
  named_folder?: string | null };
export type Listed = { p: string; h: string; s: number; m?: string };
export type Move = { kind: 'merge' | 'ownerless' | 'demo'; id: number | null; from: string; to: string; hash: string | null };
export type Record_ = { kind: 'record'; path: string; hash: string; size: number; modified: string | null; entity: string; entity_ref: string };

export const DEMO_EVIDENCE = /zz[ _-]?demo|example\.invalid|\bqd[ _-]demo\b|qd_run:/i;
const key = (p: string) => p.normalize('NFC').toLowerCase();
const after = (p: string) => p.slice(ROOT.length + 1);

// The folder of an entity: the prefix its anchor row was filed under.
export function anchorPrefix(anchor: string | undefined, kind: 'customer' | 'inquiry'): string | null {
  if (!anchor) return null;
  const m = kind === 'inquiry' ? /^(\/QuotesDone Backup\/Customers\/[^/]+\/Inquiries\/[^/]+\/)/.exec(anchor)
    : /^(\/QuotesDone Backup\/Customers\/[^/]+\/)/.exec(anchor);
  return m ? m[1] : null;
}

export function plan(rows: Row[], listed: Listed[], date: string) {
  const byKey = new Map(rows.map((r) => [r.dedupe_key, r]));
  const moves: Move[] = []; const records: Record_[] = [];
  for (const r of rows) {
    if (r.status !== 'done' || r.entity === 'zz_demo') continue;
    // B: an owned file whose owner row is gone (a torn-down fixture, a deleted account), in Storage/ or in
    // the entity tree itself (12 Oct audit: 4 "Customer (<id8>)" folders of customers who no longer exist)
    if (/^\/QuotesDone Backup\/(Storage|Customers|Suppliers)\//.test(r.dropbox_path) &&['supplier', 'customer', 'inquiry', 'quote'].includes(r.entity) && r.owner_exists === false) {
      moves.push({ kind: 'ownerless', id: r.id, from: r.dropbox_path, to: `${ROOT}/_archive/ownerless-${date}/${after(r.dropbox_path)}`, hash: r.dropbox_content_hash });
      continue;
    }
    // A: one folder per customer, and it is the NAMED one (review of #1284, 12 Oct 2026: the first folder of
    // 2 customers was opened as "Customer (<id8>)" before the name was saved; the files move to the name,
    // never into the placeholder). A request's own subfolder is the one its Inquiry Summary opened.
    if (!r.dropbox_path.startsWith(ROOT + '/Customers/') || !r.named_folder) continue;
    if (r.entity !== 'customer' && r.entity !== 'inquiry') continue;
    const own = anchorPrefix(r.dropbox_path, 'customer');
    if (!own) continue;
    let to = r.named_folder + r.dropbox_path.slice(own.length);
    if (r.entity === 'inquiry' && /\/Inquiries\//.test(r.dropbox_path)) {
      const sub = /\/Inquiries\/([^/]+)\//.exec(byKey.get(`I:${r.entity_id}:summary`)?.dropbox_path ?? '')?.[1];
      if (sub) to = to.replace(/\/Inquiries\/[^/]+\//, `/Inquiries/${sub}/`);
    }
    if (to !== r.dropbox_path) moves.push({ kind: 'merge', id: r.id, from: r.dropbox_path, to, hash: r.dropbox_content_hash });
  }
  // C and D: files in the entity tree that no row names
  const known = new Set(rows.map((r) => key(r.dropbox_path)));
  for (const l of listed) {
    if (known.has(key(l.p))) continue;
    if (!l.p.startsWith(ROOT + '/Suppliers/') && !l.p.startsWith(ROOT + '/Customers/')) continue;
    if (DEMO_EVIDENCE.test(l.p)) { moves.push({ kind: 'demo', id: null, from: l.p, to: `${ROOT}/_archive/demo-leftovers-${date}/${after(l.p)}`, hash: l.h }); continue; }
    const sup = /^\/QuotesDone Backup\/Suppliers\/[^/]+\/[^/]* \((\d+)\)\//.exec(l.p);
    const cus = /^\/QuotesDone Backup\/Customers\/[^/]* \(([0-9a-f]{8})\)\//.exec(l.p);
    records.push({ kind: 'record', path: l.p, hash: l.h, size: l.s, modified: l.m ?? null,
      entity: sup ? 'supplier' : cus ? 'customer' : 'company', entity_ref: sup?.[1] ?? cus?.[1] ?? 'dropbox' });
  }
  // two operations must never land on one path
  const to = new Map<string, number>();
  for (const m of moves) to.set(key(m.to), (to.get(key(m.to)) || 0) + 1);
  const collisions = [...to.entries()].filter(([, n]) => n > 1).map(([p]) => p);
  return { moves, records, collisions };
}

export function counts(p: ReturnType<typeof plan>) {
  const by = (k: string) => p.moves.filter((m) => m.kind === k).length;
  return { merge: by('merge'), ownerless: by('ownerless'), demo: by('demo'), record: p.records.length, collisions: p.collisions.length };
}

// ── the guards of the runner (review of #1284) ──

// 1. The moves touch real files: they need the founder's own ruling, read from public.founder_instruction,
//    whose words approve moving these Dropbox files. A ledger id alone, or a ruling about something else, is refused.
export type Ruling = { id: number; instruction: string | null; subject: string | null; status: string | null };
export function founderApprovesMoves(r: Ruling | undefined): { ok: boolean; why: string } {
  if (!r) return { ok: false, why: 'no such founder_instruction row' };
  if (/withdrawn|rejected|cancel/i.test(r.status ?? '')) return { ok: false, why: `the ruling is ${r.status}` };
  const t = `${r.subject ?? ''} ${r.instruction ?? ''}`;
  if (!/dropbox/i.test(t)) return { ok: false, why: 'the ruling does not name Dropbox' };
  if (!/\b(move|moves|moving|archive|merge|repair|re-?file)\b/i.test(t)) return { ok: false, why: 'the ruling does not name a move' };
  if (!/\b(yes|ok|okay|approve[sd]?|go ahead|proceed|do it|allowed?)\b/i.test(t) || /\b(hold|wait|not yet|don'?t move|do not move|no moves?)\b/i.test(t)) {
    return { ok: false, why: 'the ruling does not approve the moves in so many words' };
  }
  return { ok: true, why: `founder_instruction ${r.id}` };
}

// 3. At most 50 records a run unless the operator raises it on purpose.
export const RECORD_CAP = 50;
export function capRecords<T>(records: T[], max?: number): { take: T[]; held: number } {
  const n = max !== undefined && Number.isInteger(max) && max > 0 ? max : RECORD_CAP;
  return { take: records.slice(0, n), held: Math.max(0, records.length - n) };
}

// 2. The admit trigger normalises dropbox_path (fn_dbx_path) and drops a row it reads as demo. A record is
//    good only when the row that landed names EXACTLY the file in Dropbox; anything else is a failure and
//    the statement raises, so nothing half-right is left behind.
export const recordKey = (path: string) => 'DBX:' + path.normalize('NFC').toLowerCase();
export function recordStatement(rec: Record_, entityId: string, lit: (s: unknown) => string): string {
  return `do $rec$ declare v_path text; begin
  if exists (select 1 from public.doc_backups where dedupe_key = ${lit(recordKey(rec.path))}) then
    raise exception 'REC<<already recorded>>';
  end if;
  insert into public.doc_backups (entity, entity_id, doc_type, file_name, dropbox_path, source, dedupe_key, status,
      dropbox_content_hash, dropbox_size, bytes, backed_up_at, verified_at, error)
    values (${lit(rec.entity)}, ${lit(entityId)}, 'Dropbox only', ${lit(rec.path.replace(/^.*\//, ''))}, ${lit(rec.path)}, 'dropbox',
      ${lit(recordKey(rec.path))}, 'done', ${lit(rec.hash)}, ${rec.size}, ${rec.size}, ${lit(rec.modified)}, now(),
      'recorded 7 Oct 2026: in Dropbox with no backup record; no storage source (it_engineer repair)')
    returning dropbox_path into v_path;
  if v_path is null then raise exception 'REC<<dropped by the admit trigger (read as demo)>>'; end if;
  if v_path <> ${lit(rec.path)} then raise exception 'REC<<the trigger rewrote the path to %>>', v_path; end if;
  raise notice 'REC<<ok>>';
end $rec$;`;
}
// The answer of one record statement: ok only when it ran without error.
export function recordOutcome(error: string | null): { recorded: boolean; reason: string } {
  if (!error) return { recorded: true, reason: 'recorded' };
  const m = /REC<<(.*?)>>/s.exec(error);
  return { recorded: false, reason: m ? m[1] : 'error: ' + error.slice(0, 160) };
}
