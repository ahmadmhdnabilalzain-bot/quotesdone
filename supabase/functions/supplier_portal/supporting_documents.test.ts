// deno test --no-lock supabase/functions/supplier_portal/supporting_documents.test.ts
//
// Supporting company documents (15 Sep 2026) against a fake client that records every write. The
// properties under test: a supplier reaches only rows keyed to itself; nothing writes a leads column
// (the mandatory six stay on their own door); a refused file is never recorded; remove hides, it does
// not destroy. No network, no environment, no real row.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { cleanLabel, deleteSupporting, listSupporting, pathFor, REF_TABLE, saveSupporting, typeOf, urlSupporting, type Deps } from './supporting_documents.ts';

type Row = Record<string, unknown>;
function fakeAdmin(rows: Row[]) {
  const writes: { table: string; op: string; values: Row; filters: Row }[] = [];
  const from = (table: string) => {
    const filters: Row = {}; const neq: Row = {};
    let op = 'select'; let values: Row = {};
    const match = (r: Row) => Object.entries(filters).every(([k, v]) => String(r[k]) === String(v)) && Object.entries(neq).every(([k, v]) => String(r[k]) !== String(v));
    const q: Record<string, unknown> = {};
    q.select = () => q; q.order = () => q; q.limit = () => q;
    q.eq = (k: string, v: unknown) => { filters[k] = v; return q; };
    q.neq = (k: string, v: unknown) => { neq[k] = v; return q; };
    q.update = (v: Row) => { op = 'update'; values = v; return q; };
    q.insert = (v: Row) => { op = 'insert'; values = v; return q; };
    const run = () => {
      if (op === 'insert') { const r = { id: rows.length + 100, created_at: '2026-09-15T10:00:00Z', ...values }; rows.push(r); writes.push({ table, op, values, filters: {} }); return r; }
      const hit = rows.filter(match);
      if (op === 'update') { writes.push({ table, op, values, filters: { ...filters } }); for (const r of hit) Object.assign(r, values); }
      return hit;
    };
    q.maybeSingle = () => { const r = run(); return Promise.resolve({ data: Array.isArray(r) ? (r[0] ?? null) : r }); };
    q.then = (ok: (v: unknown) => unknown) => { const r = run(); return Promise.resolve({ data: r, count: Array.isArray(r) ? r.length : 1 }).then(ok); };
    return q;
  };
  return { writes, from };
}
const mine = (id: number, sup: number, extra: Row = {}): Row => ({ id, bucket: 'supplier-docs', ref_table: REF_TABLE, ref_id: String(sup), path: `supporting/${sup}/1784642799037_a.pdf`, file_name: 'ISO letter', kind: 'supporting:certificate', status: 'received', created_at: '2026-09-01T00:00:00Z', ...extra });
const deps = (over: Partial<Deps> = {}): Deps => ({
  scan: async () => ({ ok: true, bytes: new Uint8Array([1]), mime: 'application/pdf' }),
  safeFilename: (n) => n.replace(/[^\w.-]/g, '_'), upload: async () => ({ error: null }), sign: async (p) => 'https://signed/' + p, now: () => 1789000000000, ...over,
});

Deno.test('list: only this supplier\'s rows, withdrawn hidden, the uploaded filename without its stamp', async () => {
  const admin = fakeAdmin([mine(1, 7), mine(2, 8), mine(3, 7, { status: 'withdrawn' }), mine(4, 7, { ref_table: 'leads' })]);
  const r = await listSupporting(admin, 7, deps().sign);
  assertEquals(r.status, 200);
  assertEquals(r.body.documents.map((d: Row) => d.id), [1]);
  assertEquals(r.body.documents[0].file_name, 'a.pdf');
  assertEquals(r.body.documents[0].type, 'certificate');
});

Deno.test('upload: scanned, stored under supporting/<id>/, recorded received — and no leads column is written', async () => {
  const admin = fakeAdmin([]);
  let stored = '';
  const r = await saveSupporting(admin, 7, { label: '  Reference\u0007 letter  ', type: 'reference_letter', filename: 'ref.pdf', original_b64: 'AAAA' }, deps({ upload: async (p) => { stored = p; return { error: null }; } }));
  assertEquals(r.status, 200);
  assertEquals(stored, pathFor(7, 'ref.pdf', 1789000000000));
  assertEquals(r.body.document.label, 'Reference letter');
  const w = admin.writes[0];
  assertEquals([w.table, w.op, w.values.status, w.values.ref_table, w.values.ref_id, w.values.kind], ['documents', 'insert', 'received', REF_TABLE, '7', 'supporting:reference_letter']);
  assert(!admin.writes.some((x) => x.table === 'leads'), 'the mandatory six are not reachable from here');
});

Deno.test('a refused file is reported and nothing is stored or recorded', async () => {
  const admin = fakeAdmin([]);
  let uploaded = false;
  const r = await saveSupporting(admin, 7, { label: 'x', filename: 'x.exe', original_b64: 'AAAA' }, deps({ scan: async () => ({ ok: false, reason: 'executable' }), upload: async () => { uploaded = true; return { error: null }; } }));
  assertEquals([r.status, r.body.error, r.body.reason], [422, 'file_refused', 'executable']);
  assertEquals(uploaded, false);
  assertEquals(admin.writes.length, 0);
});

Deno.test('validation: label and file required for a new document, type from the list, size capped', async () => {
  const admin = fakeAdmin([]);
  assertEquals((await saveSupporting(admin, 7, { original_b64: 'AAAA' }, deps())).body.error, 'label_required');
  assertEquals((await saveSupporting(admin, 7, { label: 'x' }, deps())).body.error, 'file_required');
  assertEquals((await saveSupporting(admin, 7, { label: 'x', type: 'passport', original_b64: 'AAAA' }, deps())).body.error, 'bad_type');
  assertEquals((await saveSupporting(admin, 7, { label: 'x', original_b64: 'A'.repeat(36_000_000) }, deps())).status, 413);
  assertEquals(cleanLabel('a'.repeat(300)).length, 120);
  assertEquals(typeOf('supporting:nonsense'), 'other');
});

Deno.test('replace and rename reach only the owner\'s row; another supplier\'s id is not found', async () => {
  const admin = fakeAdmin([mine(1, 7), mine(2, 8)]);
  const r = await saveSupporting(admin, 7, { id: 1, original_b64: 'AAAA', filename: 'new.pdf' }, deps());
  assertEquals([r.status, r.body.replaced], [200, true]);
  const upd = admin.writes.find((w) => w.op === 'update')!;
  assertEquals([upd.filters.id, upd.filters.ref_id, upd.filters.ref_table], [1, '7', REF_TABLE]);
  assertEquals((await saveSupporting(admin, 7, { id: 2, label: 'mine now' }, deps())).status, 404);
  assertEquals(admin.writes.filter((w) => w.op === 'update').length, 1);
});

Deno.test('remove hides (status withdrawn), only the owner\'s, and a second remove is not found', async () => {
  const rows = [mine(1, 7), mine(2, 8)];
  const admin = fakeAdmin(rows);
  assertEquals((await deleteSupporting(admin, 7, 2)).status, 404);
  assertEquals((await deleteSupporting(admin, 7, 1)).status, 200);
  assertEquals(rows[0].status, 'withdrawn');
  assertEquals(rows[1].status, 'received');
  assertEquals((await deleteSupporting(admin, 7, 1)).status, 404);
  assertEquals((await deleteSupporting(admin, 7, 'x')).status, 400);
});

Deno.test('download URL only for the owner', async () => {
  const admin = fakeAdmin([mine(1, 7), mine(2, 8)]);
  const ok = await urlSupporting(admin, 7, 1, deps().sign);
  assertEquals([ok.status, ok.body.expires_in], [200, 3600]);
  assertEquals((await urlSupporting(admin, 7, 2, deps().sign)).status, 404);
});
