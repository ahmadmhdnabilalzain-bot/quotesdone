// deno test supabase/functions/it_engineer/exo_transport_rule.test.ts
// The Exchange Online probe and the transport rule (exo_transport_rule.ts), every branch offline: the probe asks
// for the Exchange scope and returns only `roles`; no token or secret ever appears in an answer; without
// Exchange.ManageAsApp the write makes NO Exchange call; with it, an existing rule of our name is never recreated,
// a missing one is created with the right parameters and only the read-back says `created`; and the actions answer
// the service_role only.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import {
  EXO_SCOPE, GRAPH_SCOPE, MANAGE_AS_APP, RULE_FROM, RULE_HEADER_NAME, RULE_HEADER_VALUE, RULE_NAME,
  applyRule, isServiceRole, probe, rolesOf, ruleDiff, type Fetch,
} from './exo_transport_rule.ts';

const SECRET = 'zz-demo-client-secret-value-1234567890';
const TENANT = '00000000-0000-0000-0000-0000000000aa';
const ENV: Record<string, string> = { MS_TENANT_ID: TENANT, MS_CLIENT_ID: 'zz-demo-client-id', MS_CLIENT_SECRET: SECRET };
const env = (e: Record<string, string>) => (k: string) => e[k];

const b64u = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwt = (claims: Record<string, unknown>) => `${b64u({ alg: 'none', typ: 'JWT' })}.${b64u(claims)}.zz-demo-signature`;
const GRAPH_TOKEN = jwt({ aud: 'https://graph.microsoft.com', roles: ['Mail.Send', 'Mail.Read', 'Mail.ReadWrite'] });
const EXO_WITH = jwt({ aud: 'https://outlook.office365.com', roles: [MANAGE_AS_APP] });
const EXO_WITHOUT = jwt({ aud: 'https://outlook.office365.com' });

const OURS = { Name: RULE_NAME, State: 'Enabled', Mode: 'Enforce', From: [RULE_FROM], SetHeaderName: RULE_HEADER_NAME, SetHeaderValue: RULE_HEADER_VALUE, Priority: 0 };

type Call = { url: string; scope?: string; cmdlet?: string; params?: Record<string, unknown>; headers?: Record<string, string> };
/** A fake Microsoft: tokens by scope, InvokeCommand by cmdlet. `rules` is the tenant's rule list (mutable). */
function microsoft(o: { exoToken?: string | null; graphToken?: string; rules?: Record<string, unknown>[]; getStatus?: number; newStatus?: number; newDoesNotLand?: boolean }) {
  const calls: Call[] = [];
  const rules = o.rules ?? [];
  const fetchFn: Fetch = async (url, init) => {
    const body = String(init?.body ?? '');
    if (url.includes('login.microsoftonline.com')) {
      const scope = new URLSearchParams(body).get('scope') || '';
      calls.push({ url, scope });
      if (scope === EXO_SCOPE) {
        return o.exoToken === null
          ? new Response(JSON.stringify({ error: 'invalid_client', error_description: 'AADSTS7000215 zz-demo-client-id', error_codes: [7000215] }), { status: 401 })
          : new Response(JSON.stringify({ access_token: o.exoToken ?? EXO_WITHOUT }), { status: 200 });
      }
      return new Response(JSON.stringify({ access_token: o.graphToken ?? GRAPH_TOKEN }), { status: 200 });
    }
    const j = JSON.parse(body);
    const cmdlet = j.CmdletInput.CmdletName as string;
    calls.push({ url, cmdlet, params: j.CmdletInput.Parameters, headers: init?.headers as Record<string, string> });
    if (cmdlet === 'Get-TransportRule') {
      if (o.getStatus && o.getStatus >= 400) return new Response(JSON.stringify({ error: { code: 'Forbidden', message: 'The role assigned to application isn\'t supported in this scenario' } }), { status: o.getStatus });
      return new Response(JSON.stringify({ value: rules }), { status: 200 });
    }
    if (cmdlet === 'New-TransportRule') {
      if (o.newStatus && o.newStatus >= 400) return new Response(JSON.stringify({ error: { code: 'BadRequest', message: 'nope' } }), { status: o.newStatus });
      const p = j.CmdletInput.Parameters;
      if (!o.newDoesNotLand) rules.push({ Name: p.Name, State: 'Enabled', Mode: 'Enforce', From: p.From, SetHeaderName: p.SetHeaderName, SetHeaderValue: p.SetHeaderValue });
      return new Response(JSON.stringify({ value: [] }), { status: 200 });
    }
    return new Response('{}', { status: 404 });
  };
  return { calls, fetchFn, rules };
}

const leaks = (o: unknown) => {
  const s = JSON.stringify(o);
  return [SECRET, GRAPH_TOKEN, EXO_WITH, EXO_WITHOUT, 'zz-demo-signature', 'zz-demo-client-id'].filter((t) => s.includes(t));
};

Deno.test('rolesOf returns the roles claim only, sorted; a non-token answers []', () => {
  assertEquals(rolesOf(GRAPH_TOKEN), ['Mail.Read', 'Mail.ReadWrite', 'Mail.Send']);
  assertEquals(rolesOf(EXO_WITHOUT), []);
  assertEquals(rolesOf('not-a-jwt'), []);
  assertEquals(rolesOf(''), []);
});

Deno.test('probe asks for the Graph AND the Exchange scope, and reports the Exchange roles', async () => {
  const m = microsoft({ exoToken: EXO_WITHOUT });
  const p = await probe(env(ENV), m.fetchFn);
  assertEquals(m.calls.filter((c) => c.scope).map((c) => c.scope).sort(), [GRAPH_SCOPE, EXO_SCOPE].sort());
  assertEquals(p.graph.roles, ['Mail.Read', 'Mail.ReadWrite', 'Mail.Send']);
  assertEquals(p.exchange.roles, []);
  assertFalse(p.exchange.has_manage_as_app);
  assertEquals(p.verdict, 'missing_manage_as_app');
  assertEquals(p.exchange.rbac_read, null);
  assertEquals(m.calls.filter((c) => c.cmdlet).length, 0, 'no Exchange cmdlet without the permission');
  assertEquals(leaks(p), []);
});

Deno.test('probe with ManageAsApp runs ONE read cmdlet and says ready when Exchange answers', async () => {
  const m = microsoft({ exoToken: EXO_WITH, rules: [{ Name: 'someone else', From: ['a@b.c'] }] });
  const p = await probe(env(ENV), m.fetchFn);
  assert(p.exchange.has_manage_as_app);
  assertEquals(p.verdict, 'ready');
  assertEquals(m.calls.filter((c) => c.cmdlet).map((c) => c.cmdlet), ['Get-TransportRule']);
  assertEquals(p.exchange.rbac_read?.transport_rules, 1);
  assertEquals(p.exchange.rbac_read?.our_rule, null);
  const h = m.calls.find((c) => c.cmdlet)!;
  assert(h.url.startsWith(`https://outlook.office365.com/adminapi/beta/${TENANT}/InvokeCommand`));
  assertEquals(h.headers?.['X-AnchorMailbox'], `APP:SystemMailbox{bb558c35-97f1-4cb9-8ff7-d53741dc928c}@${TENANT}`);
  assertEquals(leaks(p), []);
});

Deno.test('probe: permission present but Exchange refuses the read -> missing_exchange_role, Exchange error kept', async () => {
  const m = microsoft({ exoToken: EXO_WITH, getStatus: 403 });
  const p = await probe(env(ENV), m.fetchFn);
  assertEquals(p.verdict, 'missing_exchange_role');
  assertEquals(p.exchange.rbac_read?.status, 403);
  assert(String(p.exchange.rbac_read?.error).includes('Forbidden'));
  assertEquals(leaks(p), []);
});

Deno.test('probe: a refused token is reported without the error_description (it echoes the client id)', async () => {
  const p = await probe(env(ENV), microsoft({ exoToken: null }).fetchFn);
  assertEquals(p.verdict, 'token_refused');
  assertEquals(p.exchange.status, 401);
  assertEquals(p.exchange.error, 'invalid_client AADSTS7000215');
  assertEquals(leaks(p), []);
});

Deno.test('every missing MS_* secret fails closed with no network call', async () => {
  for (const k of Object.keys(ENV)) {
    const m = microsoft({});
    const e = { ...ENV, [k]: '  ' };
    const p = await probe(env(e), m.fetchFn);
    assertEquals(p.verdict, 'missing_secrets');
    assertEquals(p.missing_secrets, [k]);
    const a = await applyRule(env(e), m.fetchFn);
    assertEquals(a.outcome, 'refused');
    assertEquals(m.calls.length, 0);
  }
});

Deno.test('apply WITHOUT Exchange.ManageAsApp is refused and makes no Exchange call at all', async () => {
  const m = microsoft({ exoToken: EXO_WITHOUT });
  const a = await applyRule(env(ENV), m.fetchFn);
  assertEquals(a.outcome, 'refused');
  assertFalse(a.ok);
  assertEquals(m.calls.filter((c) => c.cmdlet).length, 0);
  assertEquals(m.calls.filter((c) => c.scope).map((c) => c.scope), [EXO_SCOPE]);
  assertEquals(leaks(a), []);
});

Deno.test('apply creates the rule when absent, with the exact parameters, and says created only after the read-back', async () => {
  const m = microsoft({ exoToken: EXO_WITH });
  const a = await applyRule(env(ENV), m.fetchFn);
  assertEquals(a.outcome, 'created');
  assert(a.ok);
  assertEquals(m.calls.filter((c) => c.cmdlet).map((c) => c.cmdlet), ['Get-TransportRule', 'New-TransportRule', 'Get-TransportRule']);
  const made = m.calls.find((c) => c.cmdlet === 'New-TransportRule')!.params!;
  assertEquals(made.Name, 'QuotesDone supplier@ one-click unsubscribe');
  assertEquals(made.From, ['supplier@quotesdone.com']);
  assertEquals(made.SetHeaderName, 'List-Unsubscribe-Post');
  assertEquals(made.SetHeaderValue, 'List-Unsubscribe=One-Click');
  assertEquals(leaks(a), []);
});

Deno.test('apply is idempotent: a second run finds the rule and does not call New-TransportRule', async () => {
  const m = microsoft({ exoToken: EXO_WITH, rules: [{ ...OURS }] });
  const a = await applyRule(env(ENV), m.fetchFn);
  assertEquals(a.outcome, 'exists');
  assertEquals(m.calls.filter((c) => c.cmdlet === 'New-TransportRule').length, 0);
});

Deno.test('apply never rewrites a same-named rule that differs; it reports the differences', async () => {
  const m = microsoft({ exoToken: EXO_WITH, rules: [{ ...OURS, SetHeaderValue: 'something else', State: 'Disabled' }] });
  const a = await applyRule(env(ENV), m.fetchFn);
  assertEquals(a.outcome, 'exists_differs');
  assertEquals(a.differences?.length, 2);
  assertEquals(m.calls.filter((c) => c.cmdlet && c.cmdlet !== 'Get-TransportRule').length, 0);
});

Deno.test('apply: a 2xx New-TransportRule that does not read back is a failure, not created', async () => {
  const a = await applyRule(env(ENV), microsoft({ exoToken: EXO_WITH, newDoesNotLand: true }).fetchFn);
  assertEquals(a.outcome, 'failed');
  const b = await applyRule(env(ENV), microsoft({ exoToken: EXO_WITH, getStatus: 403 }).fetchFn);
  assertEquals(b.outcome, 'failed');
  assertEquals(b.status, 403);
});

Deno.test('ruleDiff: ours is [] (case-insensitive From)', () => {
  assertEquals(ruleDiff({ ...OURS, From: ['Supplier@QuotesDone.com'] }), []);
});

Deno.test('the EXO actions answer the service_role only', () => {
  const key = jwt({ role: 'service_role', iss: 'supabase' });
  assert(isServiceRole('Bearer ' + key, undefined));
  assert(isServiceRole('Bearer sb_secret_zzdemo', 'sb_secret_zzdemo'));
  assertFalse(isServiceRole('Bearer ' + jwt({ role: 'anon' }), 'sb_secret_zzdemo'));
  assertFalse(isServiceRole('Bearer ' + jwt({ role: 'authenticated', email: 'founder@example.invalid' }), undefined));
  assertFalse(isServiceRole(null, 'sb_secret_zzdemo'));
  assertFalse(isServiceRole('Bearer ', ''));
  assertFalse(isServiceRole('Bearer garbage', undefined));
});

Deno.test('it_engineer routes both EXO actions through the service_role gate before whoami', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const gate = src.indexOf('isServiceRole(req.headers');
  const who = src.indexOf('const caller = await whoami(');
  assert(gate > 0 && who > gate, 'service_role check must precede the seat/founder auth');
  assert(src.includes("'exo_roles'") && src.includes("'exo_transport_rule_apply'"));
  const cfg = await Deno.readTextFile(new URL('../../config.toml', import.meta.url));
  assert(/\[functions\.it_engineer\]\s*\r?\nverify_jwt = true/.test(cfg), 'it_engineer must keep verify_jwt = true');
});
