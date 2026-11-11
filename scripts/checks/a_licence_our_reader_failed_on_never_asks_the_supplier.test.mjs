// A LICENCE OUR READER FAILED ON NEVER ASKS THE SUPPLIER FOR A CLEARER COPY (10 Nov 2026, customer_support; item 6 of the
// supplier-journey audit's report, #1901).
//
// process_docs answered extract_failed to the browser and stored nothing, so the gate held the licence as unread and the
// decider asked the supplier three times for a clearer copy and closed the registration at day 14, for OUR failure. This
// fails if: either licence reader stops storing whose failure it was; the gate stops holding it as licence_being_read ahead
// of the four unread reasons; the decider asks or closes it; the sweep stops reading it again; or the supplier is told to
// upload anything for it. Routine bodies are read from the definition that wins the apply order, with -- comments removed.
// Behaviour on production: the probe of the same name as the SQL file (rolled back). Whose failure it is: deno test
// supabase/functions/_shared/licence_read_state.test.ts.
//   node --test scripts/checks/a_licence_our_reader_failed_on_never_asks_the_supplier.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { functionSource } from '../lib/function_sources.mjs';

const SQL = 'scripts/sql/';
const FIX = 'a_licence_our_reader_failed_on_is_read_again_and_its_supplier_is_never_asked_for_it.sql';
const manifest = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  .map((l) => l.replace(/^scripts\/sql\//, ''));
const pending = (f) => existsSync(SQL + 'pending/' + f.replace(/\.sql$/, '.txt'));
const defRe = (fn) => new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${fn}\\s*\\(`, 'i');
function winning(fn) {
  const defines = (f) => existsSync(SQL + f) && defRe(fn).test(readFileSync(SQL + f, 'utf8'));
  if (pending(FIX) && defines(FIX)) return FIX;
  const listed = manifest.filter(defines);
  assert.ok(listed.length, `no file defines ${fn}`);
  return listed[listed.length - 1];
}
function body(fn) {
  const src = readFileSync(SQL + winning(fn), 'utf8');
  const open = src.search(defRe(fn));
  const m = /\bas\s+(\$[a-z_]*\$)/i.exec(src.slice(open));
  assert.ok(m, `${fn} has no dollar-quoted body`);
  const start = open + m.index + m[0].length;
  return src.slice(start, src.indexOf(m[1], start)).replace(/--[^\n]*/g, '');
}

test('the gate holds a licence our reader failed on as licence_being_read, ahead of the four unread reasons', () => {
  const b = body('fn_sales_engineer_verifies_supplier');
  assert.match(b, /v_ours_failed\s*:=\s*l\.license_doc_path is not null and coalesce\(l\.licence_read_state, ''\) = 'ours_failed'/);
  const held = b.search(/elsif v_ours_failed then v_decision := 'pending'; v_reason := 'licence_being_read';/);
  const unread = b.search(/elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_unreadable';/);
  assert.ok(held > 0 && unread > held, 'licence_being_read must be decided before licence_unreadable / _expiry_ / _number_ / _authority_unread');
});

test('the decider never asks the supplier for it and never closes it; three days on it goes to the ceo seat', () => {
  const b = body('fn_sales_engineer_decides_held_registrations');
  assert.match(b, /'licence_name_mismatch', 'licence_being_read'\)/, 'the decider does not look at licence_being_read at all');
  const branch = b.slice(b.indexOf("if r.reason = 'licence_being_read' then"));
  assert.ok(branch.length > 40, 'no licence_being_read branch');
  const end = branch.indexOf('continue;');
  assert.ok(end > 0, 'the branch must end the iteration before the ask and the close');
  const own = branch.slice(0, end);
  assert.doesNotMatch(own, /registration_held|registration_closed|approval_status = 'rejected'/, 'our failure must never ask or close');
  assert.match(own, /interval '3 days'[\s\S]*fn_ceo_task_open/);
  assert.ok(b.indexOf("if r.reason = 'licence_being_read' then") < b.indexOf("elsif v_asks > 0 and v_days >= 14 then"), 'the branch must come before the close');
});

test('the sweep reads it again: due rows are claimed with a back-off, and supplier_api re-runs the one licence reader', () => {
  const c = body('fn_supplier_licence_reread_claim');
  assert.match(c, /l\.licence_read_state = 'ours_failed'/);
  assert.match(c, /l\.licence_read_tries < 8/);
  assert.match(c, /10 \* \(2 \^ l\.licence_read_tries\)/);
  assert.match(c, /= v_fx/, 'a demo licence must never be read again by a real run (no model spend on fixtures)');
  const api = functionSource('supplier_api');
  const door = api.slice(api.indexOf("peek.action === 'docs_reread'"));
  assert.match(door.slice(0, 2500), /rpc\('fn_supplier_licence_reread_claim'/);
  assert.match(door.slice(0, 2500), /documentActions\(\{ email: [^}]*body, action: body\.action \}/, 'the re-read must be process_docs itself');
  assert.match(functionSource('resilience_ping'), /action: 'docs_reread'/, 'the heartbeat no longer asks for the re-read');
  const src = readFileSync(SQL + winning('fn_supplier_licence_reread_claim'), 'utf8');
  assert.match(src, /revoke execute on function public\.fn_supplier_licence_reread_claim\(integer\) from public, anon, authenticated;/);
});

test('both licence readers store whose failure it was, in the same write as the fields', () => {
  for (const fn of ['supplier_api', 'supplier_portal']) {
    const src = functionSource(fn);
    assert.match(src, /licenceReadState\(licenceLeftUnread\(upd\), [a-zA-Z]+\)/, `${fn} does not decide the read state from the fields it writes`);
    assert.match(src, /upd\.licence_read_state = state;/, `${fn} does not store the read state`);
    assert.match(src, /modelOutcomeOf\(jd\)/, `${fn} does not read the model's answer into an outcome`);
  }
  // since 11 Nov 2026 the model is asked after the row is written (supplier_api/lib/licence_store_first.ts), in askLicenceModel,
  // whose own outcome decides the state it writes
  assert.match(functionSource('supplier_api'), /catch \(e\) \{ (?:modelO|o)utcome = 'failed';/, 'a thrown model call must count as our failure');
  assert.match(functionSource('supplier_api'), /licenceReadState\(licenceLeftUnread\(\{ \.\.\.upd, \.\.\.mUpd \}\), outcome\)/, 'the model read after the answer must store whose failure it was');
});

test('the supplier is told it is on our side, and asked for nothing', () => {
  const copy = readFileSync('src/components/portal/supplier/serverCopy.ts', 'utf8');
  const line = copy.split('\n').find((l) => l.trimStart().startsWith('licence_being_read:')) || '';
  assert.ok(line, 'serverCopy has no wording for licence_being_read, so the header prints the raw code');
  const text = (copy.match(/const LICENCE_BEING_READ = '([^']*)'/) || [])[1] || '';
  assert.match(text, /on our side, not yours/);
  assert.doesNotMatch(text, /clearer copy|upload/i);
  assert.doesNotMatch(line + text, /[؀-ۿ]/, 'suppliers are written to in English');
  const api = functionSource('supplier_api');
  assert.match(api, /const licUnreadEn = licUnread\.length && !licBeingRead \?/, 'save_profile still asks for a clearer copy of a licence our reader failed on');
  assert.match(api, /out\.license_expiry_note = LICENCE_BEING_READ_NOTE/);
});
