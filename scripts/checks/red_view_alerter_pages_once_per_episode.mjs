// THE RED VIEW ALERTER PAGES ONCE PER EPISODE — proved in an aborted transaction (4 Sep 2026).
//
// One transaction, five passes of fn_red_view_alert(p_boards := false), then RAISE so nothing survives:
//   pass 0  warm-up: opens every red that stands today (crons, health, connectivity, departments,
//           watcher) and queues its one post — so the synthetic red below is measured on its own
//   pass 1  a synthetic failing health_checks row (target 'ZZ DEMO probe page')  → exactly 1 new
//           episode, exactly 1 net.http_request_queue row whose body names only that key
//   pass 2  the same target reports ok=true                                    → the episode resolves, 0 posts
//   pass 3  the target fails again                                             → a NEW episode (new id), 1 post
//   pass 4  nothing changed                                                    → 0 opened, 0 posts (no re-page)
// The posts are rows in net.http_request_queue; the RAISE rolls them back, so the founder is never
// paged by this probe. The counts come out in the exception message.
//
//   node scripts/checks/red_view_alerter_pages_once_per_episode.mjs
import { sql } from '../phase_b/lib/db.mjs';

const probe = `
do $probe$
declare
  q0 bigint; r0 jsonb; r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb;
  e1 record; e3 record; posts1 int; posts2 int; posts3 int; posts4 int; body1 text; qa bigint; qb bigint; qc bigint; qd bigint;
  in_rehearsal boolean;
begin
  select coalesce(max(id),0) into q0 from net.http_request_queue;
  select public.fn_rehearsal_window_covers(clock_timestamp()) into in_rehearsal;
  -- Another agent's declared rehearsal would (correctly) hold every post pending. Close every open
  -- window LOCALLY, inside this transaction only — the RAISE below puts them back exactly as they were —
  -- so the post path is exercised here without touching anyone's window for real.
  update public.rehearsal_window set ended_at = clock_timestamp() - interval '1 second'
   where ended_at is null or ended_at > clock_timestamp();

  r0 := public.fn_red_view_alert(false);
  select coalesce(max(id),0) into qa from net.http_request_queue;

  -- created_at is set explicitly: now() is frozen for the whole transaction, and three rows with one
  -- timestamp have no "latest"
  insert into public.health_checks (check_kind, target, ok, status_code, latency_ms, detail, created_at)
  values ('http', 'ZZ DEMO probe page', false, 503, 1, 'red_view probe — synthetic outage', clock_timestamp());
  r1 := public.fn_red_view_alert(false);
  select * into e1 from public.red_episode where check_key = 'health:http:ZZ DEMO probe page' and resolved_at is null;
  select count(*) into posts1 from net.http_request_queue where id > qa;
  -- the payload carries the internal credential; it is REMOVED before anything leaves the database
  select (convert_from(body,'utf8')::jsonb - '__secret')::text into body1 from net.http_request_queue where id > qa order by id desc limit 1;
  select coalesce(max(id),0) into qb from net.http_request_queue;

  insert into public.health_checks (check_kind, target, ok, status_code, latency_ms, detail, created_at)
  values ('http', 'ZZ DEMO probe page', true, 200, 1, 'red_view probe — recovered', clock_timestamp());
  r2 := public.fn_red_view_alert(false);
  select count(*) into posts2 from net.http_request_queue where id > qb;
  select coalesce(max(id),0) into qc from net.http_request_queue;

  insert into public.health_checks (check_kind, target, ok, status_code, latency_ms, detail, created_at)
  values ('http', 'ZZ DEMO probe page', false, 502, 1, 'red_view probe — second outage', clock_timestamp());
  r3 := public.fn_red_view_alert(false);
  select * into e3 from public.red_episode where check_key = 'health:http:ZZ DEMO probe page' and resolved_at is null;
  select count(*) into posts3 from net.http_request_queue where id > qc;
  select coalesce(max(id),0) into qd from net.http_request_queue;

  r4 := public.fn_red_view_alert(false);
  select count(*) into posts4 from net.http_request_queue where id > qd;

  -- kept short on purpose: the transport returns the first 2000 characters of the error
  raise exception 'PROBE %', jsonb_build_object(
    'in_rehearsal_window', in_rehearsal,
    'pass0', jsonb_build_object('opened', r0->'opened', 'paged', r0->'paged', 'red_now', r0->'red_now'),
    'pass1', jsonb_build_object('opened', r1->'opened', 'paged', r1->'paged', 'level', r1->'level', 'episode_id', e1.id,
                                'latency_ms', round(extract(epoch from (e1.alerted_at - e1.opened_at))*1000),
                                'paged_by', e1.paged_by, 'dedupe_key', e1.alert_dedupe_key, 'posts', posts1,
                                'post_body', left(body1, 420)),
    'pass2', jsonb_build_object('resolved', r2->'resolved', 'paged', r2->'paged', 'posts', posts2,
                                'episode_resolved', (select resolved_at is not null from public.red_episode where id = e1.id)),
    'pass3', jsonb_build_object('opened', r3->'opened', 'paged', r3->'paged', 'episode_id', e3.id, 'is_new_episode', e3.id <> e1.id, 'posts', posts3,
                                'dedupe_key', e3.alert_dedupe_key),
    'pass4', jsonb_build_object('opened', r4->'opened', 'paged', r4->'paged', 'posts', posts4));
end $probe$;`;

let msg;
try { await sql(probe); }
catch (e) { msg = String(e.message || e); }
if (!msg) { console.error('the probe committed — it must always RAISE'); process.exit(1); }
// the management API wraps the RAISE text in a JSON error body; unwrap it before reading the payload
let text = msg;
try { text = JSON.parse(msg.slice(msg.indexOf('{'))).message; } catch { /* already plain */ }
const m = text.match(/PROBE (\{[\s\S]*\})\s*(?:\nCONTEXT|$)/);
if (!m) { console.error(text); process.exit(1); }
const out = JSON.parse(m[1]);
console.log(JSON.stringify(out, null, 2));

const body1 = String(out.pass1.post_body || '');
const body1keys = (body1.match(/(board|cron|health|connectivity|department|watcher):[^ \\n]+/g) || []);
const checks = [
  ['pass1 opened exactly one episode',        out.pass1.opened === 1],
  ['pass1 queued exactly one post',           out.pass1.posts === 1],
  ['pass1 post names the synthetic key only', body1.includes('ZZ DEMO probe page') && body1keys.length === 1],
  ['pass1 post carries no secret',            !body1.includes('__secret')],
  ['pass1 episode is paged_by red_view',      out.pass1.paged_by === 'red_view'],
  ['pass2 resolved the episode, 0 posts',     out.pass2.episode_resolved === true && out.pass2.posts === 0],
  ['pass3 opened a NEW episode, 1 post',      out.pass3.is_new_episode === true && out.pass3.posts === 1],
  ['pass3 dedupe key differs from pass1',     out.pass3.dedupe_key !== out.pass1.dedupe_key],
  ['pass4 opened nothing and posted nothing', out.pass4.opened === 0 && out.pass4.posts === 0],
];
let bad = 0;
for (const [name, ok] of checks) { console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}`); if (!ok) bad++; }
if (out.in_rehearsal_window) console.log('note: a rehearsal_window was open when the probe started; it was closed inside the probe transaction only (rolled back), so the posts above were exercised and never sent');
process.exit(bad ? 1 : 0);
