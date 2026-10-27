// deliverability_test: create / collect / report, with every dependency injected (27 Oct 2026; Assigned: it_engineer).
//
// index.ts wires the real database, the real fetch and the edge secrets; handler.test.ts wires fakes and replays the
// documented GlockApps examples. Nothing here can switch the supplier invitation campaign on: the only app_secrets
// row this function ever writes is REQUEST_KEY, the one-shot "please run a test" flag it consumes
// (no_invitation_switch_is_written.test.ts reads this folder and fails otherwise). Resuming invitations is a real
// send to real suppliers, so it stays the founder's confirmation (ledger 1312, 1340).
//
// WHO MAY CALL IT: the service role, or an internal credential scoped to this function (cred_fn_deliverability_test,
// held by the it_engineer duty fn_deliverability_test_tick). Anyone else gets 403 before any work is done.
import * as G from './glockapps.ts';
import { M365_SEED_KIND, seedMarker } from '../send_outbox/m365_lane.ts';

export const FN = 'deliverability_test';
export const REQUEST_KEY = 'deliverability_test_request';
export const PROJECT_KEY = 'deliverability_test_project_id';
export const KEY_MISSING_ISSUE = 'glockapps_api_key_missing';
export const SECRETS_WHERE = 'Supabase dashboard > Edge Functions > Secrets, name GLOCKAPPS_API_KEY';

export type TestRow = {
  test_id: string; project_id: string | null; created_at: string; reason: string; marker: string; from_address: string | null;
  seeds: G.Seed[]; status: string; verdict: string; polls: number; reported_at: string | null; summary: string | null;
  outlook: G.Outlook | null; outlook_inbox_pct: number | null;
};
export type SeedRow = {
  type: 'supplier_invite_seed'; kind: string; to_email: string; to_role: 'supplier'; subject: string; body: string;
  lang: 'en'; status: 'queued'; requested_by: 'it_engineer'; dedupe_key: string;
};
export type Db = {
  secret(key: string): Promise<string>;
  clearRequest(): Promise<void>;
  openTest(): Promise<TestRow | null>;
  getTest(testId: string): Promise<TestRow | null>;
  latestTest(): Promise<TestRow | null>;
  insertTest(row: Record<string, unknown>): Promise<void>;
  updateTest(testId: string, patch: Record<string, unknown>): Promise<void>;
  /** The subset of these addresses that belong to a lead or customer we hold. */
  knownParties(emails: string[]): Promise<Set<string>>;
  queueSeeds(rows: SeedRow[]): Promise<number[]>;
  upsertProviders(testId: string, rows: G.ProviderRow[]): Promise<void>;
  fileVerdict(testId: string): Promise<unknown>;
  finding(args: Record<string, unknown>): Promise<void>;
  closeFinding(issueKey: string, note: string): Promise<void>;
};
export type Deps = {
  db: Db; fetch: G.Fetch; env: (k: string) => string | undefined; now: () => Date;
  serviceKey: string; internalAuth: (secret: string) => Promise<boolean>;
};
type Out = { http: number; body: Record<string, unknown> };
const ok = (body: Record<string, unknown>, http = 200): Out => ({ http, body: { ok: true, ...body } });
const no = (status: string, message: string, extra: Record<string, unknown> = {}, http = 200): Out =>
  ({ http, body: { ok: false, status, message, ...extra } });

/** Constant-time string comparison, so the service key is not guessable by timing. */
export function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

/** Service role (Bearer or apikey = the service key) or a scoped internal credential in body.__secret. Nothing else. */
export async function authorized(headers: Headers, body: Record<string, unknown>, d: Deps): Promise<boolean> {
  const bearer = (headers.get('authorization') || '').replace(/^Bearer\s+/i, '').trim();
  if (sameSecret(bearer, d.serviceKey) || sameSecret((headers.get('apikey') || '').trim(), d.serviceKey)) return true;
  const s = typeof body.__secret === 'string' ? body.__secret : '';
  return s ? await d.internalAuth(s) : false;
}

async function keyMissing(d: Deps, action: string): Promise<Out> {
  // A requested test that cannot run is the it_engineer's to see; the upsert is idempotent, so a 15-minute tick files it once.
  if (action === 'create') {
    try {
      await d.db.finding({
        p_issue_key: KEY_MISSING_ISSUE,
        p_title: 'The GlockApps API key is not set, so the deliverability test cannot run',
        p_where: 'edge function deliverability_test; secret ' + G.GLOCKAPPS_KEY_NAME, p_blast: 'internal', p_affected: 0,
        p_evidence: { needs: G.GLOCKAPPS_KEY_NAME, where: SECRETS_WHERE, effect: 'no GlockApps test is created or collected; invitations stay held (ledger 1312)' },
        p_ruled_out: [], p_undetermined: [], p_raised_by: 'it_engineer',
      });
    } catch (_e) { /* the answer below still says it */ }
  }
  return no('key_missing', `${G.GLOCKAPPS_KEY_NAME} is not set. Add it in ${SECRETS_WHERE}; the key is in GlockApps account settings.`, { action });
}

function failure(e: unknown, key: string): Out {
  if (e instanceof G.GlockAppsError) return no('glockapps_error', G.scrubKey(e.message, key), { http_status: e.status }, 502);
  return no('error', G.scrubKey(String((e as Error)?.message || e), key).slice(0, 300), {}, 500);
}

// ---------------------------------------------------------------------------------------------------------- create
export async function create(d: Deps, body: Record<string, unknown>): Promise<Out> {
  const key = String(d.env(G.GLOCKAPPS_KEY_NAME) || '').trim();
  if (!key) return keyMissing(d, 'create');
  const open = await d.db.openTest();
  if (open && body.force !== true) return no('test_open', `GlockApps test ${open.test_id} is still being collected; a second one would spend a credit for nothing.`, { test_id: open.test_id });
  const reason = String(body.reason || 'requested').slice(0, 200);
  const [inviteBody, subject, site, mailbox] = await Promise.all(['invite_body', 'invite_subject', 'public_site_url', 'invite_m365_mailbox'].map((k) => d.db.secret(k)));
  if (!inviteBody.trim() || !subject.trim()) return no('no_live_copy', 'app_secrets invite_subject / invite_body are empty, so there is no live invitation to test.');
  const ga = G.glockapps(key, d.fetch);
  let projectId = '', testId = '';
  try {
    try {
      const bal = await ga.balance();
      const left = Number(bal?.testCredits?.balance);
      if (Number.isFinite(left) && left < 1) return no('no_credits', 'The GlockApps account has no spam-test credit left.', { balance: bal?.testCredits });
    } catch (_e) { /* the balance is advisory; the create call is what decides */ }
    projectId = G.pickProject(await ga.projects(), await d.db.secret(PROJECT_KEY));
    if (!projectId) return no('no_project', 'The GlockApps account lists no project to create the test in.');
    const dir = G.seedDirectory(await ga.providers(projectId));
    const groupIds = Array.isArray(body.provider_group_ids) ? body.provider_group_ids.map(String) : [...dir.groupName.keys()];
    const created = await ga.createManualTest(projectId, {
      ...(groupIds.length ? { providerGroupIds: groupIds } : {}),
      note: `QuotesDone supplier invitation from ${mailbox || 'supplier@quotesdone.com'} over the Microsoft 365 lane: ${reason}`.slice(0, 250),
      linkChecker: false,
    });
    testId = String(created?.testId || '').trim();
    const marker = G.markerFor(created || {});
    const refund = async (status: string, message: string, extra: Record<string, unknown> = {}) => {
      // "can be returned if the created test is deleted before any emails are sent" (Swagger, manualTest)
      let refunded = false;
      if (testId) { try { await ga.deleteTest(projectId, testId); refunded = true; } catch (_e) { /* reported below */ } }
      return no(status, message, { test_id: testId, refunded, ...extra });
    };
    if (!testId || !marker) return await refund('marker_unusable', `GlockApps returned test id "${testId}", which the Microsoft 365 lane cannot carry as the body's last line.`);
    const emails = Array.isArray(created?.emails) && created.emails.length ? created.emails : (await ga.seedAccounts(projectId, testId))?.result?.emails;
    const listed = (Array.isArray(emails) ? emails : []).map((e: unknown) => String(e).trim().toLowerCase());
    const seeds = G.seedAddresses(listed, await d.db.knownParties(listed));
    if (!seeds.send.length) return await refund('no_seeds', 'GlockApps returned no seed address this function may send to.', { refused: seeds.refused });
    if (seeds.send.length > G.MAX_SEEDS) return await refund('too_many_seeds', `${seeds.send.length} seeds is above the Microsoft 365 lane's ${G.MAX_SEEDS} a day.`);
    const text = G.seedBody(inviteBody, site, marker);
    if (seedMarker(text) !== marker) return await refund('marker_unusable', 'The seed body would not keep the marker as its last line.');
    const seedRows = seeds.send.map((email) => dir.byEmail.get(email) ?? { email, provider: '', provider_group_id: '' });
    await d.db.insertTest({
      test_id: testId, project_id: projectId, reason, requested_by: 'it_engineer', marker, from_address: mailbox || null,
      seeds: seedRows, seeds_refused: seeds.refused, status: 'seeds_queued', verdict: 'pending', created_at: d.now().toISOString(),
    });
    const ids = await d.db.queueSeeds(seeds.send.map((email) => ({
      type: 'supplier_invite_seed', kind: M365_SEED_KIND, to_email: email, to_role: 'supplier', subject, body: text,
      lang: 'en', status: 'queued', requested_by: 'it_engineer', dedupe_key: `glockapps:${testId}:${email}`,
    })));
    await d.db.updateTest(testId, { notification_ids: ids });
    await d.db.clearRequest();
    try { await d.db.closeFinding(KEY_MISSING_ISSUE, 'closed by deliverability_test: a GlockApps test was created with the key'); } catch (_e) { /* bookkeeping */ }
    return ok({ status: 'seeds_queued', test_id: testId, project_id: projectId, marker, seeds: ids.length, refused: seeds.refused }, 201);
  } catch (e) { return failure(e, key); }
}

// ---------------------------------------------------------------------------------------------------------- collect
/** Find which project holds a test that was created outside this function (the dashboard). */
async function projectOf(ga: G.GlockApps, testId: string): Promise<string> {
  const list: any[] = (await ga.projects())?.results ?? [];
  for (const p of list) {
    try { const r = await ga.testReport(String(p.id), testId); if (String(r?.result?.testId || '') === testId) return String(p.id); }
    catch (_e) { /* not in this project */ }
  }
  return '';
}

export async function collect(d: Deps, body: Record<string, unknown>): Promise<Out> {
  const key = String(d.env(G.GLOCKAPPS_KEY_NAME) || '').trim();
  if (!key) return keyMissing(d, 'collect');
  const row = body.test_id ? await d.db.getTest(String(body.test_id)) : await d.db.openTest();
  if (!row) return ok({ status: 'nothing_to_collect' });
  if (row.verdict !== 'pending') return report(d, { test_id: row.test_id });
  const ga = G.glockapps(key, d.fetch);
  try {
    const projectId = row.project_id || await projectOf(ga, row.test_id);
    if (!projectId) {
      await d.db.updateTest(row.test_id, { polls: row.polls + 1, last_polled_at: d.now().toISOString(), last_error: 'no project in the account holds this test' });
      return no('test_not_found', `No GlockApps project in this account holds test ${row.test_id}.`, { test_id: row.test_id });
    }
    const [rep, providers] = await Promise.all([ga.testReport(projectId, row.test_id), ga.providers(projectId)]);
    const dir = G.seedDirectory(providers);
    const seeds = row.seeds?.length ? row.seeds : ((await ga.seedAccounts(projectId, row.test_id))?.result?.emails ?? []);
    const rows = G.placement(rep, seeds, dir);
    const outlook = G.outlookOf(rows);
    const filters = G.filtersOf(rep);
    const comp = G.completion(rep, new Date(row.created_at), d.now());
    const verdict = G.verdictOf(outlook, comp);
    const decided = verdict !== 'pending';
    const summary = G.summaryText({
      testId: row.test_id, createdAt: row.created_at, from: row.from_address || 'supplier@quotesdone.com',
      seedsSent: seeds.length, rows, outlook, filters, verdict,
    });
    await d.db.upsertProviders(row.test_id, rows);
    await d.db.updateTest(row.test_id, {
      project_id: projectId, polls: row.polls + 1, last_polled_at: d.now().toISOString(), last_error: null,
      status: !decided ? 'collecting' : verdict === 'incomplete' ? 'incomplete' : 'complete',
      stats: (rep?.result ?? rep)?.stats ?? null, filters, outlook, outlook_inbox_pct: outlook.inbox_pct, verdict, summary,
      ...(decided ? { decided_at: d.now().toISOString() } : {}),
    });
    const filed = decided ? await d.db.fileVerdict(row.test_id) : null;
    return ok({ status: decided ? 'decided' : 'collecting', test_id: row.test_id, verdict, outlook, providers: rows, filters, summary, filed });
  } catch (e) {
    const out = failure(e, key);
    try { await d.db.updateTest(row.test_id, { polls: row.polls + 1, last_polled_at: d.now().toISOString(), last_error: String(out.body.message).slice(0, 500) }); } catch (_e) { /* keep the answer */ }
    return out;
  }
}

// ---------------------------------------------------------------------------------------------------------- report
export async function report(d: Deps, body: Record<string, unknown>): Promise<Out> {
  const row = body.test_id ? await d.db.getTest(String(body.test_id)) : await d.db.latestTest();
  if (!row) return no('no_test', 'No deliverability test has been recorded yet.');
  const decided = row.verdict !== 'pending';
  const filed = decided && !row.reported_at ? await d.db.fileVerdict(row.test_id) : null;
  return ok({
    status: decided ? 'decided' : 'collecting', test_id: row.test_id, verdict: row.verdict,
    outlook_inbox_pct: row.outlook_inbox_pct, bar_pct: G.OUTLOOK_BAR_PCT,
    pass: row.verdict === 'pass', outlook: row.outlook, summary: row.summary, reported_at: row.reported_at, filed,
  });
}

export async function handle(req: Request, d: Deps): Promise<Out> {
  if (req.method !== 'POST') return no('method_not_allowed', 'POST only.', {}, 405);
  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { body = {}; }
  if (!body || typeof body !== 'object') body = {};
  if (!(await authorized(req.headers, body, d))) return no('forbidden', 'Service role or a scoped internal credential only.', {}, 403);
  const action = String(body.action || '');
  if (action === 'create') return create(d, body);
  if (action === 'collect') return collect(d, body);
  if (action === 'report') return report(d, body);
  return no('unknown_action', 'action must be create, collect or report.', {}, 400);
}
