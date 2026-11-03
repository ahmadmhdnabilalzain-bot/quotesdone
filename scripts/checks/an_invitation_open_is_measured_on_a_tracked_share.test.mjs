// AN INVITATION OPEN IS MEASURED, ON A TRACKED SHARE, AND THE PRIVACY POLICY SAYS SO (marketing, 3 Nov 2026).
//
//   node --test scripts/checks/an_invitation_open_is_measured_on_a_tracked_share.test.mjs
//
// The founder (3 Nov 2026): "I want us to know when someone opened our invitation email." That changes the no-link ruling
// (founder_instruction 1301, "safer to not send links") for a share of the invitations only, so this check holds the
// containment in the repository (the MIME itself: supabase/functions/send_outbox/open_tracking.test.ts; the routines on
// fixtures: scripts/sql/an_invitation_open_is_measured_on_a_tracked_share_and_reaches_the_ceo_probe.sql). Fails if:
//   1. the Privacy Policy stops saying, in both languages, that invitation opens are measured and that the address itself
//      is never kept; or 1.9 differs from 1.8 by anything but the label, the notice and that sentence (undoing the edits
//      must reproduce the live 1.8 registry hash b16a707f...); or its registry SQL is not the page's text; or the word AI
//      appears in it;
//   2. the open tables lose RLS, their deny-all policy, their revoke or their export row; a new routine is not revoked
//      from public, anon and authenticated; the switch seed overwrites a value someone set; or the SQL is not in the
//      MANIFEST (privacy first) with its probe carrying a pending note;
//   3. the pixel route answers anything but a no-store GIF, records a malformed token, records on HEAD, or stores or
//      echoes the address; or it is served on a path other than the one send_outbox writes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { EDITS_1_9, OPEN_SENTENCE, privacyAt18, registryBody } from '../lib/privacy_1_9.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const sha = (s) => createHash('sha256').update(s, 'utf8').digest('hex');
const legal = JSON.parse(read('src/content/legal.json'));
const facts = JSON.parse(read('src/content/company_facts.json'));
const OPEN_SQL = 'scripts/sql/an_invitation_open_is_measured_on_a_tracked_share_and_reaches_the_ceo.sql';
const PROBE_SQL = 'scripts/sql/an_invitation_open_is_measured_on_a_tracked_share_and_reaches_the_ceo_probe.sql';
const PRIV_SQL = 'scripts/sql/the_privacy_policy_1_9_says_we_measure_invitation_opens.sql';
const ROUTE = 'src/app/u/o/[token]/route.ts';
const code = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

test('privacy 1.9 says, in both languages, that invitation opens are measured and the address itself is never kept', () => {
  assert.deepEqual(facts.documents.privacy, { version: '1.9', date: '2026-11-03' });
  const en = legal.privacy.en.html, ar = legal.privacy.ar.html;
  assert.ok(en.includes('Version 1.9 · Last updated 3 November 2026') && ar.includes('الإصدار 1.9 · آخر تحديث 3 نوفمبر 2026'));
  // the sentence sits in section 9's "Invitations to businesses" paragraph, just before "We use this data for nothing else"
  const para = (h, start, end) => h.slice(h.indexOf(start), h.indexOf(end, h.indexOf(start)));
  assert.ok(para(en, '<strong>Invitations to businesses.</strong>', '</p>').includes(OPEN_SENTENCE.en.trim() + ' We use this data for nothing else'));
  assert.ok(para(ar, '<strong>دعوة الشركات.</strong>', '</p>').includes(OPEN_SENTENCE.ar.trim() + ' ولا نستخدم هذه البيانات'));
  assert.match(OPEN_SENTENCE.en, /never the address itself/);
  assert.match(OPEN_SENTENCE.ar, /ولا نحتفظ بالعنوان نفسه/);
  for (const h of [en, ar]) {
    assert.doesNotMatch(h, /\bAI\b|ذكاء اصطناعي|الذكاء الاصطناعي/, 'never the word AI in a public legal text');
    assert.doesNotMatch(h, /50[ .-]?931[ .-]?9355/);
  }
  // the Arabic is written, not translated: none of the calques scripts/checks/every_arabic_message_is_written_not_translated lists
  for (const [, to] of EDITS_1_9.ar) assert.doesNotMatch(to, /سوف يتم|قد تم|من قبل |يرجى ملاحظة|[؀-ۿ][,;?]|كوتس/);
});

test('1.9 is 1.8 plus exactly the label, the notice and the one sentence; the registry SQL is the page', () => {
  for (const g of ['en', 'ar']) {
    const back = privacyAt18(legal.privacy[g].html, g);   // throws if an edit is missing or doubled
    assert.ok(back.includes(g === 'en' ? 'Version 1.8 · Last updated 2 November 2026' : 'الإصدار 1.8 · آخر تحديث 2 نوفمبر 2026'));
  }
  assert.equal(sha(registryBody(privacyAt18(legal.privacy.en.html, 'en'))), 'b16a707f2ede426ca37ac7f87136b314a17c674f17a8ac6614ec26b1fe93e5e9',
    'undoing the 1.9 edits no longer gives the live 1.8 registry text');
  const sql = read(PRIV_SQL);
  const body = registryBody(legal.privacy.en.html);
  const m = /\$qd_privacy\$([\s\S]*?)\$qd_privacy\$, version = '1\.9', effective_date = date '2026-11-03',\s+content_sha256 = '([0-9a-f]{64})'/.exec(sql);
  assert.ok(m, 'the registry update is not in ' + PRIV_SQL);
  assert.equal(m[1], body, 'the registry body is not the English page');
  assert.equal(m[2], sha(body));
  assert.match(sql, /where slug = 'privacy' and version = '1\.8';/);
  assert.match(sql, /where d\.slug = 'privacy' and d\.version = '1\.8'\s+on conflict \(slug\) do nothing;/, '1.8 is not archived before it is replaced');
  assert.doesNotMatch(code(sql), /\b(begin|commit)\s*;/i);
  assert.match(sql, /PROBE OK/);
});

test('the open tables are service-role only and exported; every new routine is revoked; the switch seed never overwrites', () => {
  const sql = code(read(OPEN_SQL));
  for (const t of ['email_open_token', 'email_open_event']) {
    assert.match(sql, new RegExp(`alter table public\\.${t} enable row level security;`));
    assert.match(sql, new RegExp(`create policy ${t}_service_role_only on public\\.${t} as permissive for all to public using \\(false\\) with check \\(false\\);`));
    assert.match(sql, new RegExp(`revoke all on public\\.${t} from anon, authenticated;`));
    assert.match(sql, new RegExp(`\\('${t}', true, 'marketing', '`), `${t} has no table_export_registry row`);
  }
  assert.doesNotMatch(sql, /\bip\s+inet\b|\braw_ip\b|\bip_address\b/i, 'a column that could hold the raw address');
  const created = [...sql.matchAll(/create or replace function public\.(fn_[a-z_]+)\(/g)].map((x) => x[1])
    .filter((f) => !['fn_marketing_report_figures', 'fn_ceo_seat_board'].includes(f));
  assert.equal(created.length, 9);
  for (const f of created) assert.match(sql, new RegExp(`revoke execute on function public\\.${f}\\([^)]*\\) from public, anon, authenticated;`), `${f} is not revoked`);
  for (const f of created) assert.match(sql, new RegExp(`function public\\.${f}\\([\\s\\S]*?set search_path to 'public', 'pg_temp'`), `${f} has no pinned search_path`);
  assert.match(sql, /values \('invite_open_tracking', '20', now\(\)\) on conflict \(key\) do nothing;/);
  assert.match(sql, /'email_open_ip_salt', encode\(extensions\.gen_random_bytes\(32\), 'hex'\), now\(\)\)\s+on conflict \(key\) do nothing;/);
  // the token is random, never derived from the address or the lead
  assert.match(sql, /values \(replace\(gen_random_uuid\(\)::text, '-', ''\), n\.id, n\.lead_id, v_share\)/);
  // the report and the board carry it
  assert.match(sql, /'invitation_opens', v_opens\),/);
  assert.match(sql, /'invitation_opens',\s+public\.fn_invite_open_summary\(v_from, now\(\)\)\)/);
  assert.doesNotMatch(sql, /\b(begin|commit)\s*;/i);
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim());
  assert.ok(manifest.indexOf(PRIV_SQL) >= 0 && manifest.indexOf(PRIV_SQL) < manifest.indexOf(OPEN_SQL), 'both files in the MANIFEST, privacy first');
  assert.ok(!manifest.includes(PROBE_SQL), 'the probe is never applied');
  assert.ok(read(PROBE_SQL.replace('scripts/sql/', 'scripts/sql/pending/').replace(/\.sql$/, '.txt')).trim());
  assert.match(read(PROBE_SQL), /raise exception 'CHK<<%>>'/);
});

test('the pixel route answers a no-store GIF, records only a 32-hex token, never on HEAD, and never keeps the address', () => {
  assert.ok(existsSync(join(ROOT, ROUTE)));
  const src = read(ROUTE);
  const get = /export async function GET[\s\S]*?\n\}/.exec(src)?.[0] || '';
  const head = /export async function HEAD[\s\S]*?\n\}/.exec(src)?.[0] || '';
  assert.match(src, /'Content-Type': 'image\/gif'/);
  assert.match(src, /'Cache-Control': 'no-store/);
  assert.match(src, /const TOKEN = \/\^\[0-9a-f\]\{32\}\$\/;/);
  assert.match(get, /if \(TOKEN\.test\(token\) && key && SUPA_URL\)/);
  assert.match(get, /rpc\/fn_email_open_record/);
  assert.match(get, /return gif\(\);/);
  assert.doesNotMatch(head, /fetch|rpc/, 'HEAD must record nothing');
  assert.doesNotMatch(src, /console\.|writeFile|createClient|\/rest\/v1\/(?!rpc\/fn_email_open_record)/, 'the route logs or stores nothing itself');
  assert.match(src, /new Response\(new Uint8Array\(GIF\)/);
  assert.equal(Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', 'base64').subarray(0, 6).toString(), 'GIF89a');
  // the path send_outbox writes is the path this route serves
  assert.match(read('supabase/functions/send_outbox/open_tracking.ts'), /export const OPEN_PATH = '\/u\/o\/';/);
  assert.match(read('src/middleware.ts'), /matcher: \[/);
  assert.doesNotMatch(/matcher: \[([\s\S]*?)\]/.exec(read('src/middleware.ts'))[1], /'\/u[/']/, 'locale or UAE redirects would reach the pixel');
});
