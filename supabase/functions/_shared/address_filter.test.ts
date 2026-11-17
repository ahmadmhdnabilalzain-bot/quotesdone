// _shared/address_filter.ts: an identity is found by equality, never by a pattern (security audit 17 Nov 2026, finding 1).
// The stub below reads a filter the way PostgREST and Postgres do: `eq` is equality; `ilike` first turns every `*` into
// `%` (PostgREST), then `\` escapes, `%` is any run and `_` any one character, case ignored (Postgres). ZZ DEMO rows only.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/address_filter.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { claimedLeadIdOf, customerIdOf, likeLiteral, normalEmail, whereAddress } from './address_filter.ts';

type Row = Record<string, string | null>;

/** A LIKE pattern as Postgres reads it, after PostgREST has rewritten `*` to `%`. */
function postgrestLike(pattern: string, value: string, caseless: boolean): boolean {
  const p = pattern.replace(/\*/g, '%');
  let re = '';
  for (let i = 0; i < p.length; i++) {
    const c = p[i];
    if (c === '\\' && i + 1 < p.length) { re += p[++i].replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); continue; }
    re += c === '%' ? '[\\s\\S]*' : c === '_' ? '[\\s\\S]' : c.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
  }
  return new RegExp('^' + re + '$', caseless ? 'i' : '').test(value);
}

/** A PostgREST table: from(t).select().eq|ilike(...).limit(n) answers the rows it would. */
function stubDb(tables: Record<string, Row[]>) {
  const asked: string[] = [];
  return {
    asked,
    from(t: string) {
      const keep: ((r: Row) => boolean)[] = [];
      const q = {
        select: () => q,
        eq: (c: string, v: string) => { asked.push(`${t}.${c}=eq.${v}`); keep.push((r) => r[c] === v); return q; },
        ilike: (c: string, p: string) => { asked.push(`${t}.${c}=ilike.${p}`); keep.push((r) => r[c] != null && postgrestLike(p, String(r[c]), true)); return q; },
        limit: (n: number) => Promise.resolve({ data: (tables[t] ?? []).filter((r) => keep.every((k) => k(r))).slice(0, n), error: null }),
      };
      return q;
    },
  };
}

const VICTIM = { id: 'zz-demo-cust-victim', email: 'zz.demo.victim@example.invalid' };
const tables = () => ({
  customers: [VICTIM, { id: 'zz-demo-cust-other', email: 'zz-demo-other@example.invalid' }] as Row[],
  leads: [
    { id: '900001', claimed_by: 'zz.demo.supplier@example.invalid', email: 'Sales.ZZ.Demo@Example.Invalid' },
    { id: '900002', claimed_by: null, email: 'axyzb@example.invalid' },
  ] as Row[],
});

Deno.test('the stub reads a pattern as Postgres does (so the cases below test the real thing)', () => {
  assertEquals(postgrestLike('zz_demo_victim@example.invalid', 'zz.demo.victim@example.invalid', true), true);
  assertEquals(postgrestLike('%@example.invalid', 'zz.demo.victim@example.invalid', true), true);
  assertEquals(postgrestLike('a*b@example.invalid', 'axyzb@example.invalid', true), true, 'PostgREST turns * into %');
  assertEquals(postgrestLike('zz\\_demo@example.invalid', 'zz.demo@example.invalid', true), false);
});

Deno.test('a look-alike address is nobody: `_` and `%` are characters, not wildcards', async () => {
  const db = stubDb(tables());
  assertEquals(await customerIdOf(db, 'zz_demo_victim@example.invalid'), null, 'john_smith@ is not john.smith@');
  assertEquals(await customerIdOf(db, 'zz_demo.victim@example.invalid'), null);
  assertEquals(await customerIdOf(db, '%@example.invalid'), null, '% matches nothing');
  assertEquals(await customerIdOf(db, '%'), null);
  assertEquals(await customerIdOf(db, 'zz.demo.v%'), null);
  assertEquals(await claimedLeadIdOf(db, 'zz_demo_supplier@example.invalid'), null);
  assertEquals(await claimedLeadIdOf(db, '%@example.invalid'), null);
  assertEquals(await customerIdOf(db, ''), null);
  assertEquals(await customerIdOf(db, null), null);
});

Deno.test('the same address, in any case and with surrounding space, is still the customer', async () => {
  const db = stubDb(tables());
  assertEquals(await customerIdOf(db, 'zz.demo.victim@example.invalid'), VICTIM.id);
  assertEquals(await customerIdOf(db, '  ZZ.Demo.Victim@Example.INVALID '), VICTIM.id);
  assertEquals(await claimedLeadIdOf(db, 'ZZ.DEMO.SUPPLIER@example.invalid'), '900001');
});

Deno.test('whereAddress is a case-insensitive EQUALITY on a column stored in any case, never a pattern', async () => {
  const db = stubDb(tables());
  const ids = async (addr: string) => ((await whereAddress(db.from('leads').select('id'), 'email', addr).limit(5)).data as Row[]).map((r) => r.id);
  assertEquals(await ids('sales.zz.demo@example.invalid'), ['900001'], 'a listing e-mail stored with capitals is found');
  assertEquals(await ids('sales_zz_demo@example.invalid'), [], '_ is not any character');
  assertEquals(await ids('%@example.invalid'), [], '% is not any run');
  assertEquals(await ids('a*b@example.invalid'), [], 'a * that PostgREST would turn into % is never sent to ilike');
  assertEquals(await ids('a\\%b@example.invalid'), []);
  assertEquals(db.asked.at(-2), 'leads.email=eq.a*b@example.invalid');
});

Deno.test('likeLiteral escapes what LIKE reads and refuses what PostgREST would rewrite', () => {
  assertEquals(likeLiteral('john_smith%x\\y@example.invalid'), 'john\\_smith\\%x\\\\y@example.invalid');
  assertEquals(likeLiteral('plain@example.invalid'), 'plain@example.invalid');
  assertEquals(likeLiteral('a*b@example.invalid'), null);
  assertEquals(normalEmail('  A.B@Example.Invalid '), 'a.b@example.invalid');
  assertEquals(normalEmail(undefined), '');
});
