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
  for (const f of ['fn_supplier_named_in(text)', 'trg_published_text_names_no_supplier()']) {
    assert.ok(s.includes(`revoke execute on function public.${f} from public, anon, authenticated;`), f + ': no revoke');
  }
  assert.equal((s.match(/security definer\s+set search_path to 'public', 'pg_temp'/g) || []).length, 2, 'a routine without a pinned search_path');
  for (const t of TABLES) assert.match(s, new RegExp(`create trigger a06_names_no_supplier before insert or update of [^\\n]+ on public\\.${t}\\n`), t + ' is not guarded');
  // a seat reply the guard refuses closes its inbound message with an outcome; it is not thrown into a retry
  assert.match(read('supabase/functions/marketing_social_inbox/index.ts'), /if \(oErr && \/ruling 1020\/\.test\(oErr\.message\)\) return await outcome\('reply_names_a_supplier'\);/);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(pending() !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: naming a supplier is refused on every surface, a trade word is not', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
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
