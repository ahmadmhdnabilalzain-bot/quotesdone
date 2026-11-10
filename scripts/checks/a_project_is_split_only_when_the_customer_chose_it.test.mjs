// A PROJECT IS SPLIT INTO TRADE PACKAGES ONLY WHEN THE CUSTOMER CHOSE IT (30 Sep 2026, sales_engineer; ruling 1021:
// never split without asking the customer first).
// THE DEFAULT CHANGED 10 Nov 2026 (evidence run, ledger 1604, finding c): one contractor was preselected for every brief
// naming two trades and sent whether the customer looked or not, so a PVC wall-panel job went out as 'turnkey', matched
// only turnkey fit-out contractors and reached nobody. Both choices are now always shown with a plain explanation;
// separate quotes per trade is preselected unless the brief is a whole fit-out (brief.whole_scope), and what is sent is
// what the customer was shown. The split itself is still only ever the customer's recorded 'multi'.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the portal preselects one contractor for every multi-trade brief again, or sends a mode the customer was
//     not shown, or calls the split recommended; create_inquiry splits without the customer's explicit 'multi'; the
//     guard loses its revoke or its pinned search_path; the file carries both (or neither of) a pending note and a
//     MANIFEST line;
//   * production, in ONE aborted transaction (the file replayed first while pending; nothing commits), on a ZZ DEMO
//     customer (@example.invalid): a per-trade part under a 'single' or 'turnkey' parent is refused; under a 'multi'
//     parent it is accepted; a split parent's choice cannot be rewritten while its parts exist.
//
//   node --test scripts/checks/a_project_is_split_only_when_the_customer_chose_it.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';
import { readSource } from '../lib/portal_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_project_is_split_only_when_the_customer_chose_it.sql';
const pending = () => existsSync(join(REPO, 'scripts/sql/pending', FILE.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: the customer is shown both choices, and what is sent is what they were shown', () => {
  const ui = readSource('src/components/me/NewRequest.tsx');
  assert.match(ui, /const \[combineMode, setCombineMode\] = useState\(null\);/, 'the portal preselects a mode before the brief is read again');
  assert.match(ui, /scope_type: \(brief && Array\.isArray\(brief\.trades\) && brief\.trades\.length > 1\) \? \(combineMode \|\| combineDefaultOf\(brief\)\) : 'single'/, 'the mode sent is not the one shown');
  assert.match(ui, /checked=\{\(combineMode \|\| combineDefaultOf\(brief\)\) === v\}/, 'the radio shown is not the mode sent');
  assert.match(ui, /\[\['multi', 'nr_multi_sep_h', 'nr_multi_sep_b'\], \['turnkey', 'nr_multi_tk_h', 'nr_multi_tk_b'\]\]/, 'both choices are no longer offered');
  const helpers = read('src/components/me/newRequest/helpers.ts');
  assert.match(helpers, /export const combineDefaultOf = \(brief\) => \(brief && brief\.whole_scope === true \? 'turnkey' : 'multi'\);/, 'one contractor is preselected for more than a whole fit-out');
  const txt = read('src/components/me/portalText.ts');
  assert.doesNotMatch(txt, /nr_multi_sep_h: '[^']*(recommended|موصى به)/, 'the split is labelled recommended again');
  const api = functionSource('customer_api');
  assert.match(api, /const scope_type = \['single','multi','turnkey'\]\.includes\(String\(body\.scope_type\)\) \? String\(body\.scope_type\) : 'single';/, 'create_inquiry no longer defaults to one request');
  assert.match(api, /const wantSplit = scope_type === 'multi' && distinctTrades\.length > 1;/, 'create_inquiry splits without the customer choosing multi');
  const sql = read(FILE);
  assert.match(sql, /security definer\s+set search_path to 'public', 'pg_temp'/);
  assert.match(sql, /revoke execute on function public\.trg_inquiry_split_needs_the_customers_choice\(\) from public, anon, authenticated;/);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(pending() !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: a split without the customer\'s recorded choice is refused', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql: sql } = await import('../lib/safe_replay.mjs');   // the one door: cannot commit
  const replay = pending() ? read(FILE) + '\n' : '';
  let o;
  try {
    await sql(replay + `
do $$
declare c uuid; p uuid; k uuid; out jsonb := '{}'::jsonb; s text;
begin
  select id into c from public.customers where email like '%@example.invalid' order by created_at limit 1;
  if c is null then raise exception 'CHK<<%>>', '{"error":"no ZZ DEMO customer"}'; end if;
  foreach s in array array['single', 'turnkey'] loop
    insert into public.inquiries (customer_id, category, summary, status, lang, scope_type)
    values (c, 'fitout', 'ZZ DEMO split guard ' || s, 'sent', 'en', s) returning id into p;
    begin
      insert into public.inquiries (customer_id, category, summary, status, lang, parent_inquiry_id)
      values (c, 'gypsum', 'ZZ DEMO split guard part', 'sent', 'en', p);
      out := out || jsonb_build_object(s, 'accepted');
    exception when others then out := out || jsonb_build_object(s, 'refused');
    end;
  end loop;
  insert into public.inquiries (customer_id, category, summary, status, lang, scope_type)
  values (c, 'fitout', 'ZZ DEMO split guard multi', 'split', 'en', 'multi') returning id into p;
  begin
    insert into public.inquiries (customer_id, category, summary, status, lang, parent_inquiry_id)
    values (c, 'gypsum', 'ZZ DEMO split guard part', 'sent', 'en', p) returning id into k;
    out := out || jsonb_build_object('multi', 'accepted');
  exception when others then out := out || jsonb_build_object('multi', 'refused: ' || sqlerrm);
  end;
  begin
    update public.inquiries set scope_type = 'turnkey' where id = p;
    out := out || jsonb_build_object('rewrite', 'accepted');
  exception when others then out := out || jsonb_build_object('rewrite', 'refused');
  end;
  raise exception 'CHK<<%>>', out::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.deepEqual(o, { single: 'refused', turnkey: 'refused', multi: 'accepted', rewrite: 'refused' });
});
