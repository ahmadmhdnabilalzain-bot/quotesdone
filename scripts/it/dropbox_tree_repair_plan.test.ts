// deno test scripts/it/dropbox_tree_repair_plan.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { counts, plan, type Row } from './dropbox_tree_repair_plan.ts';

const R = '/QuotesDone Backup';
const row = (o: Partial<Row>): Row => ({ id: 0, entity: 'company', entity_id: '', dropbox_path: '', dropbox_content_hash: 'h', dedupe_key: '', status: 'done', owner_exists: true, ...o });
const C = 'aaaaaaaa-1111-2222-3333-444444444444', I = 'bbbbbbbb-1111-2222-3333-444444444444';

Deno.test('a file in a second folder moves into the folder the entity first opened', () => {
  const rows = [
    row({ id: 1, entity: 'customer', entity_id: C, dedupe_key: `C:${C}:details`, dropbox_path: `${R}/Customers/Ann (aaaaaaaa)/Customer Details.pdf` }),
    row({ id: 2, entity: 'customer', entity_id: C, dedupe_key: 'CONV:x:1', dropbox_path: `${R}/Customers/Ann B (aaaaaaaa)/Correspondence/a.pdf` }),
    row({ id: 3, entity: 'inquiry', entity_id: I, dedupe_key: `I:${I}:summary`, dropbox_path: `${R}/Customers/Ann (aaaaaaaa)/Inquiries/2026-10-01 bbbbbbbb - open/Inquiry Summary.pdf` }),
    row({ id: 4, entity: 'inquiry', entity_id: I, dedupe_key: `I:${I}:drawing:x`, dropbox_path: `${R}/Customers/Ann (aaaaaaaa)/Inquiries/2026-10-01 bbbbbbbb - quoted/Drawing - d.pdf` }),
  ];
  const p = plan(rows, [], '2026-10-07');
  assertEquals(p.moves.map((m) => [m.id, m.to]), [
    [2, `${R}/Customers/Ann (aaaaaaaa)/Correspondence/a.pdf`],
    [4, `${R}/Customers/Ann (aaaaaaaa)/Inquiries/2026-10-01 bbbbbbbb - open/Drawing - d.pdf`],
  ]);
});

Deno.test('an ownerless file in Storage/ is archived under its own path; an owned one is not touched', () => {
  const rows = [row({ id: 5, entity: 'inquiry', owner_exists: false, dropbox_path: `${R}/Storage/quote-files/quotes/1/x.pdf` }),
    row({ id: 6, entity: 'inquiry', owner_exists: true, dropbox_path: `${R}/Storage/quote-files/quotes/2/y.pdf` }),
    row({ id: 7, entity: 'company', owner_exists: null, dropbox_path: `${R}/Storage/brand/logo.png` })];
  const p = plan(rows, [], '2026-10-07');
  assertEquals(p.moves, [{ kind: 'ownerless', id: 5, from: `${R}/Storage/quote-files/quotes/1/x.pdf`, to: `${R}/_archive/ownerless-2026-10-07/Storage/quote-files/quotes/1/x.pdf`, hash: 'h' }]);
});

Deno.test('an unrecorded demo file is archived; an unrecorded real file is only recorded; a recorded file is left alone', () => {
  const rows = [row({ id: 8, dropbox_path: `${R}/Suppliers/Cat/Real Co (12)/Trade licence - a.pdf` })];
  const listed = [
    { p: `${R}/Suppliers/Cat/real co (12)/trade licence - a.pdf`, h: 'h', s: 1 },
    { p: `${R}/Suppliers/Cat/ZZ DEMO Co (13)/Trade licence - b.pdf`, h: 'h2', s: 2 },
    { p: `${R}/Suppliers/Cat/Real Co (12)/Insurance - c.pdf`, h: 'h3', s: 3, m: '2026-09-01T00:00:00Z' },
    { p: `${R}/Customers/Bo (cccccccc)/x.pdf`, h: 'h4', s: 4 },
  ];
  const p = plan(rows, listed, '2026-10-07');
  assertEquals(p.moves.map((m) => [m.kind, m.to]), [['demo', `${R}/_archive/demo-leftovers-2026-10-07/Suppliers/Cat/ZZ DEMO Co (13)/Trade licence - b.pdf`]]);
  assertEquals(p.records.map((r) => [r.entity, r.entity_ref, r.path]), [['supplier', '12', `${R}/Suppliers/Cat/Real Co (12)/Insurance - c.pdf`], ['customer', 'cccccccc', `${R}/Customers/Bo (cccccccc)/x.pdf`]]);
  assertEquals(counts(p), { merge: 0, ownerless: 0, demo: 1, record: 2, collisions: 0 });
});

Deno.test('a demo row and an unfinished row are never planned', () => {
  const p = plan([row({ id: 9, entity: 'zz_demo', owner_exists: false, dropbox_path: `${R}/Storage/a/b.pdf` }),
    row({ id: 10, entity: 'inquiry', status: 'error', owner_exists: false, dropbox_path: `${R}/Storage/a/c.pdf` })], [], '2026-10-07');
  assertEquals(p.moves, []);
});

import { capRecords, founderApprovesMoves, recordOutcome, recordStatement } from './dropbox_tree_repair_plan.ts';

Deno.test('review 1: the moves need a founder ruling that exists and approves the Dropbox moves in words', () => {
  assertEquals(founderApprovesMoves(undefined).ok, false);                                       // a bare number with no row
  assertEquals(founderApprovesMoves({ id: 1, instruction: 'yes approve the new pricing page', subject: 'site', status: 'open' }).ok, false);
  assertEquals(founderApprovesMoves({ id: 2, instruction: 'Dropbox: hold the moves, not yet', subject: null, status: 'open' }).ok, false);
  assertEquals(founderApprovesMoves({ id: 3, instruction: 'yes, move the Dropbox files to _archive', subject: null, status: 'withdrawn' }).ok, false);
  assertEquals(founderApprovesMoves({ id: 4, instruction: 'Dropbox repair: yes, approve the moves to _archive (never delete)', subject: 'backup', status: 'open' }),
    { ok: true, why: 'founder_instruction 4' });
});

Deno.test('review 2: a record is good only when the row that landed names exactly the Dropbox file', () => {
  const lit = (s: unknown) => s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
  const sql = recordStatement({ kind: 'record', path: "/QuotesDone Backup/Customers/O'Neil/a.pdf", hash: 'h', size: 1, modified: null, entity: 'company', entity_ref: 'dropbox' }, 'dropbox', lit);
  for (const must of ['returning dropbox_path into v_path', "if v_path is null then raise exception 'REC<<dropped by the admit trigger",
    "if v_path <> '/QuotesDone Backup/Customers/O''Neil/a.pdf' then raise exception", "dedupe_key = 'DBX:/quotesdone backup/customers/o''neil/a.pdf'"]) {
    assertEquals(sql.includes(must), true, must);
  }
  assertEquals(recordOutcome(null), { recorded: true, reason: 'recorded' });
  assertEquals(recordOutcome('sql 400 ERROR: P0001: REC<<dropped by the admit trigger (read as demo)>>'), { recorded: false, reason: 'dropped by the admit trigger (read as demo)' });
  assertEquals(recordOutcome('sql 400 ERROR: P0001: REC<<the trigger rewrote the path to /x>>').recorded, false);
  assertEquals(recordOutcome('sql 500 timeout').recorded, false);
});

Deno.test('review 3: at most 50 records a run unless --max says otherwise', () => {
  const r = Array.from({ length: 120 }, (_, i) => i);
  assertEquals([capRecords(r).take.length, capRecords(r).held], [50, 70]);
  assertEquals([capRecords(r, 200).take.length, capRecords(r, 200).held], [120, 0]);
  assertEquals(capRecords(r, 0).take.length, 50);                  // a nonsense --max falls back to the cap
  assertEquals(capRecords(r.slice(0, 14)).held, 0);
});
