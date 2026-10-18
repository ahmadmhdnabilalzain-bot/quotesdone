// Founder ruling 1181 (12 Oct 2026): an unfinished sign-up is never a customer. And one acceptance, one certificate.
// Owner: it_engineer (the purge), customer_support (the sign-up it protects).
//
// What this keeps from coming back:
//   1. A customer row lived 17 days with e-mail verified, mobile not, terms never accepted, and the activation duty
//      e-mailed him "Your first request on QuotesDone". The purge removes an unfinished sign-up after 30 minutes,
//      guarded on the COMPLETION FIELDS (never on time alone), and never a customer with a request or a sale.
//   2. An invited lead is campaign data: an unfinished claim returns it to the pool, it is never deleted.
//   3. Its files go too ("as if he didn't even try"; policy 1.6 "deleted in full"): the Dropbox copies the purge LISTED,
//      their backup records and its storage objects, through the Dropbox and storage APIs. No other Dropbox delete exists.
//   4. One customer got two certificates 52 s apart for one acceptance: kyc rewrote tos_accepted_at on a second
//      accept_terms for the same version. It now writes the acceptance only when that version is not on file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const src = (p) => readFileSync(join(ROOT, p), 'utf8');
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const SQL = code(src('scripts/sql/an_unfinished_sign_up_is_never_a_customer.sql'));
const body = SQL.slice(SQL.indexOf('function public.fn_unfinished_signup_purge'), SQL.indexOf('revoke execute on function public.fn_unfinished_signup_purge'));

test('the purge skips a complete sign-up before it looks at the clock, and gives each one its 30 minutes', () => {
  const loops = body.split(/\n\s*for c in/).slice(1);
  assert.equal(loops.length, 2, 'one loop for customers, one for suppliers');
  for (const l of loops) {
    const complete = l.indexOf('continue when cardinality(c.missing) = 0;');
    const clock = l.indexOf("continue when c.started > now() - interval '30 minutes';");
    assert.ok(complete > 0 && clock > complete, 'completion first, then the 30 minutes');
    for (const f of ['email', 'mobile', 'terms', 'terms_ip']) assert.ok(l.includes(`then '${f}' end`), `completion includes ${f}`);
  }
  assert.match(body, /if c\.busy then n_held/, 'a customer or company with a request, a quote or a sale is held, not removed');
});

test('an invited lead returns to the pool; only a self-registered company is deleted', () => {
  const sup = body.slice(body.lastIndexOf('for c in'));
  const inv = sup.slice(sup.indexOf('if c.invited then'), sup.indexOf('else', sup.indexOf('if c.invited then')));
  assert.match(inv, /update public\.leads l set claimed = false, claimed_by = null/, 'the invited lead is unclaimed');
  assert.ok(!/delete from public\.leads/.test(inv), 'the invited lead is never deleted');
});

test('an unfinished sign-up files are deleted: only the Dropbox copies the purge listed, their records, and its storage objects', () => {
  const h = SQL.slice(SQL.indexOf('function public.fn_signup_purge_backups'), SQL.indexOf('revoke execute on function public.fn_signup_purge_backups'));
  assert.ok(h.includes('insert into public.signup_purge_dropbox'), 'the Dropbox copies to delete are listed by the purge');
  assert.ok(body.includes("public.fn_signup_purge_backups(v_id, 'customer'") && body.includes("public.fn_signup_purge_backups(v_id, 'supplier'"), 'both roles list their backups');
  assert.ok(!body.includes('delete from storage.objects'), 'no storage row is deleted in SQL (the storage API removes the object)');
  const d = src('supabase/functions/dropbox_backup/index.ts');
  const a = d.slice(d.indexOf('async function purgeUnfinishedSignups'), d.indexOf("Deno.serve(observe('dropbox_backup'"));
  assert.ok(a.includes("from('signup_purge_dropbox')") && a.includes('signupPurgeDeleteAllowed(String(c.dropbox_file))'), 'only a listed copy inside the entity tree is deleted');
  assert.ok(a.includes(".eq('status', 'signup_purge_pending')"), 'only the record the purge marked is deleted');
  assert.ok(a.includes('admin.storage.from(o.bucket).remove([o.path])'), 'storage objects are removed through the storage API');
  assert.ok(a.includes("kind: 'signup_purge'") && !/email|full_name|company_name/.test(a.slice(a.indexOf("from('agent_actions')"))), 'counts only are logged in agent_actions');
  // the delete is reachable only from here: every other delete_v2 is the export prune, a probe, or the sandbox
  const deletes = d.split('files/delete_v2').length - 1;
  assert.equal(deletes, 5, 'a new Dropbox delete was added outside the unfinished sign-up purge: ' + deletes);
});

test('the job runs every 5 minutes and names its seat', () => {
  assert.match(SQL, /cron\.schedule\('unfinished_signup_purge', '\*\/5 \* \* \* \*'/);
  assert.match(SQL, /\('cron_job', 'unfinished_signup_purge', 'it_engineer'/);
});

test('a second accept_terms for the version on file does not write a second acceptance', () => {
  const k = src('supabase/functions/kyc/index.ts');
  const i = k.indexOf("await admin.from('customers').update({ tos_accepted_at: nowIso");
  const guard = k.slice(Math.max(0, i - 400), i);
  assert.match(guard, /if \(!\(cust as any\)\?\.tos_accepted_at \|\| \(cust as any\)\?\.tos_version !== custV\) \{/,
    'the customer acceptance is written only when the current version is not already accepted');
});

test('the customer register lists customers with the IP, the accepted version and the time, and is rebuilt when one goes', () => {
  const a = src('supabase/functions/compliance_archive/index.ts');
  assert.match(a, /\.not\('tos_accepted_at', 'is', null\)/, 'only a sign-up that accepted the terms is a customer');
  for (const h of ["'Terms version'", "'Terms accepted (UTC)'", "'IP address'"]) assert.ok(a.includes(h), 'the register has a column ' + h);
  assert.match(body, /'action', 'register'/, 'the purge rebuilds the register when a customer row went');
});

test('the supplier folder is the primary category SLUG, and the one catch-all is "uncategorized"', () => {
  const s = code(src('scripts/sql/the_supplier_folder_is_the_category_slug.sql'));
  assert.ok(!/select c\.name\b/.test(s), 'no category NAME is a folder');
  assert.match(s, /'uncategorized'\)\);/, 'one honest folder for a supplier with no category');
});

test('release review: what holds a sign-up, the phone never selects, and a login shared with a complete or held account stays', () => {
  const held = (name) => SQL.slice(SQL.indexOf('function public.' + name), SQL.indexOf('revoke execute on function public.' + name));
  const ch = held('fn_signup_customer_held'), sh = held('fn_signup_supplier_held');
  for (const c of ['cu.signed_terms_path is not null', 'public.inquiry_intake ii', 'm.customer_id = cu.id', 'lower(im.from_email) = lower(cu.email)', 'public.inquiries i'])
    assert.ok(ch.includes(c), 'a customer is held when ' + c);
  for (const c of ['im.supplier_id = l.id', 'l.signed_terms_path is not null', 'public.quotes q']) assert.ok(sh.includes(c), 'a supplier is held when ' + c);
  // an upload does NOT hold a sign-up (founder ruling 1181): it is deleted with it
  for (const h of [ch, sh]) assert.ok(!h.includes('storage.objects') && !h.includes('public.doc_backups'), 'an upload alone never holds a sign-up');
  assert.ok(body.includes('public.fn_signup_customer_held(cu.id) busy') && body.includes('public.fn_signup_supplier_held(l.id) busy'), 'both loops hold through the functions');
  assert.ok(!body.includes('to_phone') && !body.includes('p.phone'), 'nothing is matched on the unverified mobile');
  const kept = held('fn_signup_email_kept_elsewhere');
  assert.ok(kept.includes('public.fn_signup_supplier_held(l.id)') && kept.includes('public.fn_signup_customer_held(c.id)'), 'a HELD account in the other role keeps the login');
  assert.equal(body.split('delete from auth.users').length - 1, body.split('v_keep := public.fn_signup_email_kept_elsewhere(').length - 1,
    'every login removal is behind the cross-role check (its order is asserted in the round-3 test)');
  assert.equal((body.match(/else v_n := 0; end if;/g) || []).length, 2, 'a kept login counts 0 removed, never the previous statement');
});

test('release review round 3: mail and OTPs go only with the login; an invited lead keeps its campaign mail; another company of the owner keeps it', () => {
  const loops = body.split(/\n\s*for c in/).slice(1);
  for (const l of loops) {
    const keep = l.indexOf('v_keep := public.fn_signup_email_kept_elsewhere(');
    for (const del of ['delete from public.notifications', 'delete from public.email_verifications', 'delete from public.phone_verifications', 'delete from auth.users']) {
      const at = l.indexOf(del);
      assert.ok(keep > 0 && at > keep, del + ' only after the kept-elsewhere decision');
      assert.ok(l.lastIndexOf('if not v_keep then', at) > keep, del + ' only inside a not-kept branch');
    }
  }
  const sup = loops[1];
  assert.ok(sup.includes("public.fn_signup_email_kept_elsewhere(v_email, 'supplier', c.id)"), 'the owner\'s other companies are checked');
  const i = sup.indexOf('delete from public.notifications');
  assert.ok(sup.lastIndexOf('if not c.invited then', i) > sup.lastIndexOf('if not v_keep then', i), 'an invited lead\'s campaign mail is never deleted');
});

test('release review round 4: no upload in flight survives a purge, no bad row blocks the rest, an invited lead loses its sign-up files', () => {
  const r = src('supabase/functions/dropbox_backup/row.ts');
  assert.equal((r.match(/\.eq\('id', row\.id\)(?!\.eq\('status', 'processing'\))/g) || []).length, 0, 'every uploader write is conditional on its claim (status processing)');
  const d = src('supabase/functions/dropbox_backup/index.ts');
  const p = d.slice(d.indexOf('async function purgeUnfinishedSignups'), d.indexOf("Deno.serve(observe('dropbox_backup'"));
  assert.ok(p.includes(".lt('attempts', 5)") && p.includes(".lt('listed_at',"), 'a listing waits 15 minutes and stops after 5 attempts');
  assert.ok(p.includes("attempts: 5 }"), 'a refusal is terminal');
  const h = SQL.slice(SQL.indexOf('function public.fn_signup_purge_backups'), SQL.indexOf('revoke execute on function public.fn_signup_purge_backups'));
  assert.ok(!h.includes('delete from public.doc_backups') && !/d\.status in \(/.test(h), 'every record of the entity is listed, whatever its status; none is deleted in SQL');
  const inv = body.slice(body.indexOf('if c.invited then'), body.indexOf("'lead', 'removed'"));
  assert.ok(inv.includes("public.fn_signup_purge_backups(v_id, 'supplier', c.id::text)") && inv.includes("o.bucket_id = 'supplier-docs'"), 'an invited lead loses the sign-up files');
});
