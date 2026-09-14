// deno test supabase/functions/_shared/inquiry_split.test.ts
// Route-level: the real split orchestration create_inquiry runs, driven through a fake database.
// Review of #653: a partly-saved split told the customer "sent", listed trades that never went out,
// and had already emailed the suppliers of the trades that did save. All or nothing now.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { splitInquiry, type SplitOps } from './inquiry_split.ts';

function fakeDb(opts: { failTrades?: string[]; failParent?: boolean; failDelete?: boolean } = {}) {
  const rows = new Set<string>();
  const notified: string[] = [];
  const findings: Record<string, unknown>[] = [];
  let n = 0;
  const ops: SplitOps = {
    insertParent: async () => { if (opts.failParent) return null; const id = `P${++n}`; rows.add(id); return id; },
    insertChild: async (t) => { if (opts.failTrades?.includes(t)) throw new Error('insert failed'); const id = `C${++n}-${t}`; rows.add(id); return id; },
    deleteInquiries: async (ids) => { if (opts.failDelete) return false; ids.forEach((i) => rows.delete(i)); return true; },
    notifyChild: async (id) => { notified.push(id); return 2; },
    finding: async (d) => { findings.push(d); },
  };
  return { ops, rows, notified, findings };
}

Deno.test('every child saves: all are notified, matches reported per child', async () => {
  const db = fakeDb();
  const r = await splitInquiry(['aluminium', 'electrical'], db.ops);
  assert(r.ok);
  assertEquals(r.children.map((c) => [c.trade, c.matches]), [['aluminium', 2], ['electrical', 2]]);
  assertEquals(db.notified.length, 2);
  assertEquals(db.rows.size, 3);
});

Deno.test('one child fails: nothing is sent, saved rows are removed, the failed trade is named', async () => {
  const db = fakeDb({ failTrades: ['electrical'] });
  const r = await splitInquiry(['aluminium', 'electrical', 'plumbing'], db.ops);
  assertEquals(r, { ok: false, error: 'split_failed', failed_trades: ['electrical'] });
  assertEquals(db.notified, []);          // no supplier was invited to a partial request
  assertEquals(db.rows.size, 0);          // the parent and the two saved children are gone
  assertEquals(db.findings, []);
});

Deno.test('every child fails: split_failed with all trades, parent removed', async () => {
  const db = fakeDb({ failTrades: ['aluminium', 'electrical'] });
  const r = await splitInquiry(['aluminium', 'electrical'], db.ops);
  assertEquals(r, { ok: false, error: 'split_failed', failed_trades: ['aluminium', 'electrical'] });
  assertEquals(db.rows.size, 0);
  assertEquals(db.notified, []);
});

Deno.test('the parent itself fails: nothing saved, every trade named', async () => {
  const db = fakeDb({ failParent: true });
  assertEquals(await splitInquiry(['aluminium', 'glazing'], db.ops), { ok: false, error: 'split_failed', failed_trades: ['aluminium', 'glazing'] });
});

Deno.test('a failed compensating delete is reported as a finding, never swallowed', async () => {
  const db = fakeDb({ failTrades: ['electrical'], failDelete: true });
  const r = await splitInquiry(['aluminium', 'electrical'], db.ops);
  assert(!r.ok && r.cleanup_failed && r.cleanup_failed.length === 2);
  assertEquals(db.findings.length, 1);
  assertEquals(db.findings[0].kind, 'split_compensation_failed');
  assertEquals(db.notified, []);
});
