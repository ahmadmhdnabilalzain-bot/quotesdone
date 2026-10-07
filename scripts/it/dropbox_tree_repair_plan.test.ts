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
