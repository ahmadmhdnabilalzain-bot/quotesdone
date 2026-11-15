// AN INBOUND BURST IS ACCEPTED AT ONCE AND READ IN TURN (it_engineer, 15 Nov 2026). Offline: reads the repository only.
//
// 15 Nov 2026 18:40-18:54 UTC: 18 receipts forwarded in 3 minutes were each read inside their own resend_inbound request; most
// answered 546 WORKER_RESOURCE_LIMIT, some 504 after 150 s, and 5 of 18 reached inbound_messages. This fails if the webhook
// goes back to reading inside the request, if the queue loses its key, its reader cap, its claim lock, its thread order, its
// lease, its backoff or its dead letter, if a routine loses its revoke or its pinned search_path, if the file starts taking a
// strong lock on a table people use, or if it is neither pending with its probe nor on the MANIFEST.
// The behaviour is proved by supabase/functions/resend_inbound/an_inbound_burst_is_accepted_at_once_and_read_in_turn.test.ts
// (the handler and the reader) and, on a database, by the rolled-back probe beside the SQL file.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { catalogueFrom, stallsLiveUsers } from '../lib/replay_guard.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'an_inbound_burst_is_accepted_at_once_and_read_in_turn';
const SQL = read(`scripts/sql/${NAME}.sql`);
const FN = 'supabase/functions/resend_inbound';

test('the webhook verifies, records and answers; the reading runs after the answer', () => {
  const idx = read(`${FN}/index.ts`);
  const handler = idx.slice(idx.indexOf('export const handler'));
  const order = ['authenticate({ req })', 'acceptDelivery(rpc, c1.raw', "J({ error: 'inbound queue unavailable' }, 503)", 'readInBackground(J({ ok: true, queued: !acc.duplicate, duplicate: acc.duplicate'];
  let at = -1;
  for (const s of order) { const i = handler.indexOf(s); assert.ok(i > at, `${s} is missing or out of order`); at = i; }
  assert.doesNotMatch(handler, /readMail\(|receipts\(|supplierDocs\(/, 'no step of the reading runs inside the webhook request');
  assert.match(idx, /ackThenWork\(ack, \(\) => drainQueue\(\{ rpc, read: readQueued, log: logRun, \.\.\.readerOver \}\)/);
  // the minute kick is internal only
  assert.match(handler, /searchParams\.get\('drain'\) === '1'[\s\S]{0,200}requireInternal\(admin, body\?\.__secret, 'resend_inbound'\)/);
  // the steps themselves are unchanged and in their order, in pipeline.ts
  const pipe = read(`${FN}/pipeline.ts`);
  const steps = ['readMail(', 'marketingReplies(', 'expenseGate(', 'bounceUnsubscribe(', 'receipts(', 'supplierDocs('];
  at = -1; for (const s of steps) { const i = pipe.indexOf(s, at + 1); assert.ok(i > at, s); at = i; }
  assert.doesNotMatch(pipe, /catch/, 'a failure in the reading reaches the reader as a failed attempt');
});

test('the queue: one row per provider id, the reader cap under one lock, the thread order, the lease, the backoff, the dead letter', () => {
  assert.match(SQL, /create unique index if not exists inbound_mail_queue_provider_email_id_key on public\.inbound_mail_queue \(provider_email_id\)/);
  assert.match(SQL, /on conflict \(provider_email_id\) do nothing/);
  assert.match(SQL, /perform pg_advisory_xact_lock\(hashtext\('public\.inbound_mail_queue claim'\)\);/);
  assert.match(SQL, /public\.fn_inbound_mail_readers\(\) - v_live/);
  assert.match(SQL, /returns integer language sql immutable security definer set search_path to 'public', 'pg_temp' as \$fn\$ select 2 \$fn\$/);
  assert.match(SQL, /e\.thread_key = c\.thread_key and e\.id < c\.id and e\.status in \('queued', 'reading'\)/);
  assert.match(SQL, /for update skip locked/);
  assert.equal((SQL.match(/lease_until = now\(\) \+ interval '150 seconds'/g) ?? []).length, 2, 'claim and touch hold the same lease');
  assert.match(SQL, /interval '1 minute'[\s\S]{0,80}interval '5 minutes'[\s\S]{0,80}interval '15 minutes'[\s\S]{0,60}interval '60 minutes'/);
  assert.match(SQL, /max_attempts      integer not null default 5/);
  assert.match(SQL, /public\.fn_seat_handoff\('it_engineer', r\.owner_seat, 'it\.finding', 'inbound_mail_queue', r\.id::text/);
  assert.match(SQL, /r\.status <> 'reading' or r\.claimed_by is distinct from p_worker/, 'a reader whose lease was taken back cannot overwrite the verdict');
  // the reader renews well inside the lease; its budget leaves the edge's wall clock for the message it started
  const q = read(`${FN}/lib/queue.ts`);
  assert.match(q, /export const LEASE_RENEW_MS = 30_000;/);
  assert.match(q, /export const READ_BUDGET_MS = 45_000;/);
  assert.match(q, /rpc\('fn_inbound_mail_claim', \{ p_worker: worker, p_limit: 1 \}\)/, 'one message at a time per reader');
  assert.match(q, /export const READS_PER_RUN = 1;/, 'one message per invocation: the edge limits CPU per invocation');
  assert.match(q, /if \(tally\.read\) \{\s+try \{ const \{ data \} = await deps\.rpc\('fn_inbound_mail_kick', \{\}\)/, 'a reader hands on to the next');
  assert.match(SQL, /grant execute on function public\.fn_inbound_mail_kick\(\) to service_role;/);
  // the receipts' idempotency key is untouched
  assert.match(read(`${FN}/steps/receipts.ts`), /const msgKey = emailId \? \('resend:' \+ emailId\)/);
});

test('the minute kick: scheduled, internal credential in scope, one request per free slot', () => {
  assert.match(SQL, /cron\.schedule\('inbound_mail_drain', '\* \* \* \* \*'/);
  assert.match(SQL, /update public\.internal_credential set scope = scope \|\| array\['resend_inbound'\]/);
  assert.match(SQL, /\/functions\/v1\/resend_inbound\?drain=1/);
  assert.match(SQL, /v_n := least\(v_due, greatest\(0, public\.fn_inbound_mail_readers\(\) - v_live\)\)/);
  assert.match(SQL, /insert into public\.cron_registry/);
  assert.match(SQL, /\('cron_job', 'inbound_mail_drain', 'it_engineer'/);
});

test('every routine is revoked and pinned; the table is service-role only; no strong lock on a table people use; pending with its probe', () => {
  const routines = [...SQL.matchAll(/create or replace function public\.(fn_inbound_mail_\w+)\(/g)].map((m) => m[1]);
  assert.equal(routines.length, 9);
  for (const r of routines) assert.match(SQL, new RegExp(`revoke execute on function public\\.${r}\\([^)]*\\) from public, anon, authenticated;`), r);
  assert.equal((SQL.match(/security definer set search_path to 'public', 'pg_temp'|security definer\nset search_path to 'public', 'pg_temp'/g) ?? []).length, 9);
  assert.match(SQL, /create policy inbound_mail_queue_service_role_only on public\.inbound_mail_queue\s+as permissive for all to public using \(false\) with check \(false\);/);
  assert.match(SQL, /revoke all on public\.inbound_mail_queue from anon, authenticated;/);
  const prod = catalogueFrom({ relations: ['public.internal_credential', 'public.cron_registry', 'public.writer_seat', 'public.agent_actions',
    'public.app_secrets', 'public.inbound_messages', 'cron.job'].join(',') });
  assert.deepEqual(stallsLiveUsers(SQL, prod), []);
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim());
  const pending = (() => { try { return read(`scripts/sql/pending/${NAME}.txt`).trim(); } catch { return ''; } })();
  assert.ok(manifest.includes(`scripts/sql/${NAME}.sql`) !== Boolean(pending), 'exactly one of: a MANIFEST line, or a pending note');
  assert.match(read(`scripts/sql/${NAME}_probe.sql`), /CHK<<PROBE OK: 20 of a burst recorded once and read once two at a time/);
});
