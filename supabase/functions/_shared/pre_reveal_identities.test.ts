// preRevealIdentities() over a stubbed database, the whole-word match, and the four reply sites that pass the list.
// No network. Before 3 Nov 2026 no production reply passed `forbidden`, so replyProblems never refused a counterpart's name.
import { assert, assertEquals } from 'jsr:@std/assert';
import { identityTerms, preRevealIdentities } from './pre_reveal_identities.ts';
import { namesForbidden, replyProblems } from './ai_reply.ts';

type Row = Record<string, unknown>;
/** A PostgREST-shaped stub: eq/in filter the table's rows, not('revealed_at','is',null) keeps revealed rows. */
function db(tables: Record<string, Row[]>) {
  return { from(t: string) {
    let rows = [...(tables[t] ?? [])];
    const q = {
      select: () => q, limit: () => q,
      eq: (k: string, v: unknown) => { rows = rows.filter((r) => String(r[k]) === String(v)); return q; },
      in: (k: string, vs: unknown[]) => { rows = rows.filter((r) => vs.map(String).includes(String(r[k]))); return q; },
      not: (k: string) => { rows = rows.filter((r) => r[k] != null); return q; },
      then: (ok: (v: { data: Row[]; error: null }) => unknown) => Promise.resolve({ data: rows, error: null }).then(ok),
    };
    return q;
  } };
}
const TABLES = {
  inquiries: [{ id: 1, customer_id: 'c1' }, { id: 2, customer_id: 'c2' }, { id: 3, customer_id: 'c3' }],
  quotes: [{ inquiry_id: 1, supplier_id: 10 }, { inquiry_id: 2, supplier_id: 10 }, { inquiry_id: 1, supplier_id: 11 }],
  inquiry_matches: [{ inquiry_id: 3, supplier_id: 10 }],
  transactions: [{ supplier_id: 10, customer_id: 'c2', revealed_at: '2026-10-01' }, { supplier_id: 11, customer_id: 'c1', revealed_at: null }],
  customers: [{ id: 'c1', full_name: 'ZZ DEMO Ahmed Khan', email: 'ahmed@example.invalid' }, { id: 'c2', full_name: 'ZZ DEMO Revealed Person', email: 'r@example.invalid' },
    { id: 'c3', full_name: 'ZZ DEMO Sara Ali', email: 'sara@example.invalid' }],
  leads: [{ id: 10, company_name: 'ZZ DEMO Al Noor Contracting LLC', email: 'sales@alnoor.example.invalid', website: 'https://www.alnoor-demo.invalid/about' },
    { id: 11, company_name: 'ZZ DEMO Gulf Glass', contact_name: 'Omar' }],
};

Deno.test('a supplier may not be told the customers of jobs it quoted or was matched to, until a reveal', async () => {
  const f = await preRevealIdentities(db(TABLES), { leadId: 10 });
  assert(f.includes('ZZ DEMO Ahmed Khan') && f.includes('ZZ DEMO Sara Ali') && f.includes('ahmed@example.invalid'), JSON.stringify(f));
  assert(!f.some((x) => x.includes('Revealed')), 'a customer revealed to this supplier is not forbidden');
});

Deno.test('a customer may not be told the suppliers on their jobs, until a reveal', async () => {
  const f = await preRevealIdentities(db(TABLES), { customerId: 'c1' });
  assert(f.includes('ZZ DEMO Al Noor Contracting LLC') && f.includes('ZZ DEMO Al Noor') && f.includes('ZZ DEMO Gulf Glass'), JSON.stringify(f));
  assert(f.includes('alnoor-demo.invalid'), 'the web domain is forbidden too');
});

Deno.test('a failed read gives an empty list, never a thrown turn', async () => {
  assertEquals(await preRevealIdentities({ from: () => { throw new Error('down'); } }, { leadId: 1 }), []);
});

Deno.test('the match is whole-word: a name is refused, a word containing it is not', () => {
  assert(namesForbidden('Your supplier is Al Noor Contracting, ready to start.', identityTerms([{ company_name: 'Al Noor Contracting LLC' }])));
  assertEquals(namesForbidden('The quality of the finish matters.', ['Ali']), false);   // a substring match refused this
  assert(replyProblems('Ahmed Khan asked for the tiles.', new Set(), { forbidden: ['Ahmed Khan'] }).some((p) => p.includes("another party's identity")));
});

Deno.test('every conversation reply that knows the party passes the list (sales_engineer, supplier_api, wa_inbound, email_triage)', async () => {
  const src = (f: string) => Deno.readTextFile(new URL('../' + f, import.meta.url));
  assert(/replyProblems\(t, known, \{ allowed, forbidden \}\)/.test(await src('sales_engineer/index.ts')), 'sales_engineer portal');
  assert(/forbidden: await preRevealIdentities\(admin, \{ leadId: Number\(sup\.id\) \}\)/.test(await src('supplier_api/index.ts')), 'supplier_api quotation chat');
  assert(/modelSays\([\s\S]{0,300}?forbidden: await forbidden/.test(await src('wa_inbound/index.ts')), 'wa_inbound sayFor');
  const et = await src('email_triage/index.ts');
  assert(/aiReply\(deps, \{[^}]*forbidden/.test(et) && /namesForbidden\(r\.answer, forbidden\)/.test(et), 'email_triage answer()');
});
