// AN INVITED SUPPLIER WHO REGISTERS ON THE WEBSITE CLAIMS HIS INVITED LISTING (28 Oct 2026, sales_engineer; founder
// ledger 1401, the supplier-journey audit, scenario S7).
//
// MEASURED on production 07:54Z (run aub990b4a): an invited ZZ DEMO lead signed up on quotesdone.com with the invited
// address; create_company inserted a second row for it and answered HTTP 500
// "duplicate key value violates unique constraint "uq_leads_email_lower"", which the portal printed to the supplier.
// The behaviour is tested in supabase/functions/supplier_api/create_company.test.ts (an in-memory leads with
// production's unique rules). This check fails when the CAUSE returns around it:
//   * static: the create_company door stops delegating to create_company.ts; create_company.ts inserts before it has
//     looked for the lead holding the address, or claims without the `claimed_by is null` guard, or answers a body built
//     from a database message; a refusal code loses its portal copy or its sentence drifts from the server's;
//   * production, ONE aborted transaction (ZZ DEMO, @example.invalid, nothing commits): the second row the old door
//     inserted is refused by uq_leads_email_lower whatever the case of the address; the claim the new door sends finds
//     the invited row case-insensitively, claims it once, and a second account racing for it updates nothing.
// REVIEW OF #1712 (28 Oct 2026), also static: the claim stops needing a session opened by a code (the JWT amr) on top of
// a used code row; the door stops handing in that fact or the sanctions read; the /portal?t= claim writes without the
// same guard (a website sign-up and a token claim could both win) or claims a sanctioned listing; and any supplier_api
// answer, on any action, is built from a database, storage or exception message again.
//
//   node --test scripts/checks/an_invited_supplier_who_registers_on_the_website_claims_his_invited_listing.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const DOOR = 'supabase/functions/supplier_api/create_company.ts';
const COPY = 'src/components/portal/supplier/serverCopy.ts';
const noComments = (t) => t.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');

test('static: the door delegates, looks up the address before inserting, claims under a guard, never echoes the database', () => {
  const api = functionSource('supplier_api');
  const i = api.indexOf("if (action === 'create_company')");
  assert.ok(i > 0, 'create_company is gone from supplier_api');
  const door = api.slice(i, api.indexOf('\n', i));
  assert.match(door, /const r = await createCompany\(admin, email, body, \{ emailProven, /, 'the create_company door no longer goes through create_company.ts');
  assert.doesNotMatch(door, /\.insert\(/, 'the create_company door inserts a lead itself again');
  const src = noComments(read(DOOR));
  // #2032 (17 Nov 2026): the look-up is whereAddress (_shared/address_filter.ts), a case-insensitive EQUALITY, never a pattern
  const look = src.indexOf("whereAddress(admin.from('leads').select('id,claimed,claimed_by,business_role'), 'email', email)");
  // the leads insert, not the first `.insert(` in the file: the agent_actions record (audit, H10) is defined above createCompany,
  // and found first it failed this on origin/main da0e42909 (15 Nov 2026) though the leads insert still comes after the look-up
  const ins = src.indexOf("admin.from('leads').insert(");
  assert.ok(look > 0, 'create_company no longer looks for the lead that already holds the address');
  assert.ok(ins > look, 'create_company inserts before it has looked for the lead holding the address');
  assert.match(src, /\.update\(upd\)\.eq\('id', id\)\.is\('claimed_by', null\)\.select\('id'\)/, 'the claim lost its claimed_by-is-null guard: two sign-ups could both claim the row');
  assert.match(src, /if \(!won \|\| !won\.length\) return \{ status: 409, body: \{ \.\.\.EMAIL_ALREADY_REGISTERED \} \}/, 'a lost race is no longer the 409');
  assert.doesNotMatch(src, /body: \{[^}]*error\.message/, 'a response body is built from a database message again');
  assert.doesNotMatch(src, /error: error\.message/, 'a response body carries the database message again');
  // review of #1712: a "used" code row is also a retired or burned code, and public sign-up allows a password session
  assert.match(door, /sessionByCode: sessionOpenedByCode\(jwt\), sanctionedLead: \(id: number\) => sanctionedLead\(admin, id\)/, 'the door no longer hands create_company how the session was opened, or the sanctions read');
  assert.match(src, /planCreateCompany\(\{ ownCompany: !!existing, emailLeads: held, emailProven: proven && deps\.sessionByCode === true \}\)/, 'the claim no longer needs a session opened by a code');
  assert.match(src, /amr\.some\(\(m: \{ method\?: unknown \} \| null\) => CODE_METHODS\.has\(/, 'sessionOpenedByCode no longer reads the amr');
  assert.match(src, /const CODE_METHODS = new Set\(\['otp', 'magiclink'\]\);/, 'a password (or any other) session method was let in');
  assert.match(src, /if \(await deps\.sanctionedLead\(id\)\) return \{ status: 403, body: \{ \.\.\.SANCTIONED_REGISTRATION_REFUSAL \} \};/, 'a sanctioned listing can be claimed again');
  assert.match(src, /if \(error\) return lookupFailed\(/, 'a failed look-up reads as "no lead holds the address" again');
});

test('static: the /portal?t= claim writes under the same guard, and no supplier_api answer carries a database sentence', () => {
  const api = functionSource('supplier_api');
  const i = api.indexOf("if (action === 'claim')");
  assert.ok(i > 0, 'claim is gone from supplier_api');
  const claim = api.slice(i, api.indexOf('\n', i));
  assert.match(claim, /if \(await sanctionedLead\(admin, id\)\) return J\(SANCTIONED_REGISTRATION_REFUSAL, 403\);/, 'claim: a sanctioned listing can be claimed by token');
  assert.match(claim, /await \(owned \? claimWrite\.eq\('claimed_by', email\) : claimWrite\.is\('claimed_by', null\)\)\.select\('id'\)/, 'claim: the token claim writes without the claimed_by guard (two accounts can both win)');
  assert.match(claim, /if \(!won \|\| !won\.length\) return J\(\{ error: 'This company is already claimed by another account\.' \}, 409\);/, 'claim: a lost race is not the 409');
  // Every module of the function, comments stripped: no answer is built from a database, storage or exception message.
  const code = (t) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');
  const dir = 'supabase/functions/supplier_api/';
  for (const f of readdirSync(join(REPO, dir)).filter((n) => n.endsWith('.ts') && !/\.(test|fixture|check)\.ts$/.test(n))) {
    const s = code(read(dir + f));
    assert.doesNotMatch(s, /J\(\{[^;]*?\b(?:e|err|error|\w+Err)\??\.message\b/, `${f}: an answer is built from an error's message`);
    assert.doesNotMatch(s, /J\(\{ error: String\(e\)/, `${f}: an answer is the exception's own text`);
    assert.doesNotMatch(s, /detail: [\w?.]*(?:\.message\b|String\(\(?e\b)/, `${f}: a detail carries an error's message`);
    assert.doesNotMatch(s, /detail: jd\?\.detail/, `${f}: another function's error detail is relayed to the caller`);
  }
  // since 13 Nov 2026 the outer catch names the action it was in (the cause goes to agent_runs, masked; the body stays generic)
  assert.match(code(api), /\} catch \(e\) \{\s*return failed\((?:actionName \? `unhandled in \$\{actionName\}` : )?'unhandled', e\);\s*\}\s*\};\s*Deno\.serve/, 'the outer catch answers with the exception text again');
});

test('static: every refusal has portal copy, word for word', () => {
  const src = read(DOOR), copy = read(COPY);
  for (const code of ['email_already_registered', 'verify_email_first', 'register_failed']) {
    const sentence = src.match(new RegExp(`error: '([^']+)',\\s*code: '${code}'`))?.[1];
    assert.ok(sentence, `${DOOR} lost the ${code} sentence`);
    assert.ok(copy.includes(`${code}: s('${sentence}'`), `the portal copy for ${code} is missing or has drifted from the server sentence`);
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const PROBE = (tag) => `do $p$
declare lid bigint; tok uuid; n1 int; n2 int; second text := 'none'; found_id bigint; res jsonb;
begin
  insert into public.leads (company_name, email, source, invite_status, invited_at, tags)
  values ('ZZ DEMO S7 Check ${tag} Aluminium LLC', 'QD-${tag}-Lead7@Example.INVALID', 'directory', 'queued', now(), array['qd_demo','qd_run:${tag}'])
  returning id, claim_token into lid, tok;
  -- the OLD door: a second row for the address, typed in another case
  begin
    insert into public.leads (company_name, email, claimed, claimed_by, source)
    values ('ZZ DEMO S7 Check ${tag} Aluminium', 'qd-${tag}-lead7@example.invalid', true, 'qd-${tag}-lead7@example.invalid', 'self_registered');
    second := 'inserted';
  exception when unique_violation then second := substring(sqlerrm from '"([^"]+)"');
  end;
  -- the NEW door: the look-up (PostgREST .ilike on the escaped address), then one guarded claim per account
  select id into found_id from public.leads where email ilike 'qd-${tag}-lead7@example.invalid' limit 2;
  update public.leads set claimed = true, claimed_by = 'qd-${tag}-lead7@example.invalid', owner_email_verified = true,
         company_name = 'ZZ DEMO S7 Check ${tag} Aluminium', business_role = 'supplier', sector = 'aluminium', portal_updated_at = now()
   where id = found_id and claimed_by is null;
  get diagnostics n1 = row_count;
  update public.leads set claimed = true, claimed_by = 'qd-${tag}-other@example.invalid'
   where id = found_id and claimed_by is null;
  get diagnostics n2 = row_count;
  res := jsonb_build_object('second_row', second, 'found_original', found_id = lid, 'first_claim', n1, 'racing_claim', n2,
    'after', (select jsonb_build_object('rows', count(*), 'claimed_by', max(claimed_by), 'same_token', bool_and(claim_token = tok), 'demo', bool_and(is_demo))
                from public.leads where lower(email) = lower('qd-${tag}-lead7@example.invalid')));
  raise exception 'CHK<<%>>', res::text;
end $p$;`;

test('production, aborted: the old insert is refused, the new claim finds the invited row in any case and wins once', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { replaySql } = await import('../lib/safe_replay.mjs');
  const tag = 's7c' + Math.random().toString(36).slice(2, 8);
  let o = null;
  try { await replaySql(PROBE(tag), { label: 'the invited-listing claim probe' }); }
  catch (e) {
    const m = String(e.body || e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.body || e.message).slice(0, 600));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.second_row, 'uq_leads_email_lower', 'a second row for the invited address is no longer refused: ' + o.second_row);
  assert.equal(o.found_original, true, 'the look-up did not find the invited row typed in another case');
  assert.equal(o.first_claim, 1, 'the claim did not update the invited row');
  assert.equal(o.racing_claim, 0, 'a second account claimed the row the first one already holds');
  assert.deepEqual([o.after.rows, o.after.claimed_by, o.after.same_token, o.after.demo], [1, `qd-${tag}-lead7@example.invalid`, true, true]);
});
