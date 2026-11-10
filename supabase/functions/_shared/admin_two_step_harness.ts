// TEST SUPPORT ONLY — imported by the <fn>/two_step.test.ts files, never by a function (security audit 10 Nov 2026,
// item 1; it_engineer). It drives a function's REAL handler over a stubbed auth server and a stubbed PostgREST, so a
// test proves what the deployed code does with an aal1 admin, an aal2 admin and a signed-in non-admin.
//
// Nothing here is real, and nothing can reach anything real: the project host is `stub.invalid`, every other host
// answers 503 from the stub, the identities are ZZ DEMO addresses under example.invalid, and every write the handler
// attempts is recorded rather than performed.
export const ADMIN = { id: '0b0b0b0b-0000-4000-8000-0000000ad001', email: 'zz-demo-admin@example.invalid' };
export const NEW_ADMIN = { id: '0b0b0b0b-0000-4000-8000-0000000ad002', email: 'zz-demo-new-admin@example.invalid' };
export const CUSTOMER = { id: '0b0b0b0b-0000-4000-8000-0000000c0001', email: 'zz-demo-customer@example.invalid' };
export const CUSTOMER_ROW_ID = '0b0b0b0b-0000-4000-8000-0000000c0101';

const FACTORS: Record<string, unknown[]> = {
  [ADMIN.id]: [{ id: 'zz-demo-factor', factor_type: 'totp', status: 'verified' }],
  [NEW_ADMIN.id]: [],
  [CUSTOMER.id]: [],
};
const USERS = [ADMIN, NEW_ADMIN, CUSTOMER];

const b64u = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
/** A session token of the given assurance level for one of the ZZ DEMO identities. */
export function token(who: { id: string }, aal: 'aal1' | 'aal2'): string {
  const now = Math.floor(Date.now() / 1000);
  return `${b64u({ alg: 'ES256', typ: 'JWT' })}.${b64u({ sub: who.id, aal, role: 'authenticated', exp: now + 3600, iat: now })}.zz-demo-signature`;
}

export const writes: string[] = [];

function payloadOf(auth: string): Record<string, unknown> | null {
  try { return JSON.parse(atob((auth.replace(/^Bearer\s+/i, '').split('.')[1] || '').replace(/-/g, '+').replace(/_/g, '/'))); } catch (_e) { return null; }
}

/** Installs the stubs, captures the handler `Deno.serve` is given, imports the module and returns a caller. */
export async function loadHandler(moduleUrl: URL): Promise<(body: Record<string, unknown>, bearer?: string) => Promise<Response>> {
  Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const r = new Request(input, init);
    const u = new URL(r.url);
    if (u.host !== 'stub.invalid') return new Response('{"error":"stubbed: no real host is reachable from this test"}', { status: 503 });
    const json = (v: unknown, s = 200) => new Response(JSON.stringify(v), { status: s, headers: { 'Content-Type': 'application/json' } });
    if (u.pathname === '/auth/v1/user') {
      const p = payloadOf(r.headers.get('Authorization') || '');
      const user = USERS.find((x) => x.id === p?.sub);
      return user ? json({ ...user, aud: 'authenticated', factors: FACTORS[user.id] }) : json({ code: 403, msg: 'invalid JWT' }, 403);
    }
    if (r.method !== 'GET' && r.method !== 'HEAD' && !u.pathname.startsWith('/rest/v1/rpc/')) writes.push(`${r.method} ${u.pathname}`);
    const one = (r.headers.get('accept') || '').includes('vnd.pgrst.object');
    const rows = (v: unknown[]) => json(one ? (v[0] ?? null) : v);
    if (u.pathname === '/rest/v1/app_secrets') {
      return u.searchParams.get('key') === 'eq.admin_emails' ? rows([{ value: `${ADMIN.email}, ${NEW_ADMIN.email}` }]) : rows([]);
    }
    if (u.pathname === '/rest/v1/customers') {
      const q = [...u.searchParams.values()].join(' ').toLowerCase();
      return rows(q.includes(CUSTOMER.email) ? [{ id: CUSTOMER_ROW_ID }] : []);
    }
    if (u.pathname.startsWith('/rest/v1/rpc/')) return json(null);
    return rows([]);
  }) as typeof fetch;
  let handler!: (req: Request) => Promise<Response>;
  // deno-lint-ignore no-explicit-any
  (Deno as any).serve = (a: unknown, b?: unknown) => { handler = (typeof a === 'function' ? a : b) as typeof handler; return {}; };
  await import(moduleUrl.href);
  return (body, bearer) => handler(new Request('https://x.invalid/fn', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://quotesdone.com', ...(bearer ? { Authorization: 'Bearer ' + bearer } : {}) },
    body: JSON.stringify(body),
  }));
}

/** The three answers every admin door must give. `allowed` decides what "got past the door" looks like for one function. */
export function twoStepCases(name: string, moduleUrl: URL, opts: {
  body: Record<string, unknown>;
  /** What an admin got before this change, and an aal2 admin still gets (measured on origin/main, 10 Nov 2026). */
  admin: (r: Response, j: Record<string, unknown>) => void;
  /** What a signed-in non-admin got before this change, and still gets, on an aal1 or an aal2 session. */
  nonAdmin: (r: Response, j: Record<string, unknown>) => void;
}) {
  let call!: Awaited<ReturnType<typeof loadHandler>>;
  const ready = loadHandler(moduleUrl).then((c) => { call = c; });
  const read = async (r: Response) => { const t = await r.text(); try { return JSON.parse(t) as Record<string, unknown>; } catch (_e) { return { _text: t } as Record<string, unknown>; } };
  const san = { sanitizeOps: false, sanitizeResources: false };
  Deno.test({ name: `${name}: an admin whose session has one factor (aal1) gets 403 two_step_required, step challenge`, ...san, fn: async () => {
    await ready;
    const r = await call(opts.body, token(ADMIN, 'aal1'));
    const j = await read(r);
    if (r.status !== 403 || j.error !== 'two_step_required' || j.step !== 'challenge') throw new Error(`expected 403 two_step_required/challenge, got ${r.status} ${JSON.stringify(j).slice(0, 300)}`);
    if (!String(j.message || '').startsWith('Two-step sign-in required')) throw new Error('the 403 must name the step');
  } });
  Deno.test({ name: `${name}: an admin with no authenticator enrolled is sent to enrolment, not refused forever`, ...san, fn: async () => {
    await ready;
    const r = await call(opts.body, token(NEW_ADMIN, 'aal1'));
    const j = await read(r);
    if (r.status !== 403 || j.error !== 'two_step_required' || j.step !== 'enrol' || !String(j.url || '').endsWith('/admin')) throw new Error(`expected 403 two_step_required/enrol, got ${r.status} ${JSON.stringify(j).slice(0, 300)}`);
  } });
  Deno.test({ name: `${name}: an admin with a two-step session (aal2) is let through`, ...san, fn: async () => {
    await ready;
    const r = await call(opts.body, token(ADMIN, 'aal2'));
    const j = await read(r);
    if (r.status === 401 || j.error === 'two_step_required' || j.error === 'unauthorized' || j.error === 'forbidden') throw new Error(`an aal2 admin was refused: ${r.status} ${JSON.stringify(j).slice(0, 300)}`);
    opts.admin(r, j);
  } });
  Deno.test({ name: `${name}: a signed-in non-admin (aal2, and aal1 as every customer signs in) gets exactly what it got before`, ...san, fn: async () => {
    await ready;
    for (const aal of ['aal2', 'aal1'] as const) {
      const r = await call(opts.body, token(CUSTOMER, aal));
      opts.nonAdmin(r, await read(r));
    }
  } });
}
