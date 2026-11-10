// deno test --allow-read --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY supabase/functions/marketing/duties.test.ts
// The marketing duty's sweep of held comments (reviveHeldComments). Review of PR #969, 24 Sep 2026: a comment whose
// platform token was missing or could not be refreshed was re-reasoned (a model call) on every sweep. Here every
// dependency is a stub: nothing reaches a platform, the model or the database.
import { assertEquals } from 'jsr:@std/assert@1';
import type { FailedRun, HeldCommentRow, JobIO, ModelJob, ReviveIO } from './duties.ts';

// duties.ts pulls in _shared/llm.ts, which builds a client at import: a placeholder loopback URL, never called.
if (!Deno.env.get('SUPABASE_URL')) Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
if (!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'placeholder-not-a-key');
const { MAX_CLASS_QUESTIONS, reviveHeldComments, specHashText } = await import('./duties.ts');

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

// ── THE BLOG'S MODEL STEPS (release review of #1114): a refused step is paid for once, never once a beat ─────────────
// runOneJob drives article_draft, article_review and article_revise. The model, the database and the clock are stubs:
// no paid call is made.
const { runOneJob, GIVE_UP_AFTER } = await import('./duties.ts');
function jobRig(o: { write?: { ok: boolean; reason?: string }; error?: string; held?: boolean } = {}) {
  const runs: (FailedRun & { step: string })[] = [];
  const calls = { model: 0, write: 0, gaveUp: 0, prompts: [] as string[] };
  let day = '2026-09-29';
  const job = (key = 'topic:7', label = 'Waterproofing a villa roof before the summer'): ModelJob => ({
    step: 'article_draft', seat: 'marketing', taskClass: 'marketing_article_draft', max: 8000, key, label, content: { key },
    prompt: (refused) => 'write it' + (refused.length ? ' | refused: ' + refused.join(' | ') : ''),
    accept: (ans) => ans ? { ok: true, value: ans } : { ok: false, reason: 'no answer' },
    write: () => { calls.write++; return Promise.resolve(o.write ?? { ok: true }); },
    giveUp: () => { calls.gaveUp++; return Promise.resolve(); },
  });
  const io: JobIO = {
    failedRuns: (j) => Promise.resolve(runs.filter((r) => r.step === j.step && r.subject.startsWith(j.key + '#'))),
    held: () => Promise.resolve(!!o.held),
    callModel: (_j, prompt) => { calls.model++; calls.prompts.push(prompt); return Promise.resolve(o.error ? { content: null, error: o.error } : { content: '{"en":{}}', model: 'stub' }); },
    recordFailed: (j, subject, reason) => { runs.push({ step: j.step, subject, reason, run_day: day }); return Promise.resolve(); },
  };
  return { io, job, calls, runs, setDay: (d: string) => { day = d; } };
}
const raised = async (p: Promise<unknown>) => { try { await p; return null; } catch (e) { return String((e as Error).message); } };

Deno.test('a refused write (text_lost_its_script) records ONE failed row with its reason, and the next beat makes ZERO model calls', async () => {
  const { io, job, calls, runs } = jobRig({ write: { ok: false, reason: 'fn_marketing_blog_submit: text_lost_its_script' } });
  const err = await raised(runOneJob([job()], '2026-09-29', io));
  assertEquals(err?.includes('text_lost_its_script'), true);
  assertEquals([calls.model, calls.write, runs.length, runs[0].reason?.includes('text_lost_its_script')], [1, 1, 1, true]);
  const second = await runOneJob([job()], '2026-09-29', io);
  const third = await runOneJob([job()], '2026-09-29', io);
  assertEquals([calls.model, calls.write, runs.length], [1, 1, 1]);
  assertEquals([second.waiting, third.waiting], [[job().label], [job().label]]);
});

Deno.test('the next Dubai day it is tried once more, carrying the refusal; after 3 refusals the topic is replaced, not called', async () => {
  const { io, job, calls, runs, setDay } = jobRig({ write: { ok: false, reason: 'names_a_supplier' } });
  for (const d of ['2026-09-29', '2026-09-30', '2026-10-01']) {
    setDay(d);
    await raised(runOneJob([job()], d, io));
    await runOneJob([job()], d, io);   // the same day again: no call
  }
  assertEquals([calls.model, runs.length, new Set(runs.map((r) => r.subject)).size], [GIVE_UP_AFTER, GIVE_UP_AFTER, GIVE_UP_AFTER]);
  assertEquals(calls.prompts[1].includes('refused: refused when written: names_a_supplier'), true);
  setDay('2026-10-02');
  const out = await runOneJob([job()], '2026-10-02', io);
  assertEquals([out.gave_up, calls.gaveUp, calls.model], [job().label, 1, GIVE_UP_AFTER]);
});

Deno.test('no answer from the model: recorded, not retried the same day, retried the next, and never counted toward giving up', async () => {
  const { io, job, calls, runs, setDay } = jobRig({ error: 'HTTP 503' });
  for (const d of ['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02']) {
    setDay(d);
    await raised(runOneJob([job()], d, io));
    await runOneJob([job()], d, io);
  }
  assertEquals([calls.model, runs.length, calls.gaveUp], [4, 4, 0]);
});

Deno.test('a waiting job does not block the next, a beat makes at most one call, and the hold calls nothing', async () => {
  const { io, job, calls } = jobRig({ write: { ok: false, reason: 'x' } });
  await raised(runOneJob([job()], '2026-09-29', io));
  const ok = jobRig();
  ok.io.failedRuns = io.failedRuns;   // the first job's refusal is on record
  const out = await runOneJob([ok.job(), ok.job('topic:8', 'second'), ok.job('topic:9', 'third')], '2026-09-29', ok.io);
  assertEquals([out.done, ok.calls.model, calls.model], ['second', 1, 1]);
  const h = jobRig({ held: true });
  assertEquals([(await runOneJob([job()], '2026-09-29', h.io)).held, h.calls.model], [true, 0]);
});


const PZ = 'https://raw.githubusercontent.com/gitroomhq/postiz-app/main/libraries/nestjs-libraries/src/integrations/social/x.provider.ts';
const XFILE = (extra: string, limit: string, comment = '') => `import a from 'b';\n${extra}\nclass X {\n  override maxConcurrentJob = 10;\n  maxLength(s?: any) {\n    ${comment}\n    if (s?.post_type === 'article') {\n      return 100000;\n    }\n    return ${limit};\n  }\n  other() { return 1; }\n}\n`;

Deno.test('a Postiz provider file is hashed on maxLength() alone: unrelated upstream commits do not change it, a new limit does', () => {
  const base = specHashText(PZ, XFILE('', '4000 : 280'));
  assertEquals(specHashText(PZ, XFILE('// a new import and a new method elsewhere\nconst z = 9;', '4000 : 280', '// reworded comment')), base);
  assertEquals(specHashText(PZ, XFILE('', '4000 : 280').replace('other() { return 1; }', 'other() { return 2; }')), base);
  assertEquals(specHashText(PZ, XFILE('', '4000 : 280').replace('maxConcurrentJob = 10', 'maxConcurrentJob = 20')), base);
  assertEquals(specHashText(PZ, XFILE('', '4000 : 300') ) === base, false);
});

Deno.test('a Postiz file with no maxLength() hashes as a fixed marker; other pages keep the visible-text hash', () => {
  assertEquals(specHashText(PZ, 'class X {}'), specHashText(PZ, 'class Y { z() {} }'));
  assertEquals(specHashText('https://docs.x.com/a', '<p>hello   <b>world</b></p><script>1</script>'), 'hello world');
});
