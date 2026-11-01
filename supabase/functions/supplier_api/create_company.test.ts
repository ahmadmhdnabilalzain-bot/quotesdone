// AN INVITED SUPPLIER WHO REGISTERS ON THE WEBSITE CLAIMS HIS INVITED LISTING (28 Oct 2026, sales_engineer; ledger 1401
// audit, scenario S7). Behavioural: create_company.ts runs against an in-memory `leads` that refuses what production
// refuses (uq_leads_email_lower on lower(email), leads_claimed_by_lower_uidx, leads_claimed_company_name_uidx).
//
// THE INPUT THAT FAILED ON PRODUCTION (07:54Z, run aub990b4a): an unclaimed invited lead holds the address the supplier
// signs up with; create_company inserted a second row for it and answered HTTP 500 with the Postgres sentence
// "duplicate key value violates unique constraint "uq_leads_email_lower"". The first test replays it.
//   deno test --no-lock supabase/functions/supplier_api/create_company.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createCompany, EMAIL_ALREADY_REGISTERED, planCreateCompany, REGISTER_FAILED, sessionOpenedByCode, VERIFY_EMAIL_FIRST } from './create_company.ts';

type Row = Record<string, unknown>;
const low = (v: unknown) => String(v ?? '').trim().toLowerCase();
const nameKey = (v: unknown) => low(v).replace(/\s+/g, ' ');

/** An in-memory leads table with production's three unique rules, and the handful of supabase-js calls the door makes. */
function table(rows: Row[], opts: { failInsert?: { code: string; message: string }; failSelectOn?: string } = {}) {
  const t = { rows: rows.map((r) => ({ ...r })), inserts: 0, updates: 0, nextId: 900001 };
  const clash = (row: Row, self: Row | null): string | null => {
    for (const o of t.rows) {
      if (o === self) continue;
      if (row.email && o.email && low(o.email) === low(row.email)) return 'uq_leads_email_lower';
      if (row.claimed_by && o.claimed_by && low(o.claimed_by) === low(row.claimed_by)) return 'leads_claimed_by_lower_uidx';
      if (row.claimed && o.claimed && nameKey(o.company_name) === nameKey(row.company_name)) return 'leads_claimed_company_name_uidx';
    }
    return null;
  };
  const err = (idx: string) => ({ code: '23505', message: `duplicate key value violates unique constraint "${idx}"`, details: null });
  const admin = {
    from(name: string) {
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
        ilike(c: string, pat: string) { on.push(c); const want = pat.replace(/\\([\\%_])/g, '$1'); f.push((r) => low(r[c]) === low(want)); return q; },
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
