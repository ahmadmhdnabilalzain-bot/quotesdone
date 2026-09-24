// A CLAIMED COMPANY CANNOT BE REGISTERED TWICE (24 Sep 2026, sales_engineer).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: either key function loses IMMUTABLE or its pinned search_path, the name key stops using
//     fn_ar_norm or starts stripping words from the front of a name, either index loses its `where claimed`
//     restriction or its name (supplier_api reads the name), the SQL deletes or updates a lead, the file
//     carries both (or neither of) a pending note and a MANIFEST line, supplier_api stops mapping a 23505
//     on these indexes to company_already_registered at create_company / claim / process_docs, the refusal
//     sentence is written a second time instead of coming from company_already_registered.ts, or the portal
//     stops rendering that code on the claim screen;
//   * production, in ONE aborted transaction (the file replayed while pending; ZZ DEMO rows with
//     @example.invalid owners; nothing commits): after one claimed "ZZ DEMO Dup Steel Trading L.L.C." with
//     licence ZZ-DEMO-7731-01, a second claimed "zz demo dup steel FZ-LLC", a claimed "ZZ DEMO Other Glass"
//     with licence "zzdemo 773101", and claiming an unclaimed "ZZ DEMO Dup Steel Co." are each refused
//     with 23505 on the named index; an unclaimed twin of the name is still allowed (the directory keeps
//     its near-duplicates), and a genuinely different company is allowed.
//
//   node --test scripts/checks/a_claimed_company_cannot_be_registered_twice.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_claimed_company_cannot_be_registered_twice_under_another_spelling_or_the_same_licence.sql';
const API = 'supabase/functions/supplier_api/index.ts';
const MAP = 'supabase/functions/supplier_api/company_already_registered.ts';
const PORTAL = 'src/components/portal/SupplierPortal.tsx';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const NAME_IDX = 'leads_claimed_company_name_uidx';
const LIC_IDX = 'leads_claimed_trade_licence_uidx';

test('static: immutable keys, claimed-only indexes, nothing deleted, pending XOR MANIFEST', () => {
  const src = code(read(FILE));
  for (const fn of ['fn_company_registration_name_key', 'fn_trade_licence_key']) {
    assert.match(src, new RegExp(`function public\\.${fn}\\(p text\\)\\s+returns text\\s+language sql\\s+immutable\\s+parallel safe\\s+set search_path to 'public', 'pg_temp'`), `${fn} is not IMMUTABLE with a pinned search_path`);
    assert.doesNotMatch(src, new RegExp(`function public\\.${fn}[\\s\\S]{0,200}security definer`), `${fn} became SECURITY DEFINER`);
  }
  assert.match(src, /lower\(\s*public\.fn_ar_norm\(p\)\)/, 'the name key no longer folds Arabic through fn_ar_norm');
  // Legal forms are removed from the END only, and never the first word: the alternation is anchored
  // with $ and every alternative needs a leading space.
  assert.match(src, /'\( \(llc\|fze\|fzco\|fzllc\|fz\|est\|establishment\|trading\|co\|[^']*\)\)\+\$'/, 'the legal-form rule is no longer trailing-only');
  assert.doesNotMatch(src, /'\^\s*\(/, 'a rule anchored at the START of the name appeared');
  assert.match(src, new RegExp(`create unique index if not exists ${NAME_IDX}\\s+on public\\.leads \\(public\\.fn_company_registration_name_key\\(company_name\\)\\)\\s+where claimed`));
  assert.match(src, new RegExp(`create unique index if not exists ${LIC_IDX}\\s+on public\\.leads \\(public\\.fn_trade_licence_key\\(trade_license_no\\)\\)\\s+where claimed`));
  assert.doesNotMatch(src, /\b(delete\s+from|update)\s+public\.leads\b/i, 'the duplicate-company file writes to leads: existing rows are never deleted or merged');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('static: every supplier_api door that can trip the indexes answers with the existing refusal', () => {
  const map = read(MAP);
  assert.match(map, new RegExp(`DUPLICATE_COMPANY_INDEXES = \\['${NAME_IDX}', '${LIC_IDX}'\\]`));
  assert.match(map, /code: 'company_already_registered'/);
  assert.match(map, /String\(err\.code \?\? ''\) !== '23505'/, 'the mapping no longer requires a unique violation');
  const api = read(API);
  assert.match(api, /import \{ COMPANY_ALREADY_REGISTERED, isDuplicateCompany \} from '\.\/company_already_registered\.ts';/);
  const door = (name) => { const i = api.indexOf(`if (action === '${name}')`); assert.ok(i > 0, `${name} is gone`); return api.slice(i, api.indexOf('\n    if (action === ', i + 10)); };
  assert.match(door('create_company'), /if \(isDuplicateCompany\(error\)\) return J\(COMPANY_ALREADY_REGISTERED, 409\)/, 'create_company: a duplicate insert is not the existing refusal');
  assert.match(door('claim'), /if \(claimErr\) return isDuplicateCompany\(claimErr\) \? J\(COMPANY_ALREADY_REGISTERED, 409\)/, 'claim: a refused claim is not the existing refusal (or its result is discarded again)');
  assert.match(door('process_docs'), /if \(isDuplicateCompany\(updErr\)\) return J\(COMPANY_ALREADY_REGISTERED, 409\)/, 'process_docs: a duplicate licence is not the existing refusal');
  // No second copy of the sentence: the one server copy lives in company_already_registered.ts.
  assert.doesNotMatch(api, /A company with this name is already registered/, 'the refusal sentence was written again in index.ts');
  const portal = read(PORTAL);
  assert.match(portal, /if \(c === 'company_already_registered'\) return c;/, 'the claim screen no longer recognises the code');
  assert.match(portal, /srvText\(lang, code\) \|\| panelErrorText/, 'the claim screen no longer renders the existing copy');
  // The server sentence is the portal's existing English copy, word for word: no second wording.
  const sentence = map.match(/error: '([^']+)',\s*code: 'company_already_registered'/)?.[1];
  assert.ok(sentence, 'company_already_registered.ts lost its sentence');
  assert.ok(read('src/components/portal/supplier/serverCopy.ts').includes(`company_already_registered: s('${sentence}'`), 'the server sentence and the portal copy have drifted apart');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: a second registration under another spelling or the same licence is refused', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
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
  assert.equal(o.first, 'ok', 'the first ZZ DEMO registration was refused: ' + o.first);
  assert.equal(o.suffix, NAME_IDX, 'a differently-cased, differently-suffixed name was not refused by the name index');
  assert.equal(o.licence, LIC_IDX, 'the same licence under another name was not refused by the licence index');
  assert.equal(o.unclaimed_twin, 'ok', 'an UNCLAIMED directory twin was refused: only claimed rows are unique');
  assert.equal(o.claim_twin, NAME_IDX, 'claiming a listing that duplicates a claimed company was not refused');
  assert.equal(o.different, 'ok', 'a genuinely different company was refused: ' + o.different);
});

// Every insert is a ZZ DEMO row owned by an @example.invalid address (is_demo = true, nothing can reach a
// person), and the block always raises, so no row survives it.
const PROBE = String.raw`
do $$ declare o jsonb := '{}'; v text; u bigint; tag text := substr(md5(random()::text), 1, 6);
begin
  begin
    insert into public.leads (company_name, claimed, claimed_by, trade_license_no, source)
      values ('ZZ DEMO Dup Steel ' || tag || ' Trading L.L.C.', true, 'zz.dup.a.' || tag || '@example.invalid', 'ZZ-DEMO-7731-01-' || tag, 'qd_demo_fixture');
    o := o || jsonb_build_object('first', 'ok');
  exception when others then o := o || jsonb_build_object('first', sqlstate || ' ' || sqlerrm); end;

  begin
    insert into public.leads (company_name, claimed, claimed_by, source)
      values ('zz demo  dup steel ' || upper(tag) || ' FZ-LLC', true, 'zz.dup.b.' || tag || '@example.invalid', 'qd_demo_fixture');
    o := o || jsonb_build_object('suffix', 'ok');
  exception when unique_violation then get stacked diagnostics v = constraint_name; o := o || jsonb_build_object('suffix', v);
            when others then o := o || jsonb_build_object('suffix', sqlstate || ' ' || sqlerrm); end;

  begin
    insert into public.leads (company_name, claimed, claimed_by, trade_license_no, source)
      values ('ZZ DEMO Other Glass ' || tag, true, 'zz.dup.c.' || tag || '@example.invalid', 'zzdemo 773101 ' || upper(tag), 'qd_demo_fixture');
    o := o || jsonb_build_object('licence', 'ok');
  exception when unique_violation then get stacked diagnostics v = constraint_name; o := o || jsonb_build_object('licence', v);
            when others then o := o || jsonb_build_object('licence', sqlstate || ' ' || sqlerrm); end;

  begin
    insert into public.leads (company_name, claimed, source)
      values ('ZZ DEMO Dup Steel ' || tag || ' Co.', false, 'qd_demo_fixture') returning id into u;
    o := o || jsonb_build_object('unclaimed_twin', 'ok');
  exception when others then o := o || jsonb_build_object('unclaimed_twin', sqlstate || ' ' || sqlerrm); end;

  begin
    update public.leads set claimed = true, claimed_by = 'zz.dup.d.' || tag || '@example.invalid' where id = u;
    o := o || jsonb_build_object('claim_twin', 'ok');
  exception when unique_violation then get stacked diagnostics v = constraint_name; o := o || jsonb_build_object('claim_twin', v);
            when others then o := o || jsonb_build_object('claim_twin', sqlstate || ' ' || sqlerrm); end;

  begin
    insert into public.leads (company_name, claimed, claimed_by, trade_license_no, source)
      values ('ZZ DEMO Dup Stone ' || tag || ' LLC', true, 'zz.dup.e.' || tag || '@example.invalid', 'ZZ-DEMO-7731-02-' || tag, 'qd_demo_fixture');
    o := o || jsonb_build_object('different', 'ok');
  exception when others then o := o || jsonb_build_object('different', sqlstate || ' ' || sqlerrm); end;

  raise exception 'CHK<<%>>', o::text;
end $$;
`;
