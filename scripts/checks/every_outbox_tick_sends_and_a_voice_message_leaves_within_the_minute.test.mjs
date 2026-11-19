// EVERY HEARTBEAT TICK DRAINS THE OUTBOX, AND A MESSAGE CUSTOMER SUPPORT'S VOICE WRITES LEAVES WITHIN THE MINUTE
// (it_engineer, 19 Nov 2026). Static: it reads the two SQL files and the code they must agree with; nothing here connects.
//
// MEASURED (production, read-only, 19 Nov 2026):
//   * duty:heartbeat:outbox, seen 380 times: "Rate limit exceeded for trace <the tick's request id>". Over 96 ticks the outbox
//     was drained on 47 of 48 ticks with at most 2 self-calls of resilience_ping and on 9 of 48 with 3 or more (the :00 and :30
//     ticks). The kick of a detached run now goes through fn_resilience_detached_kick (pg_net, a request chain of its own).
//   * notification 150035 (duty_support_lost_request, the voice's first message) waited 30 minutes: the person-mail kick's
//     allow-list named none of the voice's types, and the voice writes after the tick's outbox step.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (p) => readFileSync(root + p, 'utf8');
const noComments = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const KICK = noComments(read('scripts/sql/the_heartbeat_kicks_its_detached_runs_through_the_database_so_every_tick_drains_the_outbox.sql'));
const KINDS = noComments(read('scripts/sql/a_message_customer_support_writes_is_sent_like_any_person_mail.sql'));

test('the detached kick posts through pg_net to resilience_ping, authenticated, in the database region', () => {
  assert.match(KICK, /create or replace function public\.fn_resilience_detached_kick\(p_name text\)\s*returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'/);
  assert.match(KICK, /net\.http_post\('https:\/\/' \|\| v_ref \|\| '\.supabase\.co\/functions\/v1\/resilience_ping\?forceFunctionRegion=ap-southeast-1'/);
  assert.match(KICK, /'x-qd-internal', v_secret/, 'resilience_ping\'s tickCaller reads the internal credential from x-qd-internal');
  assert.match(read('supabase/functions/resilience_ping/index.ts'), /req\.headers\.get\('x-qd-internal'\)[\s\S]{0,200}requireInternal\(admin, internal, 'resilience_ping'/);
  assert.match(KICK, /set scope = scope \|\| array\['resilience_ping'\][\s\S]*context = 'db\.internal'/, 'db.internal may call resilience_ping');
  assert.match(KICK, /revoke execute on function public\.fn_resilience_detached_kick\(text\) from public, anon, authenticated;/);
  assert.match(KICK, /grant execute on function public\.fn_resilience_detached_kick\(text\) to service_role;/);
  assert.match(KICK, /alter table public\.resilience_detached_kick enable row level security;[\s\S]*create policy resilience_detached_kick_service_role_only/);
});

test('a kicked run that never started is a finding: the next kick reads the previous answer and says ok:false', () => {
  assert.match(KICK, /from net\._http_response r where r\.id = v_prev\.request_id/);
  assert.match(KICK, /v_status not between 200 and 299/);
  assert.match(KICK, /has no answer recorded by pg_net/);
  assert.match(KICK, /jsonb_build_object\('ok', v_bad is null, 'started', true/);
  assert.match(KICK, /'ok', false, 'started', false, 'error', 'no db\.internal credential/);
  // the probe reads, never posts
  const probe = KICK.slice(KICK.lastIndexOf('with f as'));
  assert.ok(!/fn_resilience_detached_kick\(\s*(?!text\))\S/.test(probe), 'the probe calls the kick (it would post)');
});

test('the person-mail allow-list carries every type the voice has written, in the form send_outbox accepts', () => {
  assert.match(KINDS, /create or replace function public\.fn_outbox_person_kinds\(\)\s*returns text\[\] language sql stable security definer set search_path to 'public', 'pg_temp'/);
  assert.match(KINDS, /'duty_' \|\| replace\(o\.stage, '\.', '_'\)[\s\S]*from public\.customer_support_voice_owed o[\s\S]*o\.written_at > now\(\) - interval '7 days'/);
  // the voice's type rule is fn_customer_support_duty_send's: 'duty_' || replace(p_stage, '.', '_')
  assert.ok(read('supabase/schema/full_schema/04_functions_fn_c.sql').includes("'duty_' || replace(p_stage, '.', '_')"),
    'fn_customer_support_duty_send no longer names its type this way');
  // the same pattern and cap as send_outbox's body.kinds reader, or the kick would ask for a kind send_outbox drops
  const channels = read('supabase/functions/send_outbox/channels.ts');
  assert.match(channels, /\/\^\[a-z0-9_\]\{1,64\}\$\/\.test\(x\)\)\.slice\(0, 20\)/);
  assert.match(KINDS, /v\.k ~ '\^\[a-z0-9_\]\{1,64\}\$'/);
  assert.match(KINDS, /'\{\}'::text\[\]\)\)\[1:20\]/);
  // the seven fixed kinds are the live list, unchanged
  for (const k of ['registration_received', 'company_name_from_licence', 'supplier_approved', 'supplier_mailbox_reply', 'new_message', 'invoice_ready', 'reveal_receipt']) assert.ok(KINDS.includes(`'${k}'`), k);
  assert.match(KINDS, /revoke execute on function public\.fn_outbox_person_kinds\(\) from public, anon, authenticated;/);
});
