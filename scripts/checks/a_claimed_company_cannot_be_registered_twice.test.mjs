// A CLAIMED COMPANY CANNOT BE REGISTERED TWICE (24 Sep 2026, sales_engineer; revised on the review of #962).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static, the SQL: either key function loses IMMUTABLE or its pinned search_path; the name key stops
//     folding Arabic through fn_ar_norm, stops decoding HTML entities, or starts DROPPING a legal form or a
//     word such as trading/est/co (review of #962: dropping them merged "X EST" with "X CO" and an FZE with
//     an LLC across the directory); either index loses its `where claimed` restriction or its name; the file
//     deletes or updates a lead; the duplicate precondition stops being a precondition; the file carries
//     both (or neither of) a pending note and a MANIFEST line;
//   * static, the functions: a registration refused by the indexes stops answering the EXISTING
//     company_already_registered (create_company, claim); claim puts raw Postgres text in its answer again
//     or stops mapping the sanctions trigger; a document write (supplier_api process_docs, supplier_portal
//     save_documents, resend_inbound, wa_inbound) stops setting a clashing licence number aside; the
//     refusal sentence is written a second time or drifts from serverCopy.ts; the portal stops showing it;
//   * production, in ONE aborted transaction (the file replayed while pending; ZZ DEMO rows with
//     @example.invalid owners, which the generated is_demo column marks demo; nothing commits): after one
//     claimed "ZZ DEMO Dup Steel <tag> Co. L.L.C." with licence ZZ-DEMO-7731-01-<tag>, a second claimed
//     "zz demo  dup-steel <TAG> Company (LLC)", a claimed "ZZ DEMO Other Glass" with licence
//     "zzdemo 773101 <TAG>", and claiming an unclaimed "ZZ DEMO DUP STEEL <tag> CO LLC" are each refused
//     with 23505 on the named index; an unclaimed twin, the same words as an FZE (another legal company)
//     and a genuinely different company are all allowed.
//
//   node --test scripts/checks/a_claimed_company_cannot_be_registered_twice.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { readSupplierPortal } from '../lib/portal_sources.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_claimed_company_cannot_be_registered_twice_under_another_spelling_or_the_same_licence.sql';
const API = 'supabase/functions/supplier_api/index.ts';
const MAP = 'supabase/functions/_shared/duplicate_company.ts';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const NAME_IDX = 'leads_claimed_company_name_uidx';
const LIC_IDX = 'leads_claimed_trade_licence_uidx';

test('static: immutable keys that fold spelling and drop no word, claimed-only indexes, nothing deleted, pending XOR MANIFEST', () => {
  const src = code(read(FILE));
  for (const fn of ['fn_company_registration_name_key', 'fn_trade_licence_key']) {
    assert.match(src, new RegExp(`function public\\.${fn}\\(p text\\)\\s+returns text\\s+language sql\\s+immutable\\s+parallel safe\\s+set search_path to 'public', 'pg_temp'`), `${fn} is not IMMUTABLE with a pinned search_path`);
    assert.doesNotMatch(src, new RegExp(`function public\\.${fn}[\\s\\S]{0,200}security definer`), `${fn} became SECURITY DEFINER`);
  }
  const key = src.slice(src.indexOf('function public.fn_company_registration_name_key'), src.indexOf('comment on function public.fn_company_registration_name_key'));
  assert.match(key, /lower\(public\.fn_ar_norm\(p\)\)/, 'the name key no longer folds Arabic through fn_ar_norm');
  assert.match(key, /'&\(amp\|#0\*38\|#x0\*26\);', '&'/, 'the name key no longer decodes &#038; / &amp;');
  assert.match(key, /'&#\?\[a-z0-9\]\+;', ' '/, 'the name key no longer treats other HTML entities as separators');
  // The SPELLING of a legal form is folded and KEPT: each rule rewrites to the canonical form.
  for (const [pattern, to] of [['\\ml l c\\M', 'llc'], ['\\mf z e\\M', 'fze'], ['\\mf z c o\\M', 'fzco'], ['\\mf ?z llc\\M', 'fzllc'],
    ['\\mestablishment\\M', 'est'], ['\\mcompany\\M', 'co'], ['\\mذ م م\\M', 'llc'], ['\\mذمم\\M', 'llc']]) {
    assert.ok(key.includes(`'${pattern}', '${to}'`), `the legal-form spelling rule ${pattern} -> ${to} is gone`);
  }
  // No rule may DROP a legal form or a word (review of #962): nothing that names one is replaced by ''.
  assert.doesNotMatch(key, /'[^'\n]*\b(llc|fze|fzco|fzllc|fz|est|establishment|trading|co|company|ذمم)\b[^'\n]*',\s*''/, 'a rule drops a legal form or a word such as trading/est/co');
  assert.doesNotMatch(key, /\$'\s*,\s*''/, 'a rule strips a trailing word');
  assert.match(src, new RegExp(`create unique index if not exists ${NAME_IDX}\\s+on public\\.leads \\(public\\.fn_company_registration_name_key\\(company_name\\)\\)\\s+where claimed`));
  assert.match(src, new RegExp(`create unique index if not exists ${LIC_IDX}\\s+on public\\.leads \\(public\\.fn_trade_licence_key\\(trade_license_no\\)\\)\\s+where claimed`));
  assert.doesNotMatch(src, /\b(delete\s+from|update)\s+public\.leads\b/i, 'the duplicate-company file writes to leads: existing rows are never deleted or merged');
  assert.match(read(FILE), /PRECONDITION: EXISTING DUPLICATES ABORT THE APPLY BY ID/, 'the duplicate guard is no longer marked as a precondition');
  assert.match(src, /raise exception 'claimed duplicates exist; exclude them by id in the index predicate, never delete/);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

test('static: registrations get the existing refusal, claim leaks no Postgres text, document writes set a clashing licence aside', () => {
  const map = read(MAP);
  assert.match(map, new RegExp(`DUPLICATE_NAME_INDEX = '${NAME_IDX}'`));
  assert.match(map, new RegExp(`DUPLICATE_LICENCE_INDEX = '${LIC_IDX}'`));
  assert.match(map, /code: 'company_already_registered'/);
  assert.match(map, /String\(err\.code \?\? ''\) === '23505'/, 'the mapping no longer requires a unique violation');
  assert.doesNotMatch(map, /\.rpc\(/, 'the mapping calls a SQL routine: it must work before the SQL is applied');
  const api = functionSource('supplier_api');
  const door = (name) => { const i = api.indexOf(`if (action === '${name}')`); assert.ok(i > 0, `${name} is gone`); return api.slice(i, api.indexOf('\n    if (action === ', i + 10)); };
  // 28 Oct 2026 (ledger 1401 audit S7): create_company's body moved to supplier_api/create_company.ts, which also claims the
  // invited listing its address holds (an_invited_supplier_who_registers_on_the_website_claims_his_invited_listing.test.mjs).
  assert.match(door('create_company'), /const r = await createCompany\(admin, email, body, /, 'create_company no longer goes through create_company.ts');
  assert.match(read('supabase/functions/supplier_api/create_company.ts'), /if \(isDuplicateCompany\(error\)\) return \{ status: 409, body: \{ \.\.\.COMPANY_ALREADY_REGISTERED \} \}/, 'create_company: a duplicate write is not the existing refusal');
  const claim = door('claim');
  assert.match(claim, /if \(claimErr\) \{[^}]*const r = registrationRefusal\(claimErr\); return J\(r\.body, r\.status\); \}/, 'claim: a refused claim is not mapped (or its result is discarded again)');
  assert.doesNotMatch(claim, /J\(\{ error: \w+\.message/, 'claim: raw Postgres text reaches the browser (SP-I-01)');
  assert.match(map, /includes\('SANCTIONED_PARTY_BLOCKED'\)\) return \{ body: \{ \.\.\.SANCTIONED_REGISTRATION_REFUSAL \}, status: 403 \}/, 'claim: the sanctions trigger no longer gets the create_company 403');
  assert.match(door('process_docs'), /updateLeadSettingAsideClashingLicence\(admin as unknown as LeadWriter, sup\.id, upd, 'supplier_api\.process_docs'\)/, 'process_docs: a clashing licence fails the whole document write again');
  for (const [file, source] of [['supabase/functions/supplier_portal/index.ts', 'supplier_portal.save_documents'], ['supabase/functions/resend_inbound/index.ts', 'resend_inbound'], ['supabase/functions/wa_inbound/index.ts', 'wa_inbound']]) {
    assert.match(/(wa_inbound|resend_inbound)\/index\.ts$/.test(file) ? functionSource(file.split('/').at(-2)) : read(file), new RegExp(`updateLeadSettingAsideClashingLicence\\(admin as unknown as LeadWriter, [\\w.]+, \\w+, '${source.replace('.', '\\.')}'\\)`), `${file}: a clashing licence fails the whole document write again`);
  }
  // No second copy of the sentence: the one server copy lives in _shared/duplicate_company.ts.
  for (const f of [API, 'supabase/functions/supplier_portal/index.ts']) assert.doesNotMatch(f === API ? functionSource('supplier_api') : read(f), /A company with this name is already registered/, `the refusal sentence was written again in ${f}`);
  const portal = readSupplierPortal();
  assert.match(portal, /if \(c === 'company_already_registered'\) return c;/, 'the claim screen no longer recognises the code');
  assert.match(portal, /if \(j\.extracted && j\.extracted\.licence_set_aside\) setMsg\(srvText\(lang, 'company_already_registered'\)\)/, 'the licence upload no longer says the number was set aside');
  // The server sentence is the portal's existing English copy, word for word: no second wording.
  const sentence = map.match(/error: '([^']+)',\s*code: 'company_already_registered'/)?.[1];
  assert.ok(sentence, 'duplicate_company.ts lost its sentence');
  assert.ok(read('src/components/portal/supplier/serverCopy.ts').includes(`company_already_registered: s('${sentence}'`), 'the server sentence and the portal copy have drifted apart');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: a second registration under another spelling or the same licence is refused', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending(FILE) ? read(FILE) : '';
  let o;
  try { await replaySql(replay + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.first, 'ok', 'the first ZZ DEMO registration was refused: ' + o.first);
  assert.equal(o.spelling, NAME_IDX, 'a differently spelt, differently cased name was not refused by the name index');
  assert.equal(o.licence, LIC_IDX, 'the same licence under another name was not refused by the licence index');
  assert.equal(o.unclaimed_twin, 'ok', 'an UNCLAIMED directory twin was refused: only claimed rows are unique');
  assert.equal(o.claim_twin, NAME_IDX, 'claiming a listing that duplicates a claimed company was not refused');
  assert.equal(o.other_legal_form, 'ok', 'the same words as an FZE were refused: a different legal form is a different company');
  assert.equal(o.different, 'ok', 'a genuinely different company was refused: ' + o.different);
  assert.equal(o.all_demo, true, 'a probe row was not marked demo');
});

// Every insert is a ZZ DEMO row owned by an @example.invalid address; is_demo is a GENERATED column
// (company_name ilike 'ZZ DEMO%', the .invalid owner, source qd_demo_fixture), so it cannot be set and is
// asserted instead. The block always raises, so no row survives it.
const PROBE = String.raw`
do $$ declare o jsonb := '{}'; v text; u bigint; ids bigint[] := '{}'; tag text := substr(md5(random()::text), 1, 6);
begin
  begin
    insert into public.leads (company_name, claimed, claimed_by, trade_license_no, source)
      values ('ZZ DEMO Dup Steel ' || tag || ' Co. L.L.C.', true, 'zz.dup.a.' || tag || '@example.invalid', 'ZZ-DEMO-7731-01-' || tag, 'qd_demo_fixture')
      returning id into u;
    ids := ids || u; o := o || jsonb_build_object('first', 'ok');
  exception when others then o := o || jsonb_build_object('first', sqlstate || ' ' || sqlerrm); end;

  begin
    insert into public.leads (company_name, claimed, claimed_by, source)
      values ('zz demo  dup-steel ' || upper(tag) || ' Company (LLC)', true, 'zz.dup.b.' || tag || '@example.invalid', 'qd_demo_fixture');
    o := o || jsonb_build_object('spelling', 'ok');
  exception when unique_violation then get stacked diagnostics v = constraint_name; o := o || jsonb_build_object('spelling', v);
            when others then o := o || jsonb_build_object('spelling', sqlstate || ' ' || sqlerrm); end;

  begin
    insert into public.leads (company_name, claimed, claimed_by, trade_license_no, source)
      values ('ZZ DEMO Other Glass ' || tag, true, 'zz.dup.c.' || tag || '@example.invalid', 'zzdemo 773101 ' || upper(tag), 'qd_demo_fixture');
    o := o || jsonb_build_object('licence', 'ok');
  exception when unique_violation then get stacked diagnostics v = constraint_name; o := o || jsonb_build_object('licence', v);
            when others then o := o || jsonb_build_object('licence', sqlstate || ' ' || sqlerrm); end;

  begin
    insert into public.leads (company_name, claimed, source)
      values ('ZZ DEMO DUP STEEL ' || tag || ' CO LLC', false, 'qd_demo_fixture') returning id into u;
    ids := ids || u; o := o || jsonb_build_object('unclaimed_twin', 'ok');
  exception when others then o := o || jsonb_build_object('unclaimed_twin', sqlstate || ' ' || sqlerrm); end;

  begin
    update public.leads set claimed = true, claimed_by = 'zz.dup.d.' || tag || '@example.invalid' where id = u;
    o := o || jsonb_build_object('claim_twin', 'ok');
  exception when unique_violation then get stacked diagnostics v = constraint_name; o := o || jsonb_build_object('claim_twin', v);
            when others then o := o || jsonb_build_object('claim_twin', sqlstate || ' ' || sqlerrm); end;

  begin
    insert into public.leads (company_name, claimed, claimed_by, source)
      values ('ZZ DEMO Dup Steel ' || tag || ' Co FZE', true, 'zz.dup.f.' || tag || '@example.invalid', 'qd_demo_fixture') returning id into u;
    ids := ids || u; o := o || jsonb_build_object('other_legal_form', 'ok');
  exception when others then o := o || jsonb_build_object('other_legal_form', sqlstate || ' ' || sqlerrm); end;

  begin
    insert into public.leads (company_name, claimed, claimed_by, trade_license_no, source)
      values ('ZZ DEMO Dup Stone ' || tag || ' LLC', true, 'zz.dup.e.' || tag || '@example.invalid', 'ZZ-DEMO-7731-02-' || tag, 'qd_demo_fixture') returning id into u;
    ids := ids || u; o := o || jsonb_build_object('different', 'ok');
  exception when others then o := o || jsonb_build_object('different', sqlstate || ' ' || sqlerrm); end;

  o := o || jsonb_build_object('all_demo', (select bool_and(is_demo) and count(*) = cardinality(ids) from public.leads where id = any(ids)));
  raise exception 'CHK<<%>>', o::text;
end $$;
`;
