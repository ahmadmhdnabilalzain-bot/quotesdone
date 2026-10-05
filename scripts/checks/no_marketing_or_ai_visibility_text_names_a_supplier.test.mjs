// NO MARKETING OR AI-VISIBILITY TEXT NAMES A SUPPLIER (30 Sep 2026, marketing; founder ruling 1020).
//
// MEASURED: ruling 1020 was enforced only by the CEO seat's no_supplier_named review criterion, on blog articles only.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the guard routine or the trigger routine loses its revoke or its pinned search_path; a published-text
//     table loses its trigger in the file; the file carries both (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (the file replayed first while pending; nothing commits), with a ZZ DEMO
//     supplier (@example.invalid) added to leads: all seven published-text tables carry the trigger; a blog post, a
//     reply-library answer and an edited post variant that name it are refused; the same texts without the name, and a
//     generic trade word that is also a lead's bare name ("Landscaping"), and "a general trading licence" with a ZZ DEMO
//     lead "General Trading LLC" on file, are accepted.
//
//   * production, timed in a rolled-back run: one write to each of the 7 surfaces (the largest row re-saved, or a
//     10 KB text for social_message, which has no rows yet) must cost under 200 ms.
//
//   * production, timed in a rolled-back run: one write to each of the 7 surfaces (the largest row re-saved, or a
//     10 KB text for social_message, which has no rows yet) must cost under 200 ms.
//
//   node --test scripts/checks/no_marketing_or_ai_visibility_text_names_a_supplier.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/no_marketing_or_ai_visibility_text_names_a_supplier.sql';
const pending = () => existsSync(join(REPO, 'scripts/sql/pending', FILE.split('/').pop().replace(/\.sql$/, '.txt')));
const TABLES = ['blog_posts', 'marketing_article', 'marketing_post', 'marketing_post_variant', 'social_message', 'social_reply_library', 'social_posts'];

test('static: both routines closed and pinned, every published-text table guarded, pending XOR applied', () => {
  const s = read(FILE);
  for (const f of ['fn_supplier_named_in(text)', 'fn_supplier_name_norm(text)', 'trg_published_text_names_no_supplier()', 'trg_leads_keep_the_public_name()']) {
    assert.ok(s.includes(`revoke execute on function public.${f} from public, anon, authenticated;`), f + ': no revoke');
  }
  assert.equal((s.match(/security definer\s+set search_path to 'public', 'pg_temp'/g) || []).length, 4, 'a routine without a pinned search_path');
  for (const t of TABLES) assert.match(s, new RegExp(`create trigger a06_names_no_supplier before insert or update of [^\\n]+ on public\\.${t}\\n`), t + ' is not guarded');
  // a seat reply the guard refuses closes its inbound message with an outcome; it is not thrown into a retry
  assert.match(read('supabase/functions/marketing_social_inbox/index.ts'), /if \(oErr && \/ruling 1020\/\.test\(oErr\.message\)\) return await outcome\('reply_names_a_supplier'\);/);
  // the name set is precomputed and indexed, and the guard runs ONCE per row (review of #1164: ~3 s a call, 8 calls a row)
  assert.match(s, /create index if not exists supplier_public_name_norm on public\.supplier_public_name \(norm\);/);
  assert.match(s, /create trigger z40_leads_keep_the_public_name after insert or update of company_name on public\.leads/);
  assert.equal((s.match(/public\.fn_supplier_named_in\(v_text\)/g) || []).length, 1, 'the row guard must call the lookup once per row');
  assert.doesNotMatch(s.slice(s.indexOf('create or replace function public.fn_supplier_named_in')), /from public\.leads l\s+where length/, 'the lookup folds every lead per call again');
  // the name set is precomputed and indexed, and the guard runs ONCE per row (review of #1164: ~3 s a call, 8 calls a row)
  assert.match(s, /create index if not exists supplier_public_name_norm on public\.supplier_public_name \(norm\);/);
  assert.match(s, /create trigger z40_leads_keep_the_public_name after insert or update of company_name on public\.leads/);
  assert.equal((s.match(/public\.fn_supplier_named_in\(v_text\)/g) || []).length, 1, 'the row guard must call the lookup once per row');
  assert.doesNotMatch(s.slice(s.indexOf('create or replace function public.fn_supplier_named_in')), /from public\.leads l\s+where length/, 'the lookup folds every lead per call again');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(pending() !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: naming a supplier is refused on every surface, a trade word is not', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql: sql } = await import('../lib/safe_replay.mjs');   // the one door: cannot commit
  const replay = pending() ? read(FILE) + '\n' : '';
  const T = TABLES.map((t) => `'${t}'`).join(',');
  let o;
  try {
    await sql(replay + `
do $$
declare n text := 'ZZ DEMO Namecheck Trading LLC'; out jsonb; v bigint;
begin
  insert into public.leads (company_name, email) values (n, 'zz-demo-namecheck@example.invalid'),
    ('General Trading LLC', 'zz-demo-namecheck-generic@example.invalid');
  out := jsonb_build_object('guarded', (select count(distinct c.relname) from pg_trigger g join pg_class c on c.oid = g.tgrelid
                                         where g.tgname = 'a06_names_no_supplier' and c.relname in (${T})));
  begin insert into public.blog_posts (slug, title, body_html) values ('zz-demo-namecheck-1', 'Tiles', '<p>We like zz demo namecheck  trading llc.</p>');
        out := out || '{"blog_named":"accepted"}';
  exception when others then out := out || '{"blog_named":"refused"}'; end;
  begin insert into public.blog_posts (slug, title, body_html) values ('zz-demo-namecheck-2', 'Landscaping in Dubai', '<p>What landscaping costs.</p>');
        out := out || '{"blog_clean":"accepted"}';
  exception when others then out := out || jsonb_build_object('blog_clean', 'refused: ' || left(regexp_replace(sqlerrm, '[^a-zA-Z0-9 _:]', ' ', 'g'), 200)); end;
  begin insert into public.blog_posts (slug, title, body_html) values ('zz-demo-namecheck-3', 'Licences', '<p>How a general trading licence works.</p>');
        out := out || '{"blog_generic":"accepted"}';
  exception when others then out := out || jsonb_build_object('blog_generic', 'refused: ' || left(regexp_replace(sqlerrm, '[^a-zA-Z0-9 _:]', ' ', 'g'), 200)); end;
  begin insert into public.social_reply_library (key, reply_en, reply_ar) values ('zz_demo_namecheck', 'Try ' || n, 'x');
        out := out || '{"reply_named":"accepted"}';
  exception when others then out := out || '{"reply_named":"refused"}'; end;
  select min(id) into v from public.marketing_post_variant;
  if v is not null then
    begin update public.marketing_post_variant set caption = caption || ' ' || n where id = v;
          out := out || '{"variant_named":"accepted"}';
    exception when others then out := out || '{"variant_named":"refused"}'; end;
  else out := out || '{"variant_named":"untested: no marketing_post_variant row on production"}';
  end if;
  raise exception 'CHK<<%>>', out::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.deepEqual(o, { guarded: TABLES.length, blog_named: 'refused', blog_clean: 'accepted', blog_generic: 'accepted', reply_named: 'refused', variant_named: 'refused' });
});

test('production, aborted: one write to each of the 7 surfaces costs under 200 ms', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql: sql } = await import('../lib/safe_replay.mjs');   // the one door: cannot commit
  const replay = pending() ? read(FILE) + '\n' : '';
  let o;
  try {
    await sql(replay + `do $$
declare t0 timestamptz; out jsonb := '{}'::jsonb; v bigint; u uuid; n int;
begin
  -- one real UPDATE of the largest row per table (fires the guard once), else the guard on a 10 KB synthetic text
  select id into u from public.blog_posts order by length(body_html) desc limit 1;
  t0 := clock_timestamp(); update public.blog_posts set body_html = body_html where id = u;
  out := out || jsonb_build_object('blog_posts', round(extract(epoch from clock_timestamp() - t0) * 1000));
  select id into v from public.marketing_article order by length(coalesce(body_html_en, '')) desc limit 1;
  t0 := clock_timestamp(); update public.marketing_article set body_html_en = body_html_en where id = v;
  out := out || jsonb_build_object('marketing_article', round(extract(epoch from clock_timestamp() - t0) * 1000), 'marketing_article_row', v is not null);
  select id into v from public.marketing_post order by length(coalesce(text_en, '')) desc limit 1;
  t0 := clock_timestamp(); update public.marketing_post set text_en = text_en where id = v;
  out := out || jsonb_build_object('marketing_post', round(extract(epoch from clock_timestamp() - t0) * 1000));
  select id into v from public.marketing_post_variant order by length(coalesce(body, '') || caption) desc limit 1;
  t0 := clock_timestamp(); update public.marketing_post_variant set caption = caption where id = v;
  out := out || jsonb_build_object('marketing_post_variant', round(extract(epoch from clock_timestamp() - t0) * 1000));
  select count(*) into n from public.social_posts;
  t0 := clock_timestamp(); update public.social_posts set content = content where id = (select id from public.social_posts order by length(content::text) desc limit 1);
  out := out || jsonb_build_object('social_posts', round(extract(epoch from clock_timestamp() - t0) * 1000), 'social_posts_rows', n);
  t0 := clock_timestamp(); insert into public.social_reply_library (key, reply_en, reply_ar) values ('zz_demo_timing', repeat('A reply about tiles and grout. ', 30), 'x');
  out := out || jsonb_build_object('social_reply_library', round(extract(epoch from clock_timestamp() - t0) * 1000));
  t0 := clock_timestamp(); perform public.fn_supplier_named_in(repeat('Chiller maintenance and gypsum partitions for villas in Dubai. ', 160));
  out := out || jsonb_build_object('social_message_guard_10kb', round(extract(epoch from clock_timestamp() - t0) * 1000));
  raise exception 'CHK<<%>>', out::text;
end $$;
`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the timing probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  console.log('  ms per write:', JSON.stringify(o));
  for (const k of ['blog_posts', 'marketing_article', 'marketing_post', 'marketing_post_variant', 'social_posts', 'social_reply_library', 'social_message_guard_10kb']) {
    assert.ok(Number(o[k]) < 200, `${k}: ${o[k]} ms per write, the target is under 200`);
  }
});

test('production, aborted: one write to each of the 7 surfaces costs under 200 ms', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql: sql } = await import('../lib/safe_replay.mjs');   // the one door: cannot commit
  const replay = pending() ? read(FILE) + '\n' : '';
  let o;
  try {
    await sql(replay + `do $$
declare t0 timestamptz; out jsonb := '{}'::jsonb; v bigint; u uuid; n int;
begin
  -- one real UPDATE of the largest row per table (fires the guard once), else the guard on a 10 KB synthetic text
  select id into u from public.blog_posts order by length(body_html) desc limit 1;
  t0 := clock_timestamp(); update public.blog_posts set body_html = body_html where id = u;
  out := out || jsonb_build_object('blog_posts', round(extract(epoch from clock_timestamp() - t0) * 1000));
  select id into v from public.marketing_article order by length(coalesce(body_html_en, '')) desc limit 1;
  t0 := clock_timestamp(); update public.marketing_article set body_html_en = body_html_en where id = v;
  out := out || jsonb_build_object('marketing_article', round(extract(epoch from clock_timestamp() - t0) * 1000), 'marketing_article_row', v is not null);
  select id into v from public.marketing_post order by length(coalesce(text_en, '')) desc limit 1;
  t0 := clock_timestamp(); update public.marketing_post set text_en = text_en where id = v;
  out := out || jsonb_build_object('marketing_post', round(extract(epoch from clock_timestamp() - t0) * 1000));
  select id into v from public.marketing_post_variant order by length(coalesce(body, '') || caption) desc limit 1;
  t0 := clock_timestamp(); update public.marketing_post_variant set caption = caption where id = v;
  out := out || jsonb_build_object('marketing_post_variant', round(extract(epoch from clock_timestamp() - t0) * 1000));
  select count(*) into n from public.social_posts;
  t0 := clock_timestamp(); update public.social_posts set content = content where id = (select id from public.social_posts order by length(content::text) desc limit 1);
  out := out || jsonb_build_object('social_posts', round(extract(epoch from clock_timestamp() - t0) * 1000), 'social_posts_rows', n);
  t0 := clock_timestamp(); insert into public.social_reply_library (key, reply_en, reply_ar) values ('zz_demo_timing', repeat('A reply about tiles and grout. ', 30), 'x');
  out := out || jsonb_build_object('social_reply_library', round(extract(epoch from clock_timestamp() - t0) * 1000));
  t0 := clock_timestamp(); perform public.fn_supplier_named_in(repeat('Chiller maintenance and gypsum partitions for villas in Dubai. ', 160));
  out := out || jsonb_build_object('social_message_guard_10kb', round(extract(epoch from clock_timestamp() - t0) * 1000));
  raise exception 'CHK<<%>>', out::text;
end $$;
`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the timing probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  console.log('  ms per write:', JSON.stringify(o));
  for (const k of ['blog_posts', 'marketing_article', 'marketing_post', 'marketing_post_variant', 'social_posts', 'social_reply_library', 'social_message_guard_10kb']) {
    assert.ok(Number(o[k]) < 200, `${k}: ${o[k]} ms per write, the target is under 200`);
  }
});
