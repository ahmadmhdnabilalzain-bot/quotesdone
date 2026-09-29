// deno test --allow-read --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY supabase/functions/marketing/duties.test.ts
// The marketing duty's sweep of held comments (reviveHeldComments). Review of PR #969, 24 Sep 2026: a comment whose
// platform token was missing or could not be refreshed was re-reasoned (a model call) on every sweep. Here every
// dependency is a stub: nothing reaches a platform, the model or the database.
import { assertEquals } from 'jsr:@std/assert@1';
import type { HeldCommentRow, ReviseDueRow, ReviseIO, ReviveIO } from './duties.ts';

// duties.ts pulls in _shared/llm.ts, which builds a client at import: a placeholder loopback URL, never called.
if (!Deno.env.get('SUPABASE_URL')) Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
if (!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'placeholder-not-a-key');
const { MAX_CLASS_QUESTIONS, reviveHeldComments } = await import('./duties.ts');

const NOW = new Date('2026-09-24T10:00:00Z');
const held = (platform: HeldCommentRow['platform'], over: Partial<HeldCommentRow> = {}): HeldCommentRow => ({
  id: 1, outcome: 'held_classify', send_status: null, meta_message_id: 'cmt-' + platform, platform, body: 'Great work on this project',
  parent_id: 'post-1', occurred_at: NOW.toISOString(), conversation: { user_id: 'author-1', handle: null, account_id: 'ACCOUNT' }, ...over,
});
function rig(o: { token?: () => Promise<string | null>; questions?: { status: string }[] } = {}) {
  const calls = { classify: 0, process: 0, claim: 0, finalized: 0 };
  const io: ReviveIO = {
    finalizeSent: () => { calls.finalized++; return Promise.resolve(); },
    claim: () => { calls.claim++; return Promise.resolve(true); },
    classQuestions: () => Promise.resolve(o.questions ?? [{ status: 'answered' }]),
    ownToken: o.token ?? (() => Promise.resolve('a-token')),
    classify: () => { calls.classify++; return Promise.resolve('praise'); },
    process: () => { calls.process++; return Promise.resolve('replied'); },
  };
  return { io, calls };
}

Deno.test('a dead YouTube token: two sweeps, zero class reasonings, a named skip each time, the comment left held', async () => {
  const { io, calls } = rig({ token: () => Promise.reject(new Error('youtube token refresh HTTP 400: invalid_grant')) });
  const first = await reviveHeldComments([held('youtube')], NOW, io);
  const second = await reviveHeldComments([held('youtube')], new Date(NOW.getTime() + 600_000), io);
  assertEquals([first, second], [{ 'skipped:youtube token refresh failed': 1 }, { 'skipped:youtube token refresh failed': 1 }]);
  assertEquals([calls.classify, calls.process], [0, 0]);
});

Deno.test('LinkedIn not connected: skipped by name before any reasoning; a stale replaying row is claimed back to held first', async () => {
  const { io, calls } = rig({ token: () => Promise.resolve(null) });
  const out = await reviveHeldComments([held('linkedin'), held('linkedin', { id: 2, outcome: 'replaying:2026-09-24T09:00:00Z' })], NOW, io);
  assertEquals(out, { 'skipped:linkedin token missing': 2 });
  assertEquals([calls.claim, calls.classify, calls.process], [1, 0, 0]);
});

Deno.test('connected: the class is reasoned and the policy runs; Meta platforms need no token check', async () => {
  let asked = 0;
  const { io, calls } = rig({ token: () => { asked++; return Promise.resolve('yt-token'); } });
  const out = await reviveHeldComments([held('youtube'), held('instagram', { id: 3 })], NOW, io);
  assertEquals(out, { 'revived:replied': 2 });
  assertEquals([asked, calls.classify, calls.process], [1, 2, 2]);
});

Deno.test('a comment whose class was asked MAX_CLASS_QUESTIONS times is not asked again', async () => {
  const { io, calls } = rig({ questions: Array.from({ length: MAX_CLASS_QUESTIONS }, () => ({ status: 'answered' })) });
  const out = await reviveHeldComments([held('instagram')], NOW, io);
  assertEquals(out, { ['skipped:class asked ' + MAX_CLASS_QUESTIONS + ' times']: 1 });
  assertEquals(calls.classify, 0);
});

Deno.test('unchanged: an open class question waits, a fresh replay is left alone, a sent reply is finalized', async () => {
  const { io, calls } = rig({ questions: [{ status: 'held' }] });
  const out = await reviveHeldComments([
    held('instagram'),
    held('instagram', { id: 4, outcome: 'replaying:' + new Date(NOW.getTime() - 60_000).toISOString() }),
    held('instagram', { id: 5, send_status: 'sent' }),
  ], NOW, io);
  assertEquals(out, { finalized_sent: 1 });
  assertEquals([calls.classify, calls.claim, calls.finalized], [0, 0, 1]);
});

Deno.test('class questions unreadable: skipped this sweep, never reasoned blind', async () => {
  const { io, calls } = rig();
  io.classQuestions = () => Promise.reject(new Error('db down'));
  assertEquals(await reviveHeldComments([held('instagram')], NOW, io), { 'skipped:class questions unreadable': 1 });
  assertEquals(calls.classify, 0);
});

// ── THE ARTICLE REDRAW (release review of #1114): a refused redraw is paid for once per content, not once a beat ─────
const { reviseOne } = await import('./duties.ts');
const FIRST = JSON.parse(await Deno.readTextFile(new URL('../../../scripts/marketing/articles/how-quotesdone-works-for-procurement-teams.json', import.meta.url)));
const dueRow = (change = 'Say that replies come within 3 working days.', slug: string = FIRST.slug): ReviseDueRow =>
  ({ slug, kind: 'guide', change, earlier_changes: [], sources: [], article: { en: FIRST.en, ar: FIRST.ar } });
function reviseRig(o: { ingest?: { ok: boolean; reason?: string }; error?: string } = {}) {
  const runs: { subject: string; outcome: string; reason: string; run_day: string }[] = [];
  const calls = { model: 0, ingest: 0 };
  const redraw = structuredClone({ en: FIRST.en, ar: FIRST.ar });
  redraw.en.excerpt += ' Replies come within 3 working days.';
  let day = '2026-09-29';
  const io: ReviseIO = {
    lastRun: (s) => Promise.resolve(runs.filter((r) => r.subject === s).at(-1) ?? null),
    held: () => Promise.resolve(false),
    callModel: () => { calls.model++; return Promise.resolve(o.error ? { content: null, error: o.error } : { content: JSON.stringify(redraw), model: 'stub' }); },
    recordFailed: (subject, reason) => { runs.push({ subject, outcome: 'failed', reason, run_day: day }); return Promise.resolve(); },
    ingest: () => { calls.ingest++; return Promise.resolve(o.ingest ?? { ok: true }); },
  };
  return { io, calls, runs, setDay: (d: string) => { day = d; } };
}
const raised = async (p: Promise<unknown>) => { try { await p; return null; } catch (e) { return String((e as Error).message); } };

Deno.test('a refused ingest writes one failed row with its reason, and the next beats make ZERO model calls', async () => {
  const { io, calls, runs } = reviseRig({ ingest: { ok: false, reason: 'text_lost_its_script' } });
  const err = await raised(reviseOne([dueRow()], '2026-09-29', io));
  assertEquals(err?.includes('text_lost_its_script'), true);
  assertEquals([calls.model, calls.ingest, runs.length, runs[0].outcome, runs[0].reason.includes('text_lost_its_script')], [1, 1, 1, 'failed', true]);
  const second = await reviseOne([dueRow()], '2026-09-29', io);
  const nextDay = await reviseOne([dueRow()], '2026-09-30', io);
  assertEquals([calls.model, calls.ingest, runs.length], [1, 1, 1]);
  assertEquals([second.waiting, nextDay.waiting], [[FIRST.slug], [FIRST.slug]]);
});

Deno.test('a new change is new content: the redraw is tried again', async () => {
  const { io, calls } = reviseRig({ ingest: { ok: false, reason: 'text_lost_its_script' } });
  await raised(reviseOne([dueRow()], '2026-09-29', io));
  await raised(reviseOne([dueRow('Shorten the second section.')], '2026-09-29', io));
  assertEquals(calls.model, 2);
});

Deno.test('no answer from the model: recorded, not retried the same Dubai day, retried once the next', async () => {
  const { io, calls, runs, setDay } = reviseRig({ error: 'HTTP 503' });
  await raised(reviseOne([dueRow()], '2026-09-29', io));
  await reviseOne([dueRow()], '2026-09-29', io);
  assertEquals([calls.model, runs.length], [1, 1]);
  setDay('2026-09-30');
  await raised(reviseOne([dueRow()], '2026-09-30', io));
  await reviseOne([dueRow()], '2026-09-30', io);
  assertEquals([calls.model, runs.length], [2, 2]);
});

Deno.test('a failed draft does not block the one behind it, and a beat makes at most one model call', async () => {
  const first = reviseRig({ ingest: { ok: false, reason: 'x' } });
  await raised(reviseOne([dueRow()], '2026-09-29', first.io));
  const { io, calls } = reviseRig();
  io.lastRun = first.io.lastRun;   // the first draft's failed run is on record
  const out = await reviseOne([dueRow(), dueRow(undefined, 'another-article'), dueRow('third', 'a-third-article')], '2026-09-29', io);
  assertEquals([out.redrawn, calls.model], ['another-article', 1]);
});
