// AN INBOUND BURST IS ACCEPTED AT ONCE AND READ IN TURN (it_engineer, 15 Nov 2026).
// 15 Nov 2026 18:40-18:54 UTC: 18 receipts forwarded in 3 minutes were each read inside their own webhook request; most
// answered 546, some 504 after 150 s, and 5 of 18 reached inbound_messages. This drives resend_inbound's OWN handler with
// Svix-signed deliveries over a stubbed fetch, and its reader (lib/queue.ts drainQueue) with a stubbed pipeline, against an
// in-memory queue that keeps the rules of scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql (the
// rolled-back probe beside that file holds the SQL itself to the same rules). No value below is real: ZZ DEMO, example.invalid.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE \
//     --allow-read=. --allow-net=127.0.0.1 supabase/functions/resend_inbound/an_inbound_burst_is_accepted_at_once_and_read_in_turn.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';

const SECRET_RAW = new Uint8Array(32).map((_, i) => i + 7);
const SIGNING = 'whsec_' + btoa(String.fromCharCode(...SECRET_RAW));
const TOKEN = 'zz-demo-inbound-token-burst';
const FOUNDER = 'founder@example.invalid';
const DB_INTERNAL = 'zz-demo-db-internal-credential-000000';
const SECRETS: Record<string, string> = { resend_inbound_token: TOKEN, resend_inbound_signing_secret: SIGNING };

Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
Deno.env.set('RESEND_INBOUND_NO_SERVE', '1');

// ---- The queue, in memory, with the SQL file's rules: unique provider id; at most READERS reading; a thread waits for its
// earlier message; a 150 s lease taken back after it runs out; backoff 1/5/15/60 min; dead at max_attempts. ----
type Row = { id: number; provider_email_id: string; svix_id: string | null; payload: string; from_email: string; to_email: string;
  thread_key: string | null; owner_seat: string; status: 'queued' | 'reading' | 'done' | 'dead'; attempts: number; max_attempts: number;
  next_attempt_at: number; claimed_by: string | null; lease_until: number | null; last_error: string | null; outcome: unknown };
const READERS = 2; const LEASE = 150_000;
const backoff = (n: number) => (n <= 1 ? 1 : n === 2 ? 5 : n === 3 ? 15 : 60) * 60_000;
class MemQueue {
  rows: Row[] = []; clock = Date.now(); deadLetters: { id: number; reason: string; seat: string }[] = []; touches = 0; acceptDown = false;
  kicks: number[] = []; onKick: (n: number) => void = () => {};
  now = () => this.clock;
  private dead(r: Row, reason: string) { r.status = 'dead'; r.lease_until = null; r.last_error = reason; this.deadLetters.push({ id: r.id, reason, seat: r.owner_seat }); }
  rpc = (fn: string, a: Record<string, unknown>) => Promise.resolve(this.call(fn, a));
  // deno-lint-ignore no-explicit-any
  call(fn: string, a: any): { data: any; error: { message: string } | null } {
    if (fn === 'fn_inbound_mail_accept') {
      if (this.acceptDown) return { data: null, error: { message: 'could not find the function public.fn_inbound_mail_accept' } };
      const seen = this.rows.find((r) => r.provider_email_id === a.p_provider_email_id);
      if (seen) return { data: { queued: false, duplicate: true, id: seen.id, status: seen.status }, error: null };
      const r: Row = { id: this.rows.length + 1, provider_email_id: a.p_provider_email_id, svix_id: a.p_svix_id, payload: a.p_payload,
        from_email: a.p_from, to_email: a.p_to, thread_key: a.p_thread_key, owner_seat: a.p_owner_seat, status: 'queued', attempts: 0,
        max_attempts: 5, next_attempt_at: this.clock, claimed_by: null, lease_until: null, last_error: null, outcome: null };
      this.rows.push(r);
      return { data: { queued: true, duplicate: false, id: r.id }, error: null };
    }
    if (fn === 'fn_inbound_mail_claim') {
      for (const r of this.rows.filter((x) => x.status === 'reading' && (x.lease_until ?? 0) < this.clock)) {
        if (r.attempts >= r.max_attempts) this.dead(r, 'the reader stopped ' + r.attempts + ' times without finishing');
        else Object.assign(r, { status: 'queued', claimed_by: null, lease_until: null, next_attempt_at: this.clock + backoff(r.attempts),
          last_error: 'attempt ' + r.attempts + ': the reader stopped without finishing (its lease ran out)' });
      }
      const slots = Math.min(Math.max(a.p_limit ?? 1, 1), 10, READERS - this.rows.filter((x) => x.status === 'reading').length);
      if (slots <= 0) return { data: [], error: null };
      const open = (x: Row) => x.status === 'queued' || x.status === 'reading';
      const take = this.rows.filter((c) => c.status === 'queued' && c.next_attempt_at <= this.clock && c.attempts < c.max_attempts
        && (c.thread_key === null || !this.rows.some((e) => e.thread_key === c.thread_key && e.id < c.id && open(e)))).slice(0, slots);
      for (const r of take) Object.assign(r, { status: 'reading', attempts: r.attempts + 1, claimed_by: a.p_worker, lease_until: this.clock + LEASE });
      return { data: take.map((r) => ({ ...r })), error: null };
    }
    if (fn === 'fn_inbound_mail_touch') {
      this.touches++;
      const r = this.rows.find((x) => x.id === a.p_id && x.status === 'reading' && x.claimed_by === a.p_worker);
      if (r) r.lease_until = this.clock + LEASE;
      return { data: !!r, error: null };
    }
    if (fn === 'fn_inbound_mail_finish') {
      const r = this.rows.find((x) => x.id === a.p_id);
      if (!r || r.status !== 'reading' || r.claimed_by !== a.p_worker) return { data: { finished: false }, error: null };
      if (a.p_ok) { Object.assign(r, { status: 'done', lease_until: null, outcome: a.p_outcome }); return { data: { finished: true, status: 'done' }, error: null }; }
      if (r.attempts >= r.max_attempts) { this.dead(r, 'attempt ' + r.attempts + ': ' + a.p_error); return { data: { finished: true, status: 'dead' }, error: null }; }
      Object.assign(r, { status: 'queued', claimed_by: null, lease_until: null, next_attempt_at: this.clock + backoff(r.attempts), last_error: 'attempt ' + r.attempts + ': ' + a.p_error });
      return { data: { finished: true, status: 'queued' }, error: null };
    }
    if (fn === 'fn_inbound_mail_kick') {   // pg_net's request to resend_inbound?drain=1, once per free slot a due message can take
      const due = this.rows.filter((x) => (x.status === 'queued' && x.next_attempt_at <= this.clock) || (x.status === 'reading' && (x.lease_until ?? 0) < this.clock)).length;
      const live = this.rows.filter((x) => x.status === 'reading' && (x.lease_until ?? 0) >= this.clock).length;
      const n = Math.min(due, Math.max(0, READERS - live));
      this.kicks.push(n); this.onKick(n);
      return { data: { kicked: n, due, reading: live }, error: null };
    }
    if (fn === 'fn_inbound_mail_requeue') {
      const r = this.rows.find((x) => x.id === a.p_id && x.status === 'dead');
      if (r) Object.assign(r, { status: 'queued', attempts: 0, next_attempt_at: this.clock });
      return { data: { requeued: !!r }, error: null };
    }
    throw new Error('the queue has no routine ' + fn);
  }
}
let Q = new MemQueue();

const restCalls: string[] = [];
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init);
  const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  restCalls.push(u.pathname);
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(fn_inbound_mail_\w+)$/);
  if (rpc) { const r = Q.call(rpc[1], JSON.parse(body || '{}')); return r.error ? json({ message: r.error.message }, 404) : json(r.data); }
  if (u.pathname === '/rest/v1/rpc/fn_internal_auth') {
    const p = JSON.parse(body); return json(p.p_secret === DB_INTERNAL && p.p_function === 'resend_inbound' ? { ok: true, context: 'db.internal', credential_id: 9 } : { ok: false });
  }
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') {
    const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')];
    if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]);
    return one ? json({ value: v }) : json([{ value: v }]);
  }
  return one ? json({ id: 1 }) : json([{ id: 1 }]);
}) as typeof fetch;

const { handler, useReader, readQueued } = await import('./index.ts');
const { drainQueue, envelopeOf } = await import('./lib/queue.ts');

const drainRequest = (secret: string) => new Request('http://stub.invalid/functions/v1/resend_inbound?drain=1',
  { method: 'POST', body: JSON.stringify({ __secret: secret, drain: true }), headers: { 'Content-Type': 'application/json' } });

async function signed(data: Record<string, unknown>, svixId: string): Promise<Request> {
  const raw = JSON.stringify({ type: 'email.received', data });
  const ts = String(Math.floor(Date.now() / 1000));
  const key = await crypto.subtle.importKey('raw', SECRET_RAW, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(svixId + '.' + ts + '.' + raw)))));
  return new Request('http://stub.invalid/functions/v1/resend_inbound?s=' + TOKEN, {
    method: 'POST', body: raw, headers: { 'svix-id': svixId, 'svix-timestamp': ts, 'svix-signature': 'v1,' + sig } });
}
const receipt = (n: number) => signed({ email_id: 'zz-demo-receipt-' + n, from: 'ZZ DEMO Founder <' + FOUNDER + '>',
  to: ['expenses@mail.quotesdone.com'], subject: 'Fwd: ZZ DEMO receipt ' + n, attachments: [{ id: 'att-' + n, filename: 'receipt-' + n + '.pdf' }] }, 'msg_zz_receipt_' + n);

/** A stand-in for pipeline.ts: records who it read and when, and how many were being read at once. */
function stubReader(ms = 5, fail: (provider: string, attempt: number) => boolean = () => false) {
  const reads: string[] = []; let inFlight = 0; let peak = 0;
  // deno-lint-ignore no-explicit-any
  const read = async (row: any) => {
    inFlight++; peak = Math.max(peak, inFlight);
    try {
      await new Promise((r) => setTimeout(r, ms));
      reads.push(row.provider_email_id);
      if (fail(row.provider_email_id, row.attempts)) throw new Error('ZZ DEMO the reader failed on ' + row.provider_email_id);
      return new Response(JSON.stringify({ ok: true, receipt: true }), { status: 200 });
    } finally { inFlight--; }
  };
  return { read, reads, peak: () => peak };
}

Deno.test('a burst of 20 deliveries is answered at once, and every message is read exactly once, two at a time at most', async () => {
  Q = new MemQueue();
  const background: Promise<unknown>[] = [];
  const r = stubReader(20);
  const runs: Record<string, unknown>[] = [];
  useReader({ rpc: Q.rpc, read: r.read, waitUntil: (p) => { background.push(p); }, log: (_s, counts) => { runs.push(counts); return Promise.resolve(); } });
  // a reader hands on through the kick: pg_net's request to ?drain=1 reaches the same handler
  Q.onKick = (n) => { for (let i = 0; i < n; i++) background.push(handler(drainRequest(DB_INTERNAL))); };
  const t0 = Date.now();
  const answers = await Promise.all(Array.from({ length: 20 }, async (_, i) => {
    const s = Date.now(); const res = await handler(await receipt(i + 1)); return { res, ms: Date.now() - s, body: await res.json() };
  }));
  const allAnswered = Date.now() - t0;
  for (const a of answers) { assertEquals(a.res.status, 200); assertEquals(a.body.queued, true); assert(a.ms < 2000, 'answered in ' + a.ms + ' ms'); }
  assert(allAnswered < 2000, 'the whole burst was answered in ' + allAnswered + ' ms');
  assertEquals(Q.rows.length, 20);
  // Resend retries five of them while they wait: each is a duplicate, nothing new is recorded
  for (const n of [1, 5, 9, 13, 20]) {
    const again = await (await handler(await receipt(n))).json();
    assertEquals(again.duplicate, true); assertEquals(again.queued, false);
  }
  assertEquals(Q.rows.length, 20);
  for (let k = 0; k < background.length; k++) await background[k];   // the chain grows while it is awaited
  assertEquals(Q.rows.filter((x) => x.status === 'done').length, 20, JSON.stringify(Q.rows.map((x) => [x.id, x.status])));
  assert(runs.every((c) => Number(c.read) <= 1), 'each message is read in a run of its own');
  assertEquals(runs.filter((c) => c.read === 1).length, 20);
  assertEquals(r.reads.length, 20, 'read ' + r.reads.length + ' times');
  assertEquals(new Set(r.reads).size, 20, 'no message read twice');
  assert(r.peak() <= 2, 'at most two read at once, saw ' + r.peak());
  assert(r.peak() === 2, 'the two reader slots were both used');
  // the receipts carry no thread (order does not matter among them); the seat a dead letter would go to is the accountant
  assert(Q.rows.every((x) => x.thread_key === null && x.owner_seat === 'accountant'));
  useReader(null);
});

Deno.test('a webhook that cannot record the delivery answers 503 (the sender keeps it) and reads nothing', async () => {
  Q = new MemQueue(); Q.acceptDown = true;
  const r = stubReader();
  useReader({ rpc: Q.rpc, read: r.read, waitUntil: () => {}, log: () => Promise.resolve() });
  const res = await handler(await receipt(99));
  assertEquals(res.status, 503);
  assertEquals(r.reads.length, 0);
  useReader(null);
});

Deno.test('the minute kick: refused without the internal credential, 202 with it, and it reads what is due', async () => {
  Q = new MemQueue();
  const background: Promise<unknown>[] = [];
  const r = stubReader();
  useReader({ rpc: Q.rpc, read: r.read, waitUntil: (p) => { background.push(p); }, log: () => Promise.resolve() });
  Q.call('fn_inbound_mail_accept', { p_provider_email_id: 'zz-demo-left', p_svix_id: 'msg_left', p_payload: '{}', p_from: FOUNDER,
    p_to: 'expenses@mail.quotesdone.com', p_thread_key: null, p_owner_seat: 'accountant' });
  const kick = (secret: string) => handler(drainRequest(secret));
  assertEquals((await kick('zz-demo-wrong-credential-0000000000')).status, 403);
  assertEquals(background.length, 0);
  assertEquals((await kick(DB_INTERNAL)).status, 202);
  await Promise.all(background);
  assertEquals(r.reads, ['zz-demo-left']);
  assertEquals(Q.rows[0].status, 'done');
  useReader(null);
});

Deno.test('a reader killed mid-message: its lease runs out, the message is read again after the backoff, once, and the dead reader cannot finish it', async () => {
  Q = new MemQueue();
  Q.call('fn_inbound_mail_accept', { p_provider_email_id: 'zz-demo-crash', p_svix_id: 'msg_crash', p_payload: '{}', p_from: FOUNDER,
    p_to: 'expenses@mail.quotesdone.com', p_thread_key: null, p_owner_seat: 'accountant' });
  // the edge kills a reader after it claimed: no verdict, no renewal
  const claimed = Q.call('fn_inbound_mail_claim', { p_worker: 'zz-killed-reader', p_limit: 1 }).data;
  assertEquals(claimed.length, 1);
  const r = stubReader();
  const deps = { rpc: Q.rpc, read: r.read, now: Q.now, log: () => Promise.resolve() };
  assertEquals((await drainQueue(deps)).read, 0, 'not taken while its lease runs');
  Q.clock += LEASE + 1_000;
  assertEquals((await drainQueue(deps)).read, 0, 'taken back, but waits its backoff');
  assertEquals(Q.rows[0].status, 'queued');
  assert(String(Q.rows[0].last_error).includes('lease ran out'));
  Q.clock += 61_000;
  const t = await drainQueue(deps);
  assertEquals([t.read, t.done], [1, 1]);
  assertEquals(r.reads, ['zz-demo-crash']);
  assertEquals(Q.rows[0].attempts, 2);
  // the killed reader wakes and reports: refused, the verdict stands
  assertEquals(Q.call('fn_inbound_mail_finish', { p_id: 1, p_worker: 'zz-killed-reader', p_ok: false, p_error: 'late' }).data.finished, false);
  assertEquals(Q.rows[0].status, 'done');
});

Deno.test('a pipeline error is a failed attempt read again after 1 minute; a live reader renews its lease while it reads', async () => {
  Q = new MemQueue();
  Q.call('fn_inbound_mail_accept', { p_provider_email_id: 'zz-demo-flaky', p_svix_id: null, p_payload: '{}', p_from: FOUNDER,
    p_to: 'expenses@mail.quotesdone.com', p_thread_key: null, p_owner_seat: 'accountant' });
  const r = stubReader(60, (_p, attempt) => attempt === 1);
  const deps = { rpc: Q.rpc, read: r.read, now: Q.now, renewMs: 15, log: () => Promise.resolve() };
  const t1 = await drainQueue(deps);
  assertEquals([t1.read, t1.retried, t1.done], [1, 1, 0]);
  assertEquals(Q.kicks, [0], 'it handed on once it had read; nothing was due yet');
  assert(Q.touches >= 2, 'renewed ' + Q.touches + ' times during a 60 ms read every 15 ms');
  assert(String(Q.rows[0].last_error).includes('ZZ DEMO the reader failed'));
  assertEquals((await drainQueue(deps)).read, 0, 'not before its backoff');
  Q.clock += 60_000;
  const t2 = await drainQueue(deps);
  assertEquals([t2.read, t2.done], [1, 1]);
  assertEquals(Q.rows[0].status, 'done');
});

Deno.test('a poison message is read five times, then handed to the seat that owns it with the reason, and never again until requeued', async () => {
  Q = new MemQueue();
  Q.call('fn_inbound_mail_accept', { p_provider_email_id: 'zz-demo-poison', p_svix_id: 'msg_poison', p_payload: '{}', p_from: 'buyer@example.invalid',
    p_to: 'supplier@quotesdone.com', p_thread_key: 'buyer@example.invalid>supplier@quotesdone.com', p_owner_seat: 'customer_support' });
  const r = stubReader(1, () => true);
  const deps = { rpc: Q.rpc, read: r.read, now: Q.now, log: () => Promise.resolve() };
  const seen: string[] = [];
  for (let i = 0; i < 8; i++) { await drainQueue(deps); seen.push(Q.rows[0].status); Q.clock += 61 * 60_000; }
  assertEquals(r.reads.length, 5);
  assertEquals(Q.rows[0].status, 'dead');
  assertEquals(Q.deadLetters.length, 1);
  assertEquals(Q.deadLetters[0].seat, 'customer_support');
  assert(Q.deadLetters[0].reason.includes('attempt 5: ZZ DEMO the reader failed on zz-demo-poison'), Q.deadLetters[0].reason);
  assertEquals(seen.slice(0, 4), ['queued', 'queued', 'queued', 'queued']);
  assertEquals(Q.call('fn_inbound_mail_requeue', { p_id: 1 }).data.requeued, true);
  assertEquals((await drainQueue({ ...deps, read: stubReader().read })).done, 1);
});

Deno.test('one sender\'s mail to one mailbox is read in the order it came; receipts and other senders are not held behind it', () => {
  Q = new MemQueue();
  const supplier = (n: number, from = 'tiles@example.invalid') => Q.call('fn_inbound_mail_accept', { p_provider_email_id: 'zz-demo-q' + n,
    p_svix_id: null, p_payload: '{}', p_from: from, p_to: 'supplier@quotesdone.com', p_thread_key: from + '>supplier@quotesdone.com', p_owner_seat: 'customer_support' });
  supplier(1); supplier(2); supplier(3, 'paint@example.invalid');
  const first = Q.call('fn_inbound_mail_claim', { p_worker: 'a', p_limit: 5 }).data.map((x: Row) => x.provider_email_id);
  assertEquals(first, ['zz-demo-q1', 'zz-demo-q3'], 'his correction waits for his quotation; another supplier is not held');
  assertEquals(Q.call('fn_inbound_mail_claim', { p_worker: 'b', p_limit: 5 }).data.length, 0, 'both slots are taken');
  Q.call('fn_inbound_mail_finish', { p_id: 1, p_worker: 'a', p_ok: true });
  assertEquals(Q.call('fn_inbound_mail_claim', { p_worker: 'b', p_limit: 5 }).data.map((x: Row) => x.provider_email_id), ['zz-demo-q2']);
});

Deno.test('the queue key and envelope are read off the verified payload: the email id read_mail reads, else the Svix id', () => {
  const resend = envelopeOf(JSON.stringify({ type: 'email.received', data: { email_id: 'zz-e1', from: 'A <a@example.invalid>', to: ['Expenses@mail.quotesdone.com'], subject: 's' } }), 'msg_1');
  assertEquals([resend.providerEmailId, resend.threadKey, resend.ownerSeat], ['zz-e1', null, 'accountant']);
  const m365 = envelopeOf(JSON.stringify({ type: 'email.received', data: { email_id: 'm365:AAMkZZ', from: 'b@example.invalid', to: 'supplier@quotesdone.com', subject: 'Re: quote' } }), 'msg_2');
  assertEquals([m365.providerEmailId, m365.threadKey, m365.ownerSeat], ['m365:AAMkZZ', 'b@example.invalid>supplier@quotesdone.com', 'customer_support']);
  assertEquals(envelopeOf('not json', 'msg_3').providerEmailId, 'svix:msg_3');
  assertEquals(envelopeOf('not json', '').providerEmailId, '');
});

Deno.test('the reader hands the real pipeline the body as verified: a message already on file (a re-read after a crash) is answered at once', async () => {
  restCalls.length = 0;
  const raw = JSON.stringify({ type: 'email.received', data: { email_id: 'zz-demo-on-file', from: FOUNDER, to: ['expenses@mail.quotesdone.com'], subject: 'Fwd: receipt', text: 'ZZ DEMO a forwarded receipt, already booked' } });
  const res = await readQueued({ id: 7, provider_email_id: 'zz-demo-on-file', svix_id: 'msg_zz_on_file', payload: raw, attempts: 2, max_attempts: 5 });
  const out = await res.json();
  assertEquals([res.status, out.duplicate], [200, true]);
  assert(restCalls.includes('/rest/v1/inbound_messages'), 'read_mail looked the id up');
  assert(!restCalls.some((c) => /expense_entries|storage|ai_gateway|fn_receipt_hand_to_bookkeeper/.test(c)), 'nothing was read or booked again: ' + restCalls.join(' '));
});
