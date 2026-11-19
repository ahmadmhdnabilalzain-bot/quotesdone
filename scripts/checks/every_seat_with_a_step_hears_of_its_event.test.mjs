// EVERY SEAT WITH A STEP HEARS OF ITS EVENT (ceo, 19 Nov 2026; founder ruling 1685). Guards
// scripts/sql/every_seat_with_a_step_hears_of_its_event.sql. Its behaviour is proved by that file's probe (rehearsed on the local
// database: PROBE OK, and five mutants each caught: no dedupe, canary counted, soft bounce counted, the CEO not told, a routine
// open to anon). This fails when the shape that makes it true is taken away.
//   node --test scripts/checks/every_seat_with_a_step_hears_of_its_event.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL = readFileSync(join(ROOT, 'scripts/sql/every_seat_with_a_step_hears_of_its_event.sql'), 'utf8');
const fn = (name) => {
  const at = SQL.search(new RegExp(`create or replace function public\\.${name}\\(`, 'i'));
  assert.ok(at >= 0, `${name} is defined`);
  const tag = SQL.slice(at).match(/as (\$\w*\$)/i)[1];
  const body = SQL.indexOf(tag, at) + tag.length;
  return SQL.slice(at, SQL.indexOf(tag, body));
};

// the seats that hear each event by digest, and its one owner (section 5 of the file)
const ROUTES = {
  'mail.bounced': { digest: ['ceo', 'it_engineer', 'marketing'], owner: 'it_engineer' },
  'mail.complained': { digest: ['ceo', 'it_engineer', 'marketing'], owner: 'it_engineer' },
  'invite.sent': { digest: ['ceo', 'marketing'], owner: 'marketing' },
  'request.completed': { digest: ['ceo', 'customer_support', 'marketing', 'sales_engineer'], owner: 'sales_engineer' },
  'rating.landed': { digest: ['ceo', 'customer_support', 'marketing'], owner: 'sales_engineer' },
  'customer.complaint': { digest: ['ceo', 'customer_support', 'sales_engineer'], owner: 'customer_support' },
};
const SEATS = ['accountant', 'ceo', 'customer_support', 'it_engineer', 'marketing', 'sales_engineer'];
const rows = [...SQL.matchAll(/^\s*\('(\w+)',\s*'([a-z_.]+)',\s*'(digest|none|handover)',\s*(true|false),/gm)]
  .map((m) => ({ seat: m[1], ev: m[2], delivery: m[3], owns: m[4] === 'true' }));

test('an event emitted once: fn_emit_once looks for its key under an advisory lock before it calls fn_emit, and writes the key', () => {
  const f = fn('fn_emit_once');
  const lock = f.indexOf('pg_advisory_xact_lock(');
  const seen = f.indexOf('where e.dedupe_key = p_dedupe_key) then return null');
  const emit = f.indexOf('public.fn_emit(p_event_type');
  assert.ok(lock > 0 && seen > lock && emit > seen, 'lock, then the key, then fn_emit');
  assert.match(f, /update public\.company_event set dedupe_key = p_dedupe_key where id = v_id/);
});

test('a bounce is a hard bounce of an e-mail to a person: canaries, soft bounces and other channels are not events', () => {
  const f = fn('fn_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint');
  assert.match(f, /coalesce\(new\.channel, 'email'\) = 'email' and coalesce\(new\.to_role, ''\) <> 'system'/);
  assert.match(f, /coalesce\(new\.type, ''\) <> 'delivery_feedback_canary'/);
  assert.match(f, /new\.provider_error_code !~\* '\^bounce:\(transient\|soft\)'/);
  assert.match(f, /v_type := 'mail\.bounced'/);
  assert.match(f, /v_type := 'mail\.complained'/);
  assert.match(f, /'invite\.sent:notification:' \|\| new\.id, 'invite\.sent'/);
});

test('a completed request and a landed rating are each emitted once, keyed by their own row', () => {
  assert.match(fn('fn_inquiries_a_completed_request_is_a_company_event'), /'request\.completed:inquiry:' \|\| new\.id, 'request\.completed'/);
  assert.match(fn('fn_reviews_a_rating_is_a_company_event'), /'rating\.landed:review:' \|\| new\.id, 'rating\.landed'/);
  assert.match(SQL, /create or replace trigger z34_a_completed_request_is_a_company_event\s+after update of status on public\.inquiries\s+for each row when \(new\.status = 'completed' and old\.status is distinct from 'completed'\)/);
  assert.match(SQL, /create or replace trigger t61_a_rating_is_a_company_event\s+after insert on public\.reviews/);
});

test('every seat that has a step hears its event by digest, one owner per event, a row for every seat, nothing handed over or sent', () => {
  for (const [ev, want] of Object.entries(ROUTES)) {
    const mine = rows.filter((r) => r.ev === ev);
    assert.deepEqual(mine.map((r) => r.seat).sort(), SEATS, `${ev}: one row per seat, and only the six seats`);
    assert.deepEqual(mine.filter((r) => r.delivery === 'digest').map((r) => r.seat).sort(), want.digest, `${ev}: digest seats`);
    assert.deepEqual(mine.filter((r) => r.owns).map((r) => r.seat), [want.owner], `${ev}: owner`);
  }
  assert.ok(!rows.some((r) => r.delivery === 'handover'), 'nothing is handed over by this file');
});

test('a paid reveal gets no third event: the CEO and customer support already hear payment.received, and the probe proves it', () => {
  assert.doesNotMatch(SQL, /fn_emit(_once)?\('reveal\.paid/);
  assert.match(SQL, /where event_type = 'payment\.received' and active and delivery = 'digest' and agent_key in \('ceo', 'customer_support'\)/);
});

test('every new routine pins its search_path and is revoked from callers by its exact signature', () => {
  for (const [name, sig] of [['fn_emit_once', 'text, text, text, text, text, jsonb'],
    ['fn_notifications_the_seats_hear_a_send_a_bounce_or_a_complaint', ''],
    ['fn_inquiries_a_completed_request_is_a_company_event', ''], ['fn_reviews_a_rating_is_a_company_event', '']]) {
    assert.match(fn(name), /set search_path to 'public', 'pg_temp'/, `${name} search_path`);
    assert.ok(SQL.includes(`revoke execute on function public.${name}(${sig}) from public, anon, authenticated;`), `${name} revoke`);
  }
  assert.match(SQL, /^set local lock_timeout = '1500ms';/m);
});

test('the probe rolls back its own rows and returns one verdict row', () => {
  assert.match(SQL, /raise exception 'CHK<<%>>', case when v_fail = '' then 'OK' else v_fail end;/);
  assert.match(SQL, /select current_setting\('qd\.every_seat_hears_verdict', true\) as verdict;\s*$/);
  assert.match(SQL, /'ZZ DEMO Every Seat Probe Customer', 'every-seat-' \|\| v_tag \|\| '@example\.invalid'/);
});
