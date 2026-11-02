// EXCHANGE ONLINE, APP-ONLY: does the M365 app hold Exchange admin rights, and the one transport rule we need.
//
// Assigned: it_engineer. 27 Oct 2026.
//
// WHAT WAS MEASURED. Notification 112440 (27 Oct) left the M365 lane (send_outbox/m365_lane.ts) with
// `List-Unsubscribe-Post: List-Unsubscribe=One-Click` in the MIME we submit and arrived at Gmail without it:
// Exchange Online rebuilds the header set on submission (.claude/memory/exchange-strips-list-unsubscribe-post.md,
// docs/reports/QuotesDone Campaign/GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md). The fix is a transport rule that sets
// the header on mail from supplier@quotesdone.com, not code in the lane.
//
// WHAT IS NOT KNOWN, AND WHY THE PROBE EXISTS. The founder says he granted the app admin rights "a few weeks
// ago". The repository's last measurement of that app (18 Oct 2026, commit d2b616558) saw Graph roles Mail.Read,
// Mail.ReadWrite and Mail.Send, which is a Graph token and says nothing about Exchange. Exchange app-only
// administration needs two things on the SAME app, and they are visible in different places:
//   1. the API permission Office 365 Exchange Online -> Exchange.ManageAsApp (Application), admin-consented.
//      It shows up as a `roles` entry in a token for https://outlook.office365.com/.default — `exoRoles` reads it;
//   2. an Entra role that Exchange RBAC honours (Exchange Administrator). That is NOT in any token. The only
//      measurement of it is Exchange answering a read cmdlet, so the probe runs Get-TransportRule (read-only)
//      once the permission is present and reports Exchange's answer verbatim (status and error code).
//
// THE ENDPOINT. POST https://outlook.office365.com/adminapi/beta/{tenantId}/InvokeCommand with
// {"CmdletInput":{"CmdletName":...,"Parameters":{...}}} is the REST surface Exchange Online PowerShell v3 uses
// under the hood. Microsoft does not document it as a public API; the request shape and headers here mirror
// what the v3 module sends. It is UNMEASURED from this repository: this container cannot reach
// outlook.office365.com, so the first real answer comes from the deployed function.
//
// NEVER A TOKEN, NEVER A SECRET. The MS_* values are read by name and never returned or logged. A token is
// decoded only for its `roles` claim, and that array is the only thing that leaves `rolesOf`.
//
// WHAT THIS DOES NOT DO. It does not change an existing rule of the same name that differs from ours: that is
// reported as `exists_differs` with the differences, and a person decides. It never deletes anything.

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export type Env = (k: string) => string | undefined;

export const MS_SECRET_NAMES = ['MS_TENANT_ID', 'MS_CLIENT_ID', 'MS_CLIENT_SECRET'] as const;
export const GRAPH_SCOPE = 'https://graph.microsoft.com/.default';
export const EXO_SCOPE = 'https://outlook.office365.com/.default';
export const MANAGE_AS_APP = 'Exchange.ManageAsApp';

export const RULE_NAME = 'QuotesDone supplier@ one-click unsubscribe';
export const RULE_FROM = 'supplier@quotesdone.com';
export const RULE_HEADER_NAME = 'List-Unsubscribe-Post';
export const RULE_HEADER_VALUE = 'List-Unsubscribe=One-Click';
// ONLY ON MAIL THAT ALREADY CARRIES List-Unsubscribe (review of #1695, 27 Oct 2026). supplier@ also sends one-to-one
// replies, and RFC 8058 pairs List-Unsubscribe-Post with an HTTPS List-Unsubscribe: a Post header on a message with no
// List-Unsubscribe is meaningless at best. The lane writes List-Unsubscribe only when the notification carries an
// unsubscribe link (send_outbox/m365_lane.ts m365Mime), and Exchange keeps that header (only the Post one is lost:
// .claude/memory/exchange-strips-list-unsubscribe-post.md), so the rule matches exactly the mail that needs it.
export const RULE_IF_HEADER = 'List-Unsubscribe';
export const RULE_IF_PATTERN = '.';

const TIMEOUT_MS = 20_000;
// The well-known system mailbox the v3 module anchors app-only admin calls to.
const ANCHOR = (tenant: string) => `APP:SystemMailbox{bb558c35-97f1-4cb9-8ff7-d53741dc928c}@${tenant}`;

/** The `roles` claim of a JWT access token, and nothing else. A token that does not decode answers []. */
export function rolesOf(token: string): string[] {
  try {
    const part = String(token || '').split('.')[1];
    if (!part) return [];
    const b64 = part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=');
    const claims = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
    return Array.isArray(claims?.roles) ? claims.roles.map(String).sort() : [];
  } catch { return []; }
}

/** The bearer is the project's service_role. verify_jwt = true has already checked the signature at the edge, so
 *  the role claim is trustworthy; an exact match with the injected service key is accepted too. Anything else —
 *  anon, an authenticated user, the founder's own session, no header — is refused. */
export function isServiceRole(authorization: string | null, serviceKey: string | undefined): boolean {
  const jwt = String(authorization || '').replace(/^Bearer\s+/i, '').trim();
  if (!jwt) return false;
  if (serviceKey && jwt === serviceKey) return true;
  try {
    const part = jwt.split('.')[1];
    if (!part) return false;
    const b64 = part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=');
    const claims = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
    return claims?.role === 'service_role';
  } catch { return false; }
}

type Creds = { tenant: string; client: string; secret: string };
function creds(env: Env): { ok: true; c: Creds } | { ok: false; missing: string[] } {
  const v = MS_SECRET_NAMES.map((k) => String(env(k) || '').trim());
  const missing = MS_SECRET_NAMES.filter((_, i) => !v[i]);
  return missing.length ? { ok: false, missing } : { ok: true, c: { tenant: v[0], client: v[1], secret: v[2] } };
}

type Tok = { ok: true; token: string } | { ok: false; status: number | null; error: string };
async function token(fetchFn: Fetch, c: Creds, scope: string): Promise<Tok> {
  let r: Response;
  try {
    r = await fetchFn(`https://login.microsoftonline.com/${encodeURIComponent(c.tenant)}/oauth2/v2.0/token`, {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: c.client, client_secret: c.secret, scope, grant_type: 'client_credentials' }).toString(),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (e) { return { ok: false, status: null, error: 'token endpoint did not answer: ' + String((e as Error)?.message || e) }; }
  let j: { access_token?: string; error?: string; error_codes?: number[] } = {};
  try { j = await r.json(); } catch { /* handled below */ }
  if (!r.ok || !j.access_token) {
    // error + AADSTS code only. error_description can echo the client id; it is not needed to act.
    return { ok: false, status: r.status, error: (j.error || 'no_access_token') + (j.error_codes?.length ? ' AADSTS' + j.error_codes[0] : '') };
  }
  return { ok: true, token: j.access_token };
}

export type Invoke = { ok: boolean; status: number | null; value: Record<string, unknown>[]; error: string | null };
/** One cmdlet through InvokeCommand. Follows @odata.nextLink (at most 10 pages). The error is Exchange's own
 *  code and message, cut to 300 characters; it never carries the token. */
export async function invoke(fetchFn: Fetch, tenant: string, tok: string, cmdlet: string, params: Record<string, unknown>): Promise<Invoke> {
  const headers = {
    Authorization: 'Bearer ' + tok, 'Content-Type': 'application/json', Accept: 'application/json',
    'X-ResponseFormat': 'json', 'X-AnchorMailbox': ANCHOR(tenant), 'X-CmdletName': cmdlet,
  };
  const body = JSON.stringify({ CmdletInput: { CmdletName: cmdlet, Parameters: params } });
  let url: string | null = `https://outlook.office365.com/adminapi/beta/${encodeURIComponent(tenant)}/InvokeCommand`;
  const value: Record<string, unknown>[] = [];
  for (let page = 0; url && page < 10; page++) {
    let r: Response;
    try { r = await fetchFn(url, { method: 'POST', headers, body, signal: AbortSignal.timeout(TIMEOUT_MS) }); }
    catch (e) { return { ok: false, status: null, value, error: 'outlook.office365.com did not answer: ' + String((e as Error)?.message || e) }; }
    const text = await r.text().catch(() => '');
    let j: { value?: unknown; error?: { code?: string; message?: string }; '@odata.nextLink'?: string } = {};
    try { j = text ? JSON.parse(text) : {}; } catch { /* non-JSON error body */ }
    if (!r.ok) {
      const e = j.error ? `${j.error.code || ''}: ${j.error.message || ''}` : text;
      return { ok: false, status: r.status, value, error: String(e).replace(/Bearer\s+\S+/gi, 'Bearer [redacted]').slice(0, 300) };
    }
    if (Array.isArray(j.value)) value.push(...(j.value as Record<string, unknown>[]));
    url = typeof j['@odata.nextLink'] === 'string' ? j['@odata.nextLink'] : null;
  }
  return { ok: true, status: 200, value, error: null };
}

const asList = (v: unknown): string[] => (Array.isArray(v) ? v.map(String) : v == null || v === '' ? [] : [String(v)]).map((s) => s.toLowerCase());
const ruleNamed = (rules: Record<string, unknown>[]) => rules.find((r) => String(r.Name ?? r.Identity ?? '') === RULE_NAME) ?? null;

/** What differs between an existing rule and ours. [] = it is ours. */
export function ruleDiff(rule: Record<string, unknown>): string[] {
  const d: string[] = [];
  if (!asList(rule.From).includes(RULE_FROM)) d.push(`From is ${JSON.stringify(rule.From ?? null)}, want ${RULE_FROM}`);
  if (String(rule.SetHeaderName ?? '').toLowerCase() !== RULE_HEADER_NAME.toLowerCase()) d.push(`SetHeaderName is ${JSON.stringify(rule.SetHeaderName ?? null)}`);
  if (String(rule.SetHeaderValue ?? '') !== RULE_HEADER_VALUE) d.push(`SetHeaderValue is ${JSON.stringify(rule.SetHeaderValue ?? null)}`);
  if (String(rule.HeaderMatchesMessageHeader ?? '').toLowerCase() !== RULE_IF_HEADER.toLowerCase()) d.push(`HeaderMatchesMessageHeader is ${JSON.stringify(rule.HeaderMatchesMessageHeader ?? null)}, want ${RULE_IF_HEADER}`);
  if (JSON.stringify(Array.isArray(rule.HeaderMatchesPatterns) ? rule.HeaderMatchesPatterns.map(String) : rule.HeaderMatchesPatterns == null ? [] : [String(rule.HeaderMatchesPatterns)]) !== JSON.stringify([RULE_IF_PATTERN])) d.push(`HeaderMatchesPatterns is ${JSON.stringify(rule.HeaderMatchesPatterns ?? null)}, want ["${RULE_IF_PATTERN}"]`);
  if (rule.State != null && String(rule.State) !== 'Enabled') d.push(`State is ${String(rule.State)}`);
  return d;
}

const ruleView = (r: Record<string, unknown> | null) => r && {
  name: r.Name ?? r.Identity ?? null, state: r.State ?? null, mode: r.Mode ?? null, from: r.From ?? null,
  set_header_name: r.SetHeaderName ?? null, set_header_value: r.SetHeaderValue ?? null, priority: r.Priority ?? null,
  if_header: r.HeaderMatchesMessageHeader ?? null, if_patterns: r.HeaderMatchesPatterns ?? null,
};

export type Probe = {
  ok: boolean;
  missing_secrets?: string[];
  graph: { token: boolean; status?: number | null; error?: string; roles: string[] };
  exchange: {
    token: boolean; status?: number | null; error?: string; roles: string[];
    has_manage_as_app: boolean;
    // Exchange RBAC (the Entra role) is not in a token. Measured only by a read cmdlet, and only once the
    // permission is there; null = not asked because the permission is missing.
    rbac_read: null | { ok: boolean; status: number | null; error: string | null; transport_rules: number; our_rule: ReturnType<typeof ruleView> };
  };
  verdict: 'ready' | 'missing_manage_as_app' | 'missing_exchange_role' | 'token_refused' | 'missing_secrets';
};

/** READ-ONLY. Two client-credentials tokens (Graph, Exchange), their `roles` claims, and — when the Exchange
 *  token carries Exchange.ManageAsApp — one Get-TransportRule. */
export async function probe(env: Env, fetchFn: Fetch): Promise<Probe> {
  const k = creds(env);
  const empty = { token: false, roles: [] as string[] };
  if (!k.ok) {
    return { ok: false, missing_secrets: k.missing, graph: empty, exchange: { ...empty, has_manage_as_app: false, rbac_read: null }, verdict: 'missing_secrets' };
  }
  const [g, x] = await Promise.all([token(fetchFn, k.c, GRAPH_SCOPE), token(fetchFn, k.c, EXO_SCOPE)]);
  const graph = g.ok ? { token: true, roles: rolesOf(g.token) } : { token: false, status: g.status, error: g.error, roles: [] };
  if (!x.ok) {
    return { ok: false, graph, exchange: { token: false, status: x.status, error: x.error, roles: [], has_manage_as_app: false, rbac_read: null }, verdict: 'token_refused' };
  }
  const roles = rolesOf(x.token);
  const has = roles.includes(MANAGE_AS_APP);
  let rbac: Probe['exchange']['rbac_read'] = null;
  if (has) {
    const r = await invoke(fetchFn, k.c.tenant, x.token, 'Get-TransportRule', {});
    rbac = { ok: r.ok, status: r.status, error: r.error, transport_rules: r.value.length, our_rule: ruleView(ruleNamed(r.value)) };
  }
  const verdict = !has ? 'missing_manage_as_app' : rbac?.ok ? 'ready' : 'missing_exchange_role';
  return { ok: true, graph, exchange: { token: true, roles, has_manage_as_app: has, rbac_read: rbac }, verdict };
}

export type Apply = {
  ok: boolean;
  outcome: 'created' | 'exists' | 'exists_differs' | 'refused' | 'failed';
  why?: string;
  differences?: string[];
  rule?: ReturnType<typeof ruleView>;
  exchange_roles?: string[];
  status?: number | null;
};

/** THE WRITE. Idempotent: reads Get-TransportRule first and creates the rule only when no rule of that name
 *  exists; then reads it back, and only the read-back says `created`. Refuses, with no Exchange call at all,
 *  when the token lacks Exchange.ManageAsApp. */
export async function applyRule(env: Env, fetchFn: Fetch): Promise<Apply> {
  const k = creds(env);
  if (!k.ok) return { ok: false, outcome: 'refused', why: 'edge secret(s) not set: ' + k.missing.join(', ') };
  const x = await token(fetchFn, k.c, EXO_SCOPE);
  if (!x.ok) return { ok: false, outcome: 'refused', why: 'Exchange token refused: ' + x.error, status: x.status };
  const roles = rolesOf(x.token);
  if (!roles.includes(MANAGE_AS_APP)) {
    return { ok: false, outcome: 'refused', exchange_roles: roles,
      why: `the Exchange token does not carry ${MANAGE_AS_APP}; no Exchange call was made` };
  }
  const before = await invoke(fetchFn, k.c.tenant, x.token, 'Get-TransportRule', {});
  if (!before.ok) return { ok: false, outcome: 'failed', why: 'Get-TransportRule: ' + before.error, status: before.status, exchange_roles: roles };
  const existing = ruleNamed(before.value);
  if (existing) {
    const diff = ruleDiff(existing);
    return diff.length
      ? { ok: false, outcome: 'exists_differs', differences: diff, rule: ruleView(existing), why: 'a rule with this name exists and differs; it was not changed' }
      : { ok: true, outcome: 'exists', rule: ruleView(existing) };
  }
  const made = await invoke(fetchFn, k.c.tenant, x.token, 'New-TransportRule', {
    Name: RULE_NAME,
    From: [RULE_FROM],
    HeaderMatchesMessageHeader: RULE_IF_HEADER,
    HeaderMatchesPatterns: [RULE_IF_PATTERN],
    SetHeaderName: RULE_HEADER_NAME,
    SetHeaderValue: RULE_HEADER_VALUE,
    Comments: 'QuotesDone it_engineer: Exchange drops List-Unsubscribe-Post from the M365 lane (measured 27 Oct 2026); '
      + 'RFC 8058 one-click for Gmail/Yahoo bulk-sender rules.',
  });
  if (!made.ok) return { ok: false, outcome: 'failed', why: 'New-TransportRule: ' + made.error, status: made.status };
  const after = await invoke(fetchFn, k.c.tenant, x.token, 'Get-TransportRule', {});
  const back = after.ok ? ruleNamed(after.value) : null;
  if (!back) return { ok: false, outcome: 'failed', why: 'New-TransportRule answered 2xx but the rule did not read back' + (after.error ? ': ' + after.error : '') };
  const diff = ruleDiff(back);
  return diff.length
    ? { ok: false, outcome: 'exists_differs', differences: diff, rule: ruleView(back), why: 'created, but the read-back differs' }
    : { ok: true, outcome: 'created', rule: ruleView(back) };
}
