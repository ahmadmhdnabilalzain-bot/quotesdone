// deno test --allow-read --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY supabase/functions/marketing/duties.test.ts
// The marketing duty's sweep of held comments (reviveHeldComments). Review of PR #969, 24 Sep 2026: a comment whose
// platform token was missing or could not be refreshed was re-reasoned (a model call) on every sweep. Here every
// dependency is a stub: nothing reaches a platform, the model or the database.
import { assertEquals } from 'jsr:@std/assert@1';
import type { HeldCommentRow, ReviveIO } from './duties.ts';

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
