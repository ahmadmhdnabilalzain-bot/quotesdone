// THE GLOCKAPPS SPAM TEST API v2, AND WHAT A REPORT MEANS FOR THE 80% BAR (27 Oct 2026; Assigned: it_engineer).
//
// Founder, 27 Oct 2026 (ledger 1312): invitations stay paused unless the GlockApps check of the invitation sent from
// supplier@quotesdone.com shows Outlook at 80% inbox or more; report inbox, spam and promotions for each provider.
// He ran that check by hand. This module is what lets the it_engineer run it without him.
//
// EVERY ROUTE AND FIELD BELOW WAS READ FROM THE PUBLISHED SPEC, NOT GUESSED (27 Oct 2026). The container this was
// written in cannot reach glockapps.com (proxy 403), so the pages were fetched server-side through pg_net:
//   https://glockapps.com/api-documentation-v2/            "Every API request requires the use of the apiKey parameter"
//   https://glockapps.com/blog/how-to-use-glockapps-v2-api-step-by-step-tutorial/   header "x-api-key: <your_api_key>"
//   https://docs.spamtest.prod-k8s.glockapps.com/swagger.json   (the "Access Documentation" link; Swagger 2.0)
//     host api.glockapps.com/gateway/spamtest-v2, basePath /api/, securityDefinitions ApiKeyAuth = header x-api-key
//     GET  /projects                                  -> {results:[{id,name,...}], page, status}
//     GET  /projects/{projectId}/providers            -> {results:[{seedAccountRegionId, seedAccountGroups:[{seedAccounts:
//                                                         [{id, seedEmail, providerGroupId, providerGroupName}]}]}]}
//     POST /projects/{projectId}/manualTest           {testType:"ManualTest", providerGroupIds?, note?, linkChecker?}
//                                                      -> 201 {testId, emails[], insertInBody "id: <testId>",
//                                                         insertHeader "X-API-Campaign-id: <testId>", status}
//                                                      "One point will be deducted per request, but can be returned if the
//                                                       created test is deleted before any emails are sent."
//     GET  /projects/{projectId}/tests/{testId}/seedAccounts -> {result:{emails, insertInBody, insertHeader}}
//     GET  /projects/{projectId}/tests?testId=        -> {result: TestItem}: finished, inboxes[{email, iType,
//                                                         providerGroupId, finished}], stats{inbox,spam,other,notDelivered,
//                                                         inboxRate,...}, spamAssassin{score, headers[{tag,score,
//                                                         description}]}, microsoftEOP{scl,bcl,sfv,cat}, barracuda,
//                                                         hwBarracuda, proofPoint{spam}, googleApps{spam,phishy},
//                                                         authenticationResult{spfAuth,dkimAuth,dmarcAuth}, ipListed
//     DELETE /projects/{projectId}/tests?ids=<testId> (refunds the point while nothing was sent)
//   and from the docs page FAQ: GET https://api.glockapps.com/gateway/app/v3/u/account/balance with the same header
//     -> {"testCredits":{"balance":3,"planCredits":3}}.
// The Swagger's own description says the API is "available on all subscription plans and in the pay-per-test plan";
// the marketing page says every plan including free. Either way the founder's account (3 credits bought, ledger 1120)
// qualifies. A test spends one credit; reading a report spends none.
//
// WHAT THE SPEC DOES NOT SAY, AND HOW IT IS HANDLED (never a guess dressed as a fact):
//   - iType values. The Swagger types iType as a string with no enum. Its examples carry "Inbox", "Spam" and "X"
//     ("X" only on the spam-filter and always-on check seeds). stats has inbox / spam / other / notDelivered, and the
//     docs page says "broken down by Inbox, Tabs, and Spam". So: Inbox = inbox, Spam = spam, X = a filter seed (not
//     a mailbox, left out of placement), empty / not received = missing, and ANY OTHER value is counted as tabs and
//     kept verbatim in raw_itypes. Only "Inbox" ever counts towards the 80% bar, so an unknown label can never
//     inflate a pass.
//   - Booleans arrive as strings in the examples ("finished": "true"), so truthy() accepts both.
//   - The marker. insertInBody is "id: <testId>" (with a space). send_outbox's M365 lane keeps a seed's marker only
//     when the last line matches its SEED_MARKER, "id:" followed directly by the ID, the form that GlockApps matched
//     on 19 and 27 Oct (tests 2026-10-19-02:51:47:497t and 2026-10-27-09:33:53:634t, 110 and 112 seeds). So the line
//     is written without the space, and markerFor() refuses an ID the lane would drop.
//
// Pure apart from the injected fetch: glockapps.test.ts replays every branch offline against the documented examples.
import { seedMarker } from '../send_outbox/m365_lane.ts';

export const GLOCKAPPS_KEY_NAME = 'GLOCKAPPS_API_KEY';
export const GLOCKAPPS_BASE = 'https://api.glockapps.com/gateway/spamtest-v2/api';
export const GLOCKAPPS_BALANCE_URL = 'https://api.glockapps.com/gateway/app/v3/u/account/balance';
export const OUTLOOK_BAR_PCT = 80;
/** A report not finished this long after the test was created is decided as incomplete (never a pass). */
export const GIVE_UP_HOURS = 48;
/** The Microsoft 365 lane's own per-day ceiling (send_outbox/m365_lane.ts M365_HARD_CEILING). A seed list above it is refused. */
export const MAX_SEEDS = 150;
/** Founder, ledger 1312 memory: "Outlook" is the outlook.com, hotmail.com and Office 365 seeds together. */
export const OUTLOOK = /outlook|hotmail|office\s*365|o365|exchange|microsoft|\bmsn\b|\blive\b/i;

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export type Bucket = 'inbox' | 'spam' | 'tabs' | 'missing' | 'filter';
export type ProviderRow = {
  provider: string; provider_group_id: string; is_outlook: boolean; seeds: number;
  inbox: number; spam: number; tabs: number; missing: number; inbox_pct: number | null; raw_itypes: Record<string, number>;
};
export type Verdict = 'pending' | 'pass' | 'fail' | 'incomplete';
export type Outlook = { seeds: number; inbox: number; spam: number; tabs: number; missing: number; inbox_pct: number | null };

export class GlockAppsError extends Error {
  constructor(public status: number, public route: string, detail: string) { super(`GlockApps ${route} answered HTTP ${status}: ${detail}`); }
}

export const truthy = (v: unknown) => v === true || String(v).toLowerCase() === 'true';
const str = (v: unknown) => (v == null ? '' : String(v));

/** Remove the key from anything that may be stored or logged, whatever the provider echoed. */
export function scrubKey(s: string, key: string): string {
  return key && key.length >= 4 ? String(s).split(key).join('[redacted]') : String(s);
}

/** The API, every call through the injected fetch with the x-api-key header (Swagger securityDefinitions ApiKeyAuth). */
export function glockapps(key: string, fetchFn: Fetch, base = GLOCKAPPS_BASE) {
  const call = async (method: string, route: string, body?: unknown): Promise<any> => {
    const url = route.startsWith('https://') ? route : base + route;
    const r = await fetchFn(url, {
      method,
      headers: { 'x-api-key': key, Accept: 'application/json', ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const text = await r.text();
    if (!r.ok) throw new GlockAppsError(r.status, `${method} ${route.replace(/\?.*$/, '')}`, scrubKey(text, key).slice(0, 300));
    try { return text ? JSON.parse(text) : {}; } catch { throw new GlockAppsError(r.status, `${method} ${route}`, 'the answer was not JSON'); }
  };
  const pid = (p: string) => encodeURIComponent(p);
  return {
    projects: () => call('GET', '/projects?limit=50'),
    providers: (projectId: string) => call('GET', `/projects/${pid(projectId)}/providers`),
    createManualTest: (projectId: string, body: Record<string, unknown>) => call('POST', `/projects/${pid(projectId)}/manualTest`, { ...body, testType: 'ManualTest' }),
    seedAccounts: (projectId: string, testId: string) => call('GET', `/projects/${pid(projectId)}/tests/${encodeURIComponent(testId)}/seedAccounts`),
    testReport: (projectId: string, testId: string) => call('GET', `/projects/${pid(projectId)}/tests?testId=${encodeURIComponent(testId)}`),
    deleteTest: (projectId: string, testId: string) => call('DELETE', `/projects/${pid(projectId)}/tests?ids=${encodeURIComponent(testId)}`),
    balance: () => call('GET', GLOCKAPPS_BALANCE_URL),
  };
}
export type GlockApps = ReturnType<typeof glockapps>;

/** The project to test in: the configured one when it exists in the account, else the first the account lists. */
export function pickProject(projects: any, configured?: string): string {
  const list: any[] = Array.isArray(projects?.results) ? projects.results : [];
  const want = str(configured).trim();
  if (want && list.some((p) => str(p?.id) === want)) return want;
  if (want && !list.length) return want;
  return list.length ? str(list[0]?.id) : '';
}

export type Seed = { email: string; provider: string; provider_group_id: string };
/** seedEmail -> its provider, and providerGroupId -> name, from GET /projects/{id}/providers (or GET /providers). */
export function seedDirectory(providers: any): { byEmail: Map<string, Seed>; groupName: Map<string, string> } {
  const byEmail = new Map<string, Seed>(); const groupName = new Map<string, string>();
  for (const region of Array.isArray(providers?.results) ? providers.results : []) {
    for (const g of Array.isArray(region?.seedAccountGroups) ? region.seedAccountGroups : []) {
      for (const a of Array.isArray(g?.seedAccounts) ? g.seedAccounts : []) {
        const gid = str(a?.providerGroupId); const name = str(a?.providerGroupName) || `provider group ${gid}`;
        if (gid) groupName.set(gid, name);
        const email = str(a?.seedEmail).trim().toLowerCase();
        if (email) byEmail.set(email, { email, provider: name, provider_group_id: gid });
      }
    }
  }
  return { byEmail, groupName };
}
export const providerGroupIds = (providers: any) => [...seedDirectory(providers).groupName.keys()];

/** The body's last line for this test, in the exact form send_outbox's M365 lane keeps. '' when the lane would drop it. */
export function markerFor(created: { testId?: unknown; insertInBody?: unknown }): string {
  const fromBody = str(created.insertInBody).trim().replace(/^id:\s+/i, 'id:');
  const id = str(created.testId).trim();
  const line = fromBody || (id ? 'id:' + id : '');
  if (!line || (id && line !== 'id:' + id)) return '';
  return seedMarker('x\n\n' + line) === line ? line : '';
}

const EMAIL = /^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/;
/**
 * The addresses a test may be sent to: ONLY those GlockApps returned for this test, lower-cased, de-duplicated and
 * well formed, minus any that belong to a real party we know (leads, customers). The caller passes that set.
 */
export function seedAddresses(emails: unknown, knownParties: Set<string>): { send: string[]; refused: { email: string; why: string }[] } {
  const send: string[] = []; const refused: { email: string; why: string }[] = []; const seen = new Set<string>();
  for (const raw of Array.isArray(emails) ? emails : []) {
    const e = str(raw).trim().toLowerCase();
    if (!e || seen.has(e)) continue;
    seen.add(e);
    if (!EMAIL.test(e)) { refused.push({ email: e, why: 'not an address' }); continue; }
    if (knownParties.has(e)) { refused.push({ email: e, why: 'belongs to a lead or customer we hold: never a seed' }); continue; }
    send.push(e);
  }
  return { send, refused };
}

/** One inbox entry's iType, as a placement bucket (see the header for why unknown labels become tabs). */
export function bucketOf(iType: unknown, received = true): Bucket {
  const t = str(iType).trim();
  if (!t || !received) return 'missing';
  if (/^x$/i.test(t)) return 'filter';
  if (/^inbox$/i.test(t)) return 'inbox';
  if (/^spam$|junk/i.test(t)) return 'spam';
  if (/not\s*delivered|missing|not\s*found|waiting|pending/i.test(t)) return 'missing';
  return 'tabs';
}

const pct = (n: number, d: number) => (d > 0 ? Math.round((1000 * n) / d) / 10 : null);

/**
 * Per-provider counts. The denominator is every seed this test was sent to, plus any mailbox seed the report shows
 * that the list lacked; a seed the report does not show (yet) is missing. Filter-check seeds ("X") are left out.
 */
export function placement(report: any, seeds: Seed[] | string[], dir: { byEmail: Map<string, Seed>; groupName: Map<string, string> }): ProviderRow[] {
  const result = report?.result ?? report ?? {};
  const inboxes: any[] = Array.isArray(result?.inboxes) ? result.inboxes : [];
  const seen = new Map<string, any>();
  for (const i of inboxes) { const e = str(i?.email).trim().toLowerCase(); if (e) seen.set(e, i); }
  const all = new Map<string, Seed>();
  const add = (s: Seed) => { if (s.email && !all.has(s.email)) all.set(s.email, s); };
  for (const s of seeds as (Seed | string)[]) {
    const email = (typeof s === 'string' ? s : s.email).trim().toLowerCase();
    const known = dir.byEmail.get(email);
    add(known ?? (typeof s === 'string' ? { email, provider: '', provider_group_id: '' } : { ...s, email }));
  }
  for (const [email, i] of seen) {
    if (!all.has(email)) add(dir.byEmail.get(email) ?? { email, provider: '', provider_group_id: str(i?.providerGroupId) });
  }
  const rows = new Map<string, ProviderRow>();
  for (const s of all.values()) {
    const i = seen.get(s.email);
    const gid = s.provider_group_id || str(i?.providerGroupId);
    const provider = s.provider || dir.groupName.get(gid) || (gid ? `provider group ${gid}` : 'unknown provider');
    const b = bucketOf(i?.iType, !!i);
    if (b === 'filter') continue;
    const row = rows.get(provider) ?? { provider, provider_group_id: gid, is_outlook: OUTLOOK.test(provider), seeds: 0, inbox: 0, spam: 0, tabs: 0, missing: 0, inbox_pct: null, raw_itypes: {} };
    row.seeds++; row[b]++;
    const label = i ? str(i.iType) || '(empty)' : '(not received)';
    row.raw_itypes[label] = (row.raw_itypes[label] || 0) + 1;
    rows.set(provider, row);
  }
  for (const r of rows.values()) r.inbox_pct = pct(r.inbox, r.seeds);
  return [...rows.values()].sort((a, b) => Number(b.is_outlook) - Number(a.is_outlook) || a.provider.localeCompare(b.provider));
}

export function outlookOf(rows: ProviderRow[]): Outlook {
  const o = { seeds: 0, inbox: 0, spam: 0, tabs: 0, missing: 0, inbox_pct: null as number | null };
  for (const r of rows) if (r.is_outlook) { o.seeds += r.seeds; o.inbox += r.inbox; o.spam += r.spam; o.tabs += r.tabs; o.missing += r.missing; }
  o.inbox_pct = pct(o.inbox, o.seeds);
  return o;
}

/** The spam-filter and authentication results, where the report carries them. */
export function filtersOf(report: any): Record<string, unknown> {
  const r = report?.result ?? report ?? {};
  const rules = (h: any) => (Array.isArray(h?.headers) ? h.headers : [])
    .map((x: any) => ({ tag: str(x?.tag), score: Number(x?.score ?? 0), description: str(x?.description).slice(0, 200) }))
    .filter((x: any) => x.tag);
  const num = (v: unknown) => (v === undefined || v === null || v === '' ? null : Number(v));
  const out: Record<string, unknown> = {};
  if (r.spamAssassin) out.spamassassin = { score: num(r.spamAssassin.score), finished: truthy(r.spamAssassin.finished), rules: rules(r.spamAssassin) };
  if (r.microsoftEOP) out.microsoft_eop = { scl: num(r.microsoftEOP.scl), bcl: num(r.microsoftEOP.bcl), sfv: str(r.microsoftEOP.sfv), cat: str(r.microsoftEOP.cat), finished: truthy(r.microsoftEOP.finished) };
  if (r.barracuda) out.barracuda = { score: num(r.barracuda.score), reason: str(r.barracuda.reason), finished: truthy(r.barracuda.finished), rules: rules(r.barracuda) };
  if (r.hwBarracuda) out.barracuda_hw = { score: num(r.hwBarracuda.score), status: str(r.hwBarracuda.status), rules: rules(r.hwBarracuda) };
  if (r.proofPoint) out.proofpoint = { spam: truthy(r.proofPoint.spam), finished: truthy(r.proofPoint.finished) };
  if (r.googleApps) out.google = { spam: truthy(r.googleApps.spam), phishy: truthy(r.googleApps.phishy), finished: truthy(r.googleApps.finished) };
  const a = r.authenticationResult;
  if (a) out.authentication = { spf: str(a.spfAuth), dkim: str(a.dkimAuth), dmarc: str(a.dmarcAuth), sender_ip: str(a.senderIp), rdns: str(a.rDNSStatus) };
  if (r.ipListed !== undefined) out.ip_listed = truthy(r.ipListed);
  if (Array.isArray(r?.dnsbl?.results)) out.blocklists = r.dnsbl.results.reduce((n: number, x: any) => n + (Number(x?.listedCount) || 0), 0);
  if (r.stats) out.glockapps_stats = r.stats;
  return out;
}

/** Finished per GlockApps, or given up on after GIVE_UP_HOURS. */
export function completion(report: any, createdAt: Date, now: Date): { complete: boolean; gaveUp: boolean } {
  const finished = truthy((report?.result ?? report)?.finished);
  const gaveUp = !finished && now.getTime() - createdAt.getTime() >= GIVE_UP_HOURS * 3_600_000;
  return { complete: finished || gaveUp, gaveUp };
}

/** pass only when GlockApps finished, Outlook seeds exist, and Outlook inbox is at or over the bar. */
export function verdictOf(o: Outlook, c: { complete: boolean; gaveUp: boolean }): Verdict {
  if (!c.complete) return 'pending';
  if (c.gaveUp || !o.seeds || o.inbox_pct === null) return 'incomplete';
  return o.inbox_pct >= OUTLOOK_BAR_PCT ? 'pass' : 'fail';
}

const VERDICT_LINE: Record<Verdict, string> = {
  pass: 'PASS: Outlook is at or above the 80% bar. Invitations may resume; resuming is a real send and stays the founder\'s confirmation (steps: docs/reports/QuotesDone Campaign/SUPPLIER_WARMUP_PLAN_27_OCT.md). Nothing was switched on.',
  fail: 'FAIL: Outlook is below the 80% bar. Invitations stay held (ledger 1312) and the cause gets fixed.',
  incomplete: 'INCOMPLETE: GlockApps did not finish this test, or it had no Outlook seed, so it decides nothing. Invitations stay held.',
  pending: 'PENDING: GlockApps has not finished this test yet.',
};

/** The plain report the founder and the it_engineer read. */
export function summaryText(o: {
  testId: string; createdAt: string; from: string; seedsSent: number; rows: ProviderRow[]; outlook: Outlook; filters: Record<string, any>; verdict: Verdict;
}): string {
  const line = (r: { inbox: number; spam: number; tabs: number; missing: number; seeds: number; inbox_pct: number | null }) =>
    `inbox ${r.inbox}, spam ${r.spam}, tabs/promotions ${r.tabs}, missing ${r.missing} (of ${r.seeds}; ${r.inbox_pct ?? '–'}% inbox)`;
  const f = o.filters || {};
  const out = [
    `GlockApps test ${o.testId}, created ${o.createdAt}: ${o.seedsSent} seeds of the live supplier invitation from ${o.from} over the Microsoft 365 lane.`,
    '',
    `Outlook / Microsoft (outlook.com, hotmail.com, Office 365 together): ${line(o.outlook)}, against the ${OUTLOOK_BAR_PCT}% bar.`,
    '',
    'Each provider:',
    ...o.rows.map((r) => `- ${r.provider}${r.is_outlook ? ' [Outlook]' : ''}: ${line(r)}`),
  ];
  const fl: string[] = [];
  if (f.spamassassin) fl.push(`SpamAssassin score ${f.spamassassin.score ?? '–'}${f.spamassassin.rules?.length ? ' (' + f.spamassassin.rules.filter((x: any) => x.score > 0).slice(0, 6).map((x: any) => `${x.tag} ${x.score}`).join(', ') + ')' : ''}`);
  if (f.microsoft_eop) fl.push(`Microsoft EOP SCL ${f.microsoft_eop.scl ?? '–'}, BCL ${f.microsoft_eop.bcl ?? '–'}, SFV ${f.microsoft_eop.sfv || '–'}, CAT ${f.microsoft_eop.cat || '–'}`);
  if (f.barracuda) fl.push(`Barracuda score ${f.barracuda.score ?? '–'}${f.barracuda.reason ? ' (' + f.barracuda.reason + ')' : ''}`);
  if (f.proofpoint) fl.push(`Proofpoint ${f.proofpoint.spam ? 'spam' : 'not spam'}`);
  if (f.google) fl.push(`Google filter ${f.google.spam ? 'spam' : 'not spam'}${f.google.phishy ? ', phishy' : ''}`);
  if (f.authentication) fl.push(`SPF ${f.authentication.spf || '–'}, DKIM ${f.authentication.dkim || '–'}, DMARC ${f.authentication.dmarc || '–'}`);
  if (f.blocklists !== undefined) fl.push(`blocklist listings ${f.blocklists}`);
  if (fl.length) out.push('', 'Filters and authentication: ' + fl.join('; ') + '.');
  out.push('', VERDICT_LINE[o.verdict]);
  return out.join('\n');
}

/** The seed body: the live invitation for a fixture company, with the marker as its last line. */
export function seedBody(inviteBody: string, site: string, marker: string): string {
  const body = String(inviteBody || '').split('{{company}}').join('ZZ DEMO Supplier')
    .split('{{link}}').join(`${site || 'https://quotesdone.com'}/en/portal?t=00000000-0000-0000-0000-000000000000`);
  return body.trimEnd() + '\n\n' + marker;
}
