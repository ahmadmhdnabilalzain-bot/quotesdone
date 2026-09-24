// EACH CHANNEL OF A POST SAYS WHAT THE PLATFORM ACTUALLY DID (24 Sep 2026, marketing + it_engineer).
//
// The cause: a post was 'published' the moment Postiz accepted POST /posts, so a channel that failed or
// half-published (YouTube: thumbnail not set) read as done and nobody was told. The behaviour is proved against
// recorded Postiz answers in supabase/functions/_shared/marketing_channel_results.test.ts; this check holds what
// those tests cannot see.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the table loses RLS / its policy / its revoke, a routine loses its pinned search_path or revoke,
//     the post outcome rule changes shape, the re-check window stops being 48 hours, the beat stops reading
//     back or stops settling partial/failed channels as it_engineer findings through fn_it_duty_settle, the
//     read-back writes to Postiz or calls a model, the table leaves the daily export, or the file carries both
//     (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (the file replayed while pending, a ZZ DEMO post with is_demo set,
//     nothing commits, no finding filed, no notification): all-ok is published, a YouTube thumbnail complaint is
//     partial, one channel error is partial, all errors are failed, a second record of the same channel is still
//     one row, and a demo post is never due for a re-check.
//
//   node --test scripts/checks/each_channel_of_a_post_says_what_the_platform_actually_did.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/each_channel_of_a_post_says_what_the_platform_actually_did.sql';
const LIB = 'supabase/functions/_shared/marketing_channel_results.ts';
const FN = 'supabase/functions/marketing_channels/index.ts';
const sqlCode = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const tsCode = (t) => t.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('static SQL: RLS + policy + revoke, pinned and revoked routines, the rule, the 48-hour schedule, the export', () => {
  const src = sqlCode(read(FILE));
  assert.match(src, /alter table public\.marketing_post_channel_result enable row level security/);
  assert.match(src, /create policy marketing_post_channel_result_service_role_only[\s\S]{0,160}using \(false\) with check \(false\)/);
  assert.match(src, /revoke all on public\.marketing_post_channel_result from anon, authenticated/);
  for (const [fn, sig] of [['fn_marketing_post_channel_record', 'bigint, jsonb'], ['fn_marketing_channel_results_due', 'integer']]) {
    assert.match(src, new RegExp(`function public\\.${fn}\\([^)]*\\)[\\s\\S]{0,260}security definer\\s+set search_path to 'public', 'pg_temp'`), fn + ' is not pinned');
    assert.match(src, new RegExp(`revoke execute on function public\\.${fn}\\(${sig}\\) from public, anon, authenticated;`), fn + ' is not revoked');
  }
  assert.match(src, /state\s+text not null check \(state in \('pending', 'published', 'partial', 'failed'\)\)/);
  // the post outcome: pending while any pending, published only if all published, failed if none reached, else partial
  assert.match(src, /when 'pending' = any \(v_states\) then 'pending'\s+when v_states <@ array\['published'\] then 'published'\s+when not \(v_states && array\['published', 'partial'\]\) then 'failed'\s+else 'partial' end/);
  assert.match(src, /p\.published_at > now\(\) - interval '48 hours'/, 'the re-check no longer covers the 48 hours Postiz reports in');
  assert.match(src, /where p\.status = 'published' and not p\.is_demo/, 'a demo post must never be re-read from Postiz');
  assert.doesNotMatch(src, /cron\.schedule/, 'the re-check runs on the existing beat: no new cron job');
  assert.match(src, /\('marketing_post_channel_result','marketing'\)/, 'the new table is not in the daily export');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('static runtime: the beat reads back every channel, stores it, and settles partial/failed as it_engineer findings', () => {
  const fn = tsCode(read(FN));
  assert.match(fn, /const channels = spent \? \{ ok: true, deferred: 'a post was sent this beat' \} : await channelResults\(e\);/, 'the duties beat does not read channel results');
  assert.match(fn, /rpc\('fn_marketing_channel_results_due'/);
  assert.match(fn, /rpc\('fn_marketing_post_channel_record', \{ p_post_id: p\.post_id, p_channels: rows \}\)/);
  assert.match(fn, /\.in\('state', \['partial', 'failed'\]\)/, 'the settle must be built from every stored partial/failed row, or a finding closes on a beat that did not look');
  assert.match(fn, /rpc\('fn_it_duty_settle', \{ p_duty: 'postiz_channel_result', p_items: items \}\)/);
  assert.match(fn, /if \(listed\.ok && notes\.ok\) \{/, 'an unreadable Postiz must store nothing');
  const lib = tsCode(read(LIB));
  assert.doesNotMatch(lib, /method:\s*'(POST|PUT|PATCH|DELETE)'/, 'reading results back must never write to Postiz');
  assert.doesNotMatch(lib + fn.slice(fn.indexOf('async function channelResults(')), /think\(|fn_reason_hold|openrouter|makeLlm/i, 'the read-back is deterministic code, never a model');
  assert.match(lib, /item: `post:\$\{r\.post_id\}:\$\{r\.channel\}`/, 'one finding key per post-channel');
  assert.match(lib, /owner_seat: 'it_engineer'/, 'the finding belongs to the it_engineer seat');
  assert.match(lib, /export const RECHECK_HOURS = 48;/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: the database derives the post outcome from its channels, one row per channel', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending(FILE) ? read(FILE) : '';
  let o;
  try { await sql(replay + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.all_ok, 'published');
  assert.equal(o.thumbnail, 'partial', 'a YouTube thumbnail complaint must make the post partial');
  assert.equal(o.one_error, 'partial');
  assert.equal(o.all_error, 'failed');
  assert.equal(o.rows, 2, 'recording the same channels again must not add rows');
  assert.equal(o.column, 'failed', 'marketing_post.channel_outcome was not written');
  assert.equal(o.demo_due, 0, 'a ZZ DEMO post was due for a Postiz read-back');
});

const PROBE = String.raw`
do $$ declare o jsonb := '{}'; v bigint;
begin
  insert into marketing_post (ingest_key, ingested_by, title, text_en, channels, status, is_demo)
    values ('zz-demo-channel-results-' || substr(md5(random()::text), 1, 8), 'claude', 'ZZ DEMO channel results', 'ZZ DEMO channel results probe',
            array['youtube', 'instagram'], 'draft', true)
    returning id into v;
  o := o || jsonb_build_object('all_ok', fn_marketing_post_channel_record(v, '[{"channel":"youtube","state":"published","release_url":"https://www.youtube.com/watch?v=ZZdemo"},{"channel":"instagram","state":"published"}]')->>'outcome');
  o := o || jsonb_build_object('thumbnail', fn_marketing_post_channel_record(v, '[{"channel":"youtube","state":"partial","postiz_state":"ERROR","platform_message":"An error occurred while posting on youtube: thumbnail not set"},{"channel":"instagram","state":"published"}]')->>'outcome');
  o := o || jsonb_build_object('one_error', fn_marketing_post_channel_record(v, '[{"channel":"youtube","state":"published"},{"channel":"instagram","state":"failed","platform_message":"An error occurred while posting on instagram-standalone: Media upload failed"}]')->>'outcome');
  o := o || jsonb_build_object('all_error', fn_marketing_post_channel_record(v, '[{"channel":"youtube","state":"failed","platform_message":"x"},{"channel":"instagram","state":"failed","platform_message":"y"}]')->>'outcome');
  o := o || jsonb_build_object('rows', (select count(*) from marketing_post_channel_result where post_id = v));
  o := o || jsonb_build_object('column', (select channel_outcome from marketing_post where id = v));
  -- The publish guard may refuse a demo post reaching 'published' at all; either way it must never be due.
  begin
    update marketing_post set status = 'published', published_at = now(), attempts = 1 where id = v;
    o := o || jsonb_build_object('demo_due', (select count(*) from fn_marketing_channel_results_due(50) d where d.post_id = v));
  exception when others then
    o := o || jsonb_build_object('demo_due', 0, 'demo_publish_refused', sqlerrm);
  end;
  raise exception 'CHK<<%>>', o::text;
end $$;
`;
