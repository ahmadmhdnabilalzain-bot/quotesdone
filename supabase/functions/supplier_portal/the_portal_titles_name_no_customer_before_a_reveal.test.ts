// The supplier portal's workspaces, opportunities and quote recommendation name no customer before a reveal (13 Nov 2026,
// sales_engineer; independent review of F2, item 3). The inputs are what production's routines returned for the review's
// probe: fn_supplier_safe_text kept "Al Nahda", "Villa 15 Al Barsha 2 near Mall of the Emirates" and "AED 32,816.70".
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/supplier_portal/the_portal_titles_name_no_customer_before_a_reveal.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { opportunitiesBeforeReveal, portalTitle, recommendBeforeReveal, revealedBy, workspacesBeforeReveal } from './before_reveal.ts';

const SQL_MASKED = 'Kitchen fit-out in Al Nahda, Sharjah; villa 15 Al Barsha 2 near Mall of the Emirates; existing quote AED 32,816.70';
const NEVER = ['Nahda', 'Barsha', 'villa 15', 'Mall of the Emirates', '32,816', 'Falcon'];
const found = (t: string) => NEVER.filter((n) => t.toLowerCase().includes(n.toLowerCase()));

Deno.test('before a reveal: the trade and the emirate only, no customer file name; after it, the customer\'s own title', () => {
  const ws = { workspaces: [
    { inquiry_id: 'a', project: { title: SQL_MASKED, category: 'fitout', emirate: 'Sharjah' }, files: [{ name: 'Falcon quote Omar Villa 15.pdf', kind: 'quotation' }] },
    { inquiry_id: 'c', project: { title: SQL_MASKED, category: 'fitout', emirate: 'Sharjah', rfq_no: 160777 }, files: [] },
    { inquiry_id: 'b', project: { title: SQL_MASKED, category: 'fitout', emirate: 'Sharjah' }, files: [] },
  ] };
  const out = workspacesBeforeReveal(ws, new Set(['b']))!;
  assertEquals(found(JSON.stringify(out.workspaces[0])), []);
  assertEquals(out.workspaces[0].project.title, 'Fitout work in Sharjah · Job A');
  assertEquals(out.workspaces[0].files[0].name, 'Job file (quotation)');
  assertEquals(out.workspaces[2].project.title, SQL_MASKED);   // revealed: his to read
  // two same-trade jobs in one emirate are told apart by the job number (second review of F2, item 4)
  assertEquals(out.workspaces[1].project.title, 'Fitout work in Sharjah · Job 160777');
  assert(out.workspaces[0].project.title !== out.workspaces[1].project.title);
  const op = opportunitiesBeforeReveal({ opportunities: [{ inquiry_id: 'a', category: 'fitout', emirate: 'Sharjah', project_title: SQL_MASKED, requirement: 'the whole chat ' + SQL_MASKED, estimated_value: 'AED 30k for villa 15' }] }, new Set())!;
  assertEquals(found(JSON.stringify(op)), []);
  assertEquals([op.opportunities[0].requirement, op.opportunities[0].estimated_value], [null, null]);
  const rec = recommendBeforeReveal({ available: true, summary: SQL_MASKED }, false, { category: 'fitout', emirate: 'Sharjah' })!;
  assertEquals(rec.summary, 'Fitout work in Sharjah');   // no job given: none printed
  assert(portalTitle('plumbing_sanitary', 'Dubai') === 'Plumbing sanitary work in Dubai');
});

Deno.test('a reveal is a transactions row WITH revealed_at (second review of F2: N7, revealedBy without the filter, survived)', async () => {
  const rows = [{ inquiry_id: 'paid', revealed_at: '2026-11-13T06:00:00Z' }, { inquiry_id: 'pending', revealed_at: null }];
  let filtered = false;
  const q: any = { select: () => q, eq: () => q, not: (col: string, op: string, v: unknown) => { filtered = col === 'revealed_at' && op === 'is' && v === null; return q; },
    then: (res: (v: unknown) => unknown) => res({ data: filtered ? rows.filter((r) => r.revealed_at) : rows, error: null }) };
  const got = await revealedBy({ from: () => q }, 7);
  assertEquals([...got], ['paid']);
});
