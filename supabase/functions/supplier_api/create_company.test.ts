// AN INVITED SUPPLIER WHO REGISTERS ON THE WEBSITE CLAIMS HIS INVITED LISTING (28 Oct 2026, sales_engineer; ledger 1401
// audit, scenario S7). Behavioural: create_company.ts runs against an in-memory `leads` that refuses what production
// refuses (uq_leads_email_lower on lower(email), leads_claimed_by_lower_uidx, leads_claimed_company_name_uidx).
//
// THE INPUT THAT FAILED ON PRODUCTION (07:54Z, run aub990b4a): an unclaimed invited lead holds the address the supplier
// signs up with; create_company inserted a second row for it and answered HTTP 500 with the Postgres sentence
// "duplicate key value violates unique constraint "uq_leads_email_lower"". The first test replays it.
//   deno test --no-lock supabase/functions/supplier_api/create_company.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { companyNameKey, createCompany, DISPOSABLE_EMAIL, EMAIL_ALREADY_REGISTERED, emirateOf, listingProbes, planCreateCompany, planListingMatch, REGISTER_FAILED, sessionOpenedByCode, VERIFY_EMAIL_FIRST } from './create_company.ts';

type Row = Record<string, unknown>;
const low = (v: unknown) => String(v ?? '').trim().toLowerCase();
const nameKey = (v: unknown) => low(v).replace(/\s+/g, ' ');

/** An in-memory leads table with production's three unique rules, and the handful of supabase-js calls the door makes. */
function table(rows: Row[], opts: { failInsert?: { code: string; message: string }; failSelectOn?: string } = {}) {
  const t = { rows: rows.map((r) => ({ ...r })), inserts: 0, updates: 0, nextId: 900001, actions: [] as Row[] };
  const clash = (row: Row, self: Row | null): string | null => {
    for (const o of t.rows) {
      if (o === self) continue;
      if (row.email && o.email && low(o.email) === low(row.email)) return 'uq_leads_email_lower';
      if (row.claimed_by && o.claimed_by && low(o.claimed_by) === low(row.claimed_by)) return 'leads_claimed_by_lower_uidx';
      // fn_company_registration_name_key('') is NULL and NULL never conflicts: rows waiting for their licence's name do not clash
      if (row.claimed && o.claimed && String(row.company_name ?? '').trim() !== '' && (companyNameKey(o.company_name) ?? nameKey(o.company_name)) === (companyNameKey(row.company_name) ?? nameKey(row.company_name))) return 'leads_claimed_company_name_uidx';
    }
    return null;
  };
  const err = (idx: string) => ({ code: '23505', message: `duplicate key value violates unique constraint "${idx}"`, details: null });
  const admin = {
    from(name: string) {
      // the audit trail of a listing decision (H10): recorded, and readable by the tests
      if (name === 'agent_actions') return { insert(p: Row) { t.actions.push(p); return Promise.resolve({ data: null, error: null }); } };
      assertEquals(name, 'leads');
      const f: ((r: Row) => boolean)[] = []; const on: string[] = [];
      let op: 'select' | 'update' | 'insert' = 'select', payload: Row = {}, lim = Infinity, cols = '*';
      const pick = (r: Row) => (cols === '*' ? { ...r } : Object.fromEntries(cols.split(',').map((c) => [c.trim(), r[c.trim()]])));
      const run = () => {
        // a read that the database fails (a timeout, a dropped connection): PostgREST resolves { data: null, error }
        if (op === 'select' && opts.failSelectOn && on.includes(opts.failSelectOn)) return { data: null, error: { code: '57014', message: 'canceling statement due to statement timeout', details: null } };
        if (op === 'insert') {
          if (opts.failInsert) return { data: null, error: { ...opts.failInsert, details: null } };
          const row = { id: t.nextId++, ...payload };
          const c = clash(row, null);
          if (c) return { data: null, error: err(c) };
          t.rows.push(row); t.inserts++;
          return { data: [pick(row)], error: null };
        }
        const hit = t.rows.filter((r) => f.every((p) => p(r)));
        if (op === 'update') {
          for (const r of hit) { const next = { ...r, ...payload }; const c = clash(next, r); if (c) return { data: null, error: err(c) }; }
          for (const r of hit) { Object.assign(r, payload); t.updates++; }
        }
        return { data: hit.slice(0, lim).map(pick), error: null };
      };
      const q: Record<string, unknown> = {
        select(c: string) { cols = c; return q; },
        eq(c: string, v: unknown) { on.push(c); f.push((r) => r[c] === v); return q; },
        is(c: string, v: unknown) { on.push(c); f.push((r) => (r[c] ?? null) === v); return q; },
        // ilike as Postgres reads it: an unescaped % is any run of characters (the listing look-up's '%word%'), else exact
        // filter(col, 'imatch', re) as PostgREST reads it (~*): the listing look-up's per-word regular expressions (listingProbes).
        // Only the operator create_company uses is implemented, under the method name the REAL client has (supabase-js has no
        // .imatch(): round-2 review, 12 Nov 2026); any other operator fails the test loudly.
        filter(c: string, op: string, re: string) { if (op !== 'imatch') throw new Error('test table: filter op ' + op + ' not implemented'); on.push(c); const r = new RegExp(re, 'iu'); f.push((row) => r.test(String(row[c] ?? ''))); return q; },
        ilike(c: string, pat: string) { on.push(c); if (/(^|[^\\])%/.test(pat)) { const re = new RegExp('^' + pat.split(/(?<!\\)%/).map((x) => x.replace(/\\([\\%_])/g, '$1').replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$', 'is'); f.push((r) => re.test(String(r[c] ?? ''))); return q; } const want = pat.replace(/\\([\\%_])/g, '$1'); f.push((r) => low(r[c]) === low(want)); return q; },
        limit(n: number) { lim = n; return q; },
        update(p: Row) { op = 'update'; payload = p; return q; },
        insert(p: Row) { op = 'insert'; payload = p; return q; },
        maybeSingle() { const r = run(); return Promise.resolve({ data: r.data?.[0] ?? null, error: r.error }); },
        then(res: (v: unknown) => unknown, rej: (e: unknown) => unknown) { return Promise.resolve(run()).then(res, rej); },
      };
      return q;
    },
  };
  return { t, admin };
}
const calls: { reg: number[]; touch: number[] } = { reg: [], touch: [] };
const deps = (proven = true, o: { byCode?: boolean; sanctioned?: number[] } = {}) => ({
  emailProven: () => Promise.resolve(proven),
  sessionByCode: o.byCode ?? true,
  sanctionedLead: (id: number) => Promise.resolve((o.sanctioned ?? []).includes(id)),
  setRegistration: (id: number) => { calls.reg.push(id); return Promise.resolve({ status: 'free' }); },
  recordFirstTouch: (id: number) => { calls.touch.push(id); return Promise.resolve(); },
  locale: 'en',
});
const INVITED = { id: 151618, company_name: 'ZZ DEMO S7 Aluminium LLC', email: 'qd-aub990b4a-lead7@example.invalid', claimed: false, claimed_by: null,
  invite_status: 'queued', claim_token: '00000000-0000-4000-8000-000000000007', sector: null, source: 'directory' };
const FORM = { company_name: 'ZZ DEMO S7 Aluminium', category: 'aluminium', role: 'supplier', first_touch: null };

Deno.test('S7 replayed: the invited lead holding the address is CLAIMED in place — same id, one row, never an insert', async () => {
  const { t, admin } = table([INVITED]);
  calls.reg.length = 0; calls.touch.length = 0;
  const r = await createCompany(admin, 'qd-aub990b4a-lead7@example.invalid', FORM, deps());
  assertEquals(r.status, 200, JSON.stringify(r.body));
  assertEquals(r.body.ok, true);
  assertEquals(r.body.id, 151618, 'the invited row keeps its id (invitation, claim token and outreach history stay attached)');
  assertEquals(t.inserts, 0, 'a second row was inserted for an address the invited lead already holds');
  assertEquals(t.rows.length, 1);
  const row = t.rows[0];
  assertEquals([row.claimed, row.claimed_by, row.owner_email_verified], [true, 'qd-aub990b4a-lead7@example.invalid', true]);
  assertEquals([row.company_name, row.sector, row.business_role], ['ZZ DEMO S7 Aluminium', 'aluminium', 'supplier'], 'the form input is written to the row');
  assertEquals([row.claim_token, row.invite_status, row.source], [INVITED.claim_token, 'queued', 'directory'], 'the invitation record is untouched');
  assertEquals([calls.reg, calls.touch], [[151618], [151618]], 'the registration state and the first touch run for the claimed row, as after a /portal?t= claim');
});

Deno.test('the invited address typed in another case still claims the same row', async () => {
  const { t, admin } = table([{ ...INVITED, email: 'QD-Aub990b4a-Lead7@Example.INVALID' }]);
  const r = await createCompany(admin, 'qd-aub990b4a-lead7@example.invalid', FORM, deps());
  assertEquals([r.status, r.body.id, t.inserts, t.rows.length], [200, 151618, 0, 1]);
  assertEquals(t.rows[0].claimed_by, 'qd-aub990b4a-lead7@example.invalid');
});

Deno.test('two sign-ups racing for one invited row: exactly one claims it, the other is told the address has an account', async () => {
  const { t, admin } = table([INVITED]);
  const [a, b] = await Promise.all([
    createCompany(admin, 'qd-aub990b4a-lead7@example.invalid', FORM, deps()),
    createCompany(admin, 'qd-aub990b4a-lead7@example.invalid', FORM, deps()),
  ]);
  const statuses = [a.status, b.status].sort();
  assertEquals(statuses, [200, 409], `${JSON.stringify(a)} ${JSON.stringify(b)}`);
  const lost = a.status === 409 ? a : b;
  assertEquals(lost.body.code, EMAIL_ALREADY_REGISTERED.code);
  assertEquals([t.rows.length, t.inserts, t.updates], [1, 0, 1]);
});

Deno.test('a lead already claimed by another account: 409 email_already_registered, nothing written, no Postgres text', async () => {
  const { t, admin } = table([{ ...INVITED, claimed: true, claimed_by: 'qd-aub990b4a-other@example.invalid' }]);
  const r = await createCompany(admin, 'qd-aub990b4a-lead7@example.invalid', FORM, deps());
  assertEquals([r.status, r.body.code, r.body.error], [409, EMAIL_ALREADY_REGISTERED.code, EMAIL_ALREADY_REGISTERED.error]);
  assertEquals([t.inserts, t.updates], [0, 0]);
});

Deno.test('an address not proven by a sign-in code never claims anyone\'s listing', async () => {
  const { t, admin } = table([INVITED]);
  const r = await createCompany(admin, 'qd-aub990b4a-lead7@example.invalid', FORM, deps(false));
  assertEquals([r.status, r.body.code], [403, VERIFY_EMAIL_FIRST.code]);
  assertEquals([t.inserts, t.updates, t.rows[0].claimed_by], [0, 0, null]);
});

Deno.test('no lead holds the address: registered as before (one new self_registered row)', async () => {
  const { t, admin } = table([INVITED]);
  const r = await createCompany(admin, 'qd-aub990b4a-new8@example.invalid', { ...FORM, company_name: 'ZZ DEMO S7 Brand New' }, deps());
  assertEquals([r.status, t.inserts, t.rows.length], [200, 1, 2]);
  const row = t.rows.find((x) => x.email === 'qd-aub990b4a-new8@example.invalid')!;
  assertEquals([row.source, row.claimed, row.owner_email_verified], ['self_registered', true, true]);
});

Deno.test('the typed name of another claimed company is refused before any write (claim or insert)', async () => {
  const { t, admin } = table([INVITED, { id: 5, company_name: 'ZZ DEMO S7 Aluminium', email: 'qd-x-y@example.invalid', claimed: true, claimed_by: 'qd-x-y@example.invalid' }]);
  const r = await createCompany(admin, 'qd-aub990b4a-lead7@example.invalid', FORM, deps());
  assertEquals([r.status, r.body.code, t.inserts, t.updates], [409, 'company_already_registered', 0, 0]);
});

Deno.test('a temporary inbox is told so, not "please try again" into the same refusal (15 Nov 2026, Monday checklist)', async () => {
  // public.block_disposable_signup raises this, word for word, with SQLSTATE 23514
  const { admin } = table([], { failInsert: { code: '23514', message: 'Please use a permanent email address; temporary inboxes are not allowed.' } });
  const r = await createCompany(admin, 'qd-aub990b4a-tmp1@example.invalid', FORM, deps());
  assertEquals([r.status, r.body.code, r.body.error], [422, DISPOSABLE_EMAIL.code, DISPOSABLE_EMAIL.error]);
  // another check constraint on leads (23514 too) is not called a temporary inbox
  const other = table([], { failInsert: { code: '23514', message: 'new row for relation "leads" violates check constraint "leads_emirate_check"' } });
  const r2 = await createCompany(other.admin, 'qd-aub990b4a-tmp2@example.invalid', FORM, deps());
  assertEquals([r2.status, r2.body.code], [500, REGISTER_FAILED.code]);
});

Deno.test('any other refusal answers a stable code: never the database\'s own sentence', async () => {
  const { admin } = table([], { failInsert: { code: 'XX000', message: 'internal error: something only the log should see' } });
  const r = await createCompany(admin, 'qd-aub990b4a-new9@example.invalid', FORM, deps());
  assertEquals([r.status, r.body.code, r.body.error], [500, REGISTER_FAILED.code, REGISTER_FAILED.error]);
  assert(!JSON.stringify(r.body).includes('internal error'));
  const e = table([], { failInsert: { code: '23505', message: 'duplicate key value violates unique constraint "uq_leads_email_lower"' } });
  const r2 = await createCompany(e.admin, 'qd-aub990b4a-new9@example.invalid', FORM, deps());
  assertEquals([r2.status, r2.body.code], [409, EMAIL_ALREADY_REGISTERED.code], 'an e-mail clash the lookup could not see (a race) is still the 409');
  assert(!JSON.stringify(r2.body).includes('duplicate key'));
});

Deno.test('the account that already manages a company is told so (unchanged)', async () => {
  const { admin } = table([{ ...INVITED, claimed: true, claimed_by: 'qd-aub990b4a-lead7@example.invalid' }]);
  const r = await createCompany(admin, 'qd-aub990b4a-lead7@example.invalid', FORM, deps());
  assertEquals([r.status, r.body.code], [409, 'company_exists']);
});

// RULING 1672 (12 Nov 2026): the portal sends no company name and no category; the trade licence names the company later.
const NO_NAME_FORM = { role: 'supplier', lang: 'en', first_touch: null };
Deno.test('ruling 1672: a registration with no name typed is its own row with no name and no category, and nothing is looked up by an empty name', async () => {
  const waiting = { id: 7, company_name: '', email: 'qd-r1672-first@example.invalid', claimed: true, claimed_by: 'qd-r1672-first@example.invalid', source: 'self_registered' };
  const listing = { id: 8, company_name: 'ZZ DEMO R1672 Listed Trading LLC', emirate: 'Dubai', claimed: false, claimed_by: null };
  const { t, admin } = table([waiting, listing]);
  const r = await createCompany(admin, 'qd-r1672-second@example.invalid', NO_NAME_FORM, deps());
  assertEquals(r.status, 200, 'another registration still waiting for its licence is not "the same company": ' + JSON.stringify(r.body));
  const row = t.rows.find((x) => x.email === 'qd-r1672-second@example.invalid')!;
  assertEquals([row.company_name, row.sector, row.claimed, row.source], ['', null, true, 'self_registered']);
  assertEquals(t.actions.length, 0, 'no listing is flagged on a name nobody typed (the gate flags it when the licence names the company)');
  assertEquals([t.rows.find((x) => x.id === 8)!.claimed_by, t.updates], [null, 0], 'no listing is touched');
});

Deno.test('ruling 1672: an invited lead claimed by its proven address keeps its listing\'s own name when none is typed', async () => {
  const { t, admin } = table([INVITED]);
  const r = await createCompany(admin, 'qd-aub990b4a-lead7@example.invalid', NO_NAME_FORM, deps());
  assertEquals([r.status, r.body.id, t.inserts], [200, 151618, 0], JSON.stringify(r.body));
  assertEquals([t.rows[0].company_name, t.rows[0].claimed_by, t.rows[0].sector], ['ZZ DEMO S7 Aluminium LLC', 'qd-aub990b4a-lead7@example.invalid', null]);
});

Deno.test('ruling 1672: a name that IS sent (an older portal build) is still checked as before', async () => {
  const { admin } = table([INVITED, { id: 5, company_name: 'ZZ DEMO S7 Aluminium', email: 'qd-x-y@example.invalid', claimed: true, claimed_by: 'qd-x-y@example.invalid' }]);
  const short = await createCompany(admin, 'qd-r1672-third@example.invalid', { ...NO_NAME_FORM, company_name: 'Z' }, deps());
  assertEquals([short.status, short.body.code], [400, 'enter_company']);
  const twin = await createCompany(admin, 'qd-r1672-third@example.invalid', { ...NO_NAME_FORM, company_name: 'ZZ DEMO S7 Aluminium' }, deps());
  assertEquals([twin.status, twin.body.code], [409, 'company_already_registered']);
});

Deno.test('planCreateCompany: the decision table', () => {
  const u = { id: 1, claimed: false, claimed_by: null };
  assertEquals(planCreateCompany({ ownCompany: true, emailLeads: [u], emailProven: true }).kind, 'company_exists');
  assertEquals(planCreateCompany({ ownCompany: false, emailLeads: [u], emailProven: true }).kind, 'claim_invited');
  assertEquals(planCreateCompany({ ownCompany: false, emailLeads: [u], emailProven: false }).kind, 'verify_email_first');
  assertEquals(planCreateCompany({ ownCompany: false, emailLeads: [{ ...u, claimed_by: 'x@example.invalid' }], emailProven: true }).kind, 'email_taken');
  assertEquals(planCreateCompany({ ownCompany: false, emailLeads: [u, { ...u, id: 2 }], emailProven: true }).kind, 'email_taken');
  assertEquals(planCreateCompany({ ownCompany: false, emailLeads: [], emailProven: true }).kind, 'insert');
});

// REVIEW OF #1712 (28 Oct 2026). Each of these failed against the PR as first pushed: the claim trusted any "used" code
// row and any session, a failed look-up read as "no lead", a sanctioned listing could be claimed, and the form's constant
// role overwrote the listing's own.
const jwtWith = (claims: unknown) => ['eyJhbGciOiJIUzI1NiJ9', btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(claims))))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''), 'sig'].join('.');

Deno.test('a session opened by a PASSWORD never claims an invited listing, even when a used code row exists for the address', async () => {
  const { t, admin } = table([INVITED]);
  const r = await createCompany(admin, INVITED.email, FORM, deps(true, { byCode: false }));
  assertEquals([r.status, r.body.code], [403, VERIFY_EMAIL_FIRST.code]);
  assertEquals([t.inserts, t.updates, t.rows[0].claimed_by, t.rows[0].claimed], [0, 0, null, false]);
});

Deno.test('the address that claims is the session\'s: another company\'s e-mail, id or token in the BODY is ignored', async () => {
  const { t, admin } = table([INVITED]);
  const attacker = 'qd-aub990b4a-attacker@example.invalid';
  const r = await createCompany(admin, attacker, { ...FORM, company_name: 'ZZ DEMO S7 Attacker Co', email: INVITED.email, claimed_by: INVITED.email,
    owner_email: INVITED.email, leads_id: INVITED.id, id: INVITED.id, claim_token: INVITED.claim_token, t: INVITED.claim_token }, deps());
  assertEquals(r.status, 200, JSON.stringify(r.body));
  assert(r.body.id !== INVITED.id, 'the attacker was handed the invited listing');
  const victim = t.rows.find((x) => x.id === INVITED.id)!;
  assertEquals([victim.claimed, victim.claimed_by, victim.company_name, victim.claim_token], [false, null, INVITED.company_name, INVITED.claim_token], 'the invited listing was touched');
  const mine = t.rows.find((x) => x.id === r.body.id)!;
  assertEquals([mine.email, mine.claimed_by], [attacker, attacker], 'the new row is not the session\'s own');
});

Deno.test('a look-up the database fails answers register_failed — never "this e-mail already has an account"', async () => {
  for (const col of ['email', 'claimed_by']) {
    const { t, admin } = table([INVITED], { failSelectOn: col });
    const r = await createCompany(admin, INVITED.email, FORM, deps());
    assertEquals([r.status, r.body.code], [500, REGISTER_FAILED.code], `look-up on ${col}`);
    assert(!JSON.stringify(r.body).includes('statement timeout'), 'the database sentence reached the body');
    assertEquals([t.inserts, t.updates], [0, 0], `look-up on ${col}: something was written`);
  }
});

Deno.test('a listing under a sanctions ban is never claimed (the a01 trigger excludes the row itself)', async () => {
  const { t, admin } = table([INVITED]);
  const r = await createCompany(admin, INVITED.email, FORM, deps(true, { sanctioned: [INVITED.id] }));
  assertEquals([r.status, r.body.code], [403, 'registration_refused']);
  assertEquals([t.inserts, t.updates, t.rows[0].claimed_by], [0, 0, null]);
});

Deno.test('the claim keeps the listing\'s own trade description; the form\'s constant role fills only an empty one', async () => {
  const { t, admin } = table([{ ...INVITED, business_role: 'manufacturer' }]);
  const r = await createCompany(admin, INVITED.email, FORM, deps());
  assertEquals([r.status, t.rows[0].business_role, t.rows[0].claimed_by], [200, 'manufacturer', INVITED.email]);
});

Deno.test('sessionOpenedByCode reads how THIS session was opened from the verified token\'s amr', () => {
  assertEquals(sessionOpenedByCode(jwtWith({ amr: [{ method: 'otp', timestamp: 1 }] })), true, 'login_otp\'s sessions');
  assertEquals(sessionOpenedByCode(jwtWith({ amr: [{ method: 'magiclink', timestamp: 1 }] })), true);
  assertEquals(sessionOpenedByCode(jwtWith({ amr: [{ method: 'password', timestamp: 1 }] })), false, 'a password session');
  assertEquals(sessionOpenedByCode(jwtWith({ sub: 'x' })), false, 'no amr');
  assertEquals(sessionOpenedByCode(jwtWith({ amr: 'otp' })), false, 'amr not a list');
  // non-ASCII metadata and base64url's - and _ survive the decode
  assertEquals(sessionOpenedByCode(jwtWith({ user_metadata: { name: 'مورّد ?>>?' }, amr: [{ method: 'otp' }] })), true);
  for (const junk of ['', 'abc', 'a.%%%.c', 'a..c', 'a.' + btoa('not json') + '.c']) assertEquals(sessionOpenedByCode(junk), false, junk);
});

// THE FORM OPENS ON CREATE_COMPANY'S OWN ANSWER (11 Nov 2026, customer_support; registration certification free round 6,
// run 2 J1 desktop: "Create company" opened the registration form in 3,907 ms against 3,000, create_company 1,810 ms and
// then `me` 1,581 ms in series). The answer carries the supplier `me` would read, so the portal asks nothing after it,
// and the four look-ups before the write are one wave instead of four round trips in series.
// deno-lint-ignore no-explicit-any
const meOf = (admin: any, email: string) => (): Promise<Row | null> =>
  admin.from('leads').select('id,company_name,claimed_by').eq('claimed_by', email).maybeSingle().then((r: { data: Row | null }) => r.data);

Deno.test('a registered company is answered with the supplier `me` would read: the insert and the invited claim', async () => {
  const fresh = table([INVITED]);
  const a = await createCompany(fresh.admin, 'qd-aub990b4a-new9@example.invalid', { ...FORM, company_name: 'ZZ DEMO S7 Fresh' },
    { ...deps(), readSupplier: meOf(fresh.admin, 'qd-aub990b4a-new9@example.invalid') });
  assertEquals(a.status, 200, JSON.stringify(a.body));
  const s = a.body.supplier as Row;
  assert(s, 'create_company answered without the supplier: the portal has to ask `me` before the form opens');
  assertEquals([s.id, s.company_name, s.claimed_by], [a.body.id, 'ZZ DEMO S7 Fresh', 'qd-aub990b4a-new9@example.invalid']);
  const inv = table([INVITED]);
  const b = await createCompany(inv.admin, INVITED.email, FORM, { ...deps(), readSupplier: meOf(inv.admin, INVITED.email) });
  assertEquals([b.status, (b.body.supplier as Row)?.id, (b.body.supplier as Row)?.company_name], [200, 151618, 'ZZ DEMO S7 Aluminium']);
});

Deno.test('a supplier read that fails leaves `supplier` out and the registration stands (the portal asks `me` as before)', async () => {
  const { t, admin } = table([INVITED]);
  const r = await createCompany(admin, 'qd-aub990b4a-new10@example.invalid', { ...FORM, company_name: 'ZZ DEMO S7 Read Fails' },
    { ...deps(), readSupplier: () => Promise.reject(new Error('connection reset')) });
  assertEquals([r.status, r.body.ok, 'supplier' in r.body, t.inserts], [200, true, false, 1]);
  const other = await createCompany(table([]).admin, 'qd-aub990b4a-new11@example.invalid', { ...FORM, company_name: 'ZZ DEMO S7 Someone Else' },
    { ...deps(), readSupplier: () => Promise.resolve({ id: 1, company_name: 'not this one' }) });
  assertEquals('supplier' in other.body, false, 'a row that is not the one just written is never handed back as his');
});

Deno.test('the look-ups before the write are one wave, not four round trips in series', async () => {
  const { t, admin } = table([INVITED]);
  let now = 0, most = 0, beforeWrite = 0;
  const slow = async <T>(f: () => Promise<T> | T): Promise<T> => {
    now++; most = Math.max(most, now); if (t.inserts + t.updates === 0) beforeWrite = Math.max(beforeWrite, now);
    await new Promise((r) => setTimeout(r, 5));
    try { return await f(); } finally { now--; }
  };
  const timed = {
    from(n: string) {
      const q = admin.from(n) as Record<string, (...a: unknown[]) => unknown>;
      const w: Record<string, unknown> = new Proxy(q, { get(target, k: string) {
        if (k === 'maybeSingle') return () => slow(() => target.maybeSingle() as Promise<unknown>);
        if (k === 'then') return (res: (v: unknown) => unknown, rej: (e: unknown) => unknown) => slow(() => new Promise((r) => (target.then as (f: (v: unknown) => void) => void)(r))).then(res, rej);
        return (...a: unknown[]) => { target[k](...a); return w; };
      } });
      return w;
    },
  };
  const r = await createCompany(timed, 'qd-aub990b4a-new12@example.invalid', { ...FORM, company_name: 'ZZ DEMO S7 One Wave' },
    { ...deps(), emailProven: () => slow(() => true) });
  assertEquals([r.status, t.inserts], [200, 1], JSON.stringify(r.body));
  assert(beforeWrite >= 4, `only ${beforeWrite} look-up(s) were in flight together before the write: they are read one after another`);
});

// AFTER THE WRITE, ONE WAVE (15 Nov 2026, customer_support; the code e-mail to the registration form measured 3,026 and 3,078 ms
// against 3,000). The new-company path waited on the insert, then a touch UPDATE (portal_updated_at only), then the registration
// state, then the first touch beside the supplier read: four calls in series. The insert writes portal_updated_at itself, so the
// state is read without a touch, beside the first touch and the supplier read. The claim's own update touches the row the same way.
Deno.test('after the write, one wave: the registration state, the first touch and the supplier read leave together, and no touch UPDATE', async () => {
  for (const which of ['insert', 'claim'] as const) {
    const { t, admin } = table([INVITED]);
    let now = 0, most = 0; const touches: (boolean | undefined)[] = [];
    const slow = async <T>(f: () => T): Promise<T> => { now++; most = Math.max(most, now); await new Promise((r) => setTimeout(r, 5)); try { return f(); } finally { now--; } };
    const email = which === 'claim' ? INVITED.email : 'qd-aub990b4a-new13@example.invalid';
    const before = Date.now();
    const r = await createCompany(admin, email, which === 'claim' ? FORM : { ...FORM, company_name: 'ZZ DEMO S7 Wave After' }, {
      ...deps(),
      setRegistration: (_id: number, touch?: boolean) => { touches.push(touch); return slow(() => ({ status: 'not_due' })); },
      recordFirstTouch: () => slow(() => undefined),
      readSupplier: () => slow(() => t.rows.find((x) => x.claimed_by === email) ?? null),
    });
    assertEquals(r.status, 200, JSON.stringify(r.body));
    assertEquals(r.body.registration, { status: 'not_due' }, which + ': the answer carries the registration state as before');
    assert(r.body.supplier, which + ': the answer carries the supplier');
    assertEquals(most, 3, `${which}: only ${most} of the three reads after the write were in flight together`);
    assertEquals(touches, [false], which + ': the state is read without a second UPDATE of the row');
    const row = t.rows.find((x) => x.claimed_by === email)!;
    assert(typeof row.portal_updated_at === 'string' && Date.parse(String(row.portal_updated_at)) >= before - 1000, which + ': portal_updated_at is written with the row, as the touch wrote it');
    assertEquals([t.inserts, t.updates], which === 'claim' ? [0, 1] : [1, 0], which + ': one write, and only one');
  }
});

// lib/registration.ts setRegistration as create_company now calls it: touch=false sends no UPDATE and reads the state only.
Deno.test('setRegistration(id, false) issues no UPDATE: the state rpc alone', async () => {
  const src = await Deno.readTextFile(new URL('./lib/registration.ts', import.meta.url));
  assert(/if \(touch\) await admin\.from\('leads'\)\.update\(\{ portal_updated_at: /.test(src), 'setRegistration no longer skips its UPDATE when touch is false');
});

// H10 (12 Nov 2026, customer_support; founder ruling 1645, browser perfection walk of supplier registration). MEASURED on
// production: an unclaimed directory listing (lead 158191) existed; a public sign-up with another address typed the same name;
// a second lead was created (158192, self_registered) and the listing stayed invitable. These replay it and its edges.
const LISTED = { id: 158191, company_name: 'ZZ DEMO Walk Listed Trading L.L.C.', emirate: 'Dubai', email: null, website: null, claimed: false,
  claimed_by: null, is_demo: true, invite_status: 'sent', claim_token: '00000000-0000-4000-8000-000000158191', source: 'directory', business_role: 'trader' };
const WALKER = 'qd-walk-h10@example.invalid';
const LISTED_FORM = { company_name: 'ZZ DEMO Walk Listed Trading LLC', emirate: 'Dubai', category: 'steel', role: 'supplier', first_touch: null };

Deno.test('H10: the listing with the same legal name and emirate is NOT taken: a new row, the listing untouched, a person asked to merge', async () => {
  const { t, admin } = table([LISTED]);
  calls.reg.length = 0;
  const r = await createCompany(admin, WALKER, LISTED_FORM, deps());
  assertEquals(r.status, 200, JSON.stringify(r.body));
  assertEquals([t.inserts, t.rows.length, t.updates], [1, 2, 0], 'the listing was written to');
  assert(r.body.id !== 158191 && !('claimed_listing' in r.body));
  assertEquals([t.rows[0].claimed, t.rows[0].claimed_by, t.rows[0].company_name], [false, null, LISTED.company_name], 'the listing changed');
  assertEquals(calls.reg, [r.body.id]);
  assertEquals(t.actions.length, 1);
  const a = t.actions[0];
  assertEquals([a.agent, a.kind, a.status, a.target_id], ['it_engineer', 'possible_duplicate_listing', 'pending', String(r.body.id)]);
  assertEquals((a.detail as Row).why, 'name and emirate agree with one listing; a person confirms before it is merged');
  assertEquals(((a.detail as Row).listings as Row[]).map((l) => l.id), [158191]);
});

Deno.test('H10: a hand-made request (public name, emirate, a gmail address) never updates a REAL listing: a new row and a flag', async () => {
  const real = { ...LISTED, id: 9101, company_name: 'Gulf Panels Trading LLC', email: 'info@gulfpanels.ae', website: null, is_demo: false };
  const { t, admin } = table([real]);
  const r = await createCompany(admin, 'someone.else@gmail.com', { company_name: 'Gulf Panels Trading LLC', emirate: 'Dubai', category: 'steel', role: 'supplier', first_touch: null }, deps());
  assertEquals([r.status, t.inserts, t.updates], [200, 1, 0], JSON.stringify(r.body));
  assertEquals([t.rows[0].claimed, t.rows[0].claimed_by, t.rows[0].email], [false, null, 'info@gulfpanels.ae'], 'a real company\'s listing went to whoever typed its name');
  assertEquals(t.actions.map((x) => x.kind), ['possible_duplicate_listing']);
});

Deno.test('H10: a NEAR match (same name but for the legal form) is flagged for the IT seat and NOT merged', async () => {
  const { t, admin } = table([LISTED]);
  const r = await createCompany(admin, WALKER, { ...LISTED_FORM, company_name: 'ZZ DEMO Walk Listed Trading' }, deps());
  assertEquals([r.status, t.inserts, t.rows.length], [200, 1, 2], JSON.stringify(r.body));
  assertEquals([t.rows[0].claimed_by, t.rows[0].claimed], [null, false], 'the listing was taken on a near match');
  assertEquals(t.actions.length, 1);
  const a = t.actions[0];
  assertEquals([a.agent, a.kind, a.status, a.target_id], ['it_engineer', 'possible_duplicate_listing', 'pending', String(r.body.id)]);
  assertEquals(((a.detail as Row).listings as Row[]).map((l) => l.id), [158191]);
});

Deno.test('H10: the same name in ANOTHER emirate, an unknown emirate, two listings, an unproven session: flagged, never claimed', async () => {
  for (const [label, rows, form, d] of [
    ['other emirate', [LISTED], { ...LISTED_FORM, emirate: 'Sharjah' }, deps()],
    ['unknown emirate', [{ ...LISTED, emirate: 'Al Quoz Industrial Area 1' }], LISTED_FORM, deps()],
    ['two listings', [LISTED, { ...LISTED, id: 158192, claim_token: null }], LISTED_FORM, deps()],
    ['password session', [LISTED], LISTED_FORM, deps(true, { byCode: false })],
    ['another company domain', [{ ...LISTED, website: 'https://www.walk-listed.ae' }], LISTED_FORM, deps()],
    ['another licence number', [{ ...LISTED, trade_license_no: 'CN-1234567' }], { ...LISTED_FORM, trade_license_no: 'CN-7654321' }, deps()],
  ] as const) {
    const { t, admin } = table(rows as unknown as Row[]);
    const r = await createCompany(admin, WALKER, form as unknown as Row, d);
    assertEquals([r.status, t.inserts], [200, 1], `${label}: ${JSON.stringify(r.body)}`);
    assert(t.rows.filter((x) => x.id !== r.body.id).every((x) => x.claimed_by == null), `${label}: a listing was claimed`);
    assertEquals(t.actions.map((x) => x.kind), ['possible_duplicate_listing'], `${label}: the possible duplicate was not flagged`);
  }
});

Deno.test('H10: an address on the listing\'s own company domain is the strongest agreement the planner records (still only a flag)', () => {
  const plan = planListingMatch({ name: 'Walk Listed Trading LLC', emirate: 'Dubai', email: 'gm@walk-listed.ae', proven: true,
    listings: [{ id: 7, company_name: 'Walk Listed Trading L.L.C.', emirate: 'Office 505, Business Bay, Dubai, UAE', email: 'info@walk-listed.ae', claimed: false, claimed_by: null, is_demo: false }] });
  assertEquals(plan.kind, 'strong');
  assertEquals(plan.kind === 'strong' && plan.basis.domain_agrees, true);
});

Deno.test('H10: a CLAIMED company\'s name is still refused, in any spelling, and an unclaimed twin listing is not handed over instead', async () => {
  const taken = { id: 5001, company_name: 'ZZ DEMO Taken Steel LLC', emirate: 'Dubai', email: 'qd-owner@example.invalid', claimed: true, claimed_by: 'qd-owner@example.invalid', is_demo: true };
  for (const typed of ['ZZ DEMO Taken Steel LLC', 'zz demo taken steel l.l.c.']) {
    const { t, admin } = table([taken, { ...LISTED, id: 5002, company_name: 'ZZ DEMO Taken Steel LLC' }]);
    const r = await createCompany(admin, WALKER, { ...LISTED_FORM, company_name: typed }, deps());
    assertEquals([r.status, r.body.code], [409, 'company_already_registered'], typed);
    assertEquals([t.inserts, t.rows[1].claimed_by], [0, null], typed);
  }
});

Deno.test('H10: a demo row is never matched to a real one, either way round', async () => {
  // a fixture registrant typing a real company's name
  { const { t, admin } = table([{ ...LISTED, id: 9001, company_name: 'Gulf Panels LLC', is_demo: false }]);
    const r = await createCompany(admin, WALKER, { ...LISTED_FORM, company_name: 'Gulf Panels LLC' }, deps());
    assertEquals([r.status, t.inserts, t.rows[0].claimed_by, t.actions.length], [200, 1, null, 0], JSON.stringify(r.body)); }
  // a real registrant typing the name a fixture listing carries
  const plan = planListingMatch({ name: 'Gulf Panels LLC', emirate: 'Dubai', email: 'owner@gulfpanels.ae', proven: true,
    listings: [{ id: 9002, company_name: 'Gulf Panels LLC', emirate: 'Dubai', email: 'qd-x@example.invalid', claimed: false, claimed_by: null, is_demo: true }] });
  assertEquals(plan.kind, 'none');
});

Deno.test('companyNameKey is the twin of public.fn_company_registration_name_key (keys read from production, 12 Nov 2026)', () => {
  // 15 named cases below; the same comparison over 2,000 production names matched 2,000 of 2,000 the same day.
  const cases: [string, string][] = [['Al-Bariq Trading L.L.C.', 'al bariq trading llc'], ['GOLDEN OCEAN BUILDING MATERIALS TRADING &#038; ELEC', 'golden ocean building materials trading and elec'],
    ['A & B Glass Co.', 'a and b glass co'], ["Mu'min Establishment", 'mumin est'], ['Gulf Star FZ-LLC', 'gulf star fzllc'], ['Gulf Star F.Z.E', 'gulf star fze'],
    ['Gulf Star (L.L.C)', 'gulf star llc'], ['النور للمقاولات ذ.م.م', 'النور للمقاولات llc'], ['مؤسسة الإمارات ش.ذ.م.م', 'موسسه الامارات شذمم'], ['Delta F Z C O', 'delta fzco'],
    ['  Twin   Spaces  Company ', 'twin spaces co'], ['Café Ünïcode LLC', 'café ünïcode llc'], ['Rock&amp;Roll Co', 'rock and roll co'], ['١٢٣ Steel', '123 steel'], ['...', '']];
  for (const [n, k] of cases) assertEquals(companyNameKey(n) ?? '', k, n);
});

Deno.test('emirateOf: an emirate, or an address naming exactly one; anything else is unknown', () => {
  assertEquals(['Dubai', 'abu dhabi', 'Office 505, Business Bay, Dubai, UAE', 'Al Quoz Industrial Area 1', '', null, 'Dubai or Sharjah', 'RAS AL KHAIMAH'].map(emirateOf),
    ['Dubai', 'Abu Dhabi', 'Dubai', null, null, null, null, 'Ras Al Khaimah']);
});

Deno.test('H10 review 2: a page cut at its limit with no twin in it is flagged, never "none"', () => {
  const page = Array.from({ length: 300 }, (_, i) => ({ id: i + 1, company_name: `Trading Partner ${i} LLC`, emirate: 'Dubai', claimed: false, claimed_by: null, is_demo: false }));
  assertEquals(planListingMatch({ name: 'Alpha Trading LLC', emirate: 'Dubai', email: 'gm@alpha.ae', proven: true, listings: page, truncated: false }).kind, 'none');
  const p = planListingMatch({ name: 'Alpha Trading LLC', emirate: 'Dubai', email: 'gm@alpha.ae', proven: true, listings: page, truncated: true });
  assertEquals(p.kind, 'flag');
});

Deno.test('H10 review 2: the look-up narrows by the two longest words, and "Mu\'min" is read by "Mumin"', async () => {
  assertEquals(listingProbes('Mumin General Trading LLC').length, 2);
  assertEquals(listingProbes('A & B Co'), []);
  const rows = [{ ...LISTED, id: 9201, company_name: "ZZ DEMO Mu'min Establishment", emirate: 'Dubai' }, { ...LISTED, id: 9202, company_name: 'ZZ DEMO Other Trading', emirate: 'Dubai' }];
  const { t, admin } = table(rows);
  const r = await createCompany(admin, WALKER, { ...LISTED_FORM, company_name: 'ZZ DEMO Mumin Est' }, deps());
  assertEquals([r.status, t.inserts, t.updates], [200, 1, 0]);
  assertEquals(((t.actions[0]?.detail as Row)?.listings as Row[] | undefined)?.map((l) => l.id), [9201], 'the apostrophe hid the twin');
  for (const re of listingProbes('ZZ DEMO Mumin Est')) assert(new RegExp(re, 'iu').test("ZZ DEMO Mu'min Establishment"), re);
  for (const re of listingProbes('مؤسسة الامارات')) assert(new RegExp(re, 'iu').test('مؤسسة الإمارات'), re);
});
