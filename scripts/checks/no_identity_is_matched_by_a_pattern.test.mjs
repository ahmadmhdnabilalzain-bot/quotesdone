// no_identity_is_matched_by_a_pattern.test.mjs
// node --test scripts/checks/no_identity_is_matched_by_a_pattern.test.mjs
//
// Security audit 17 Nov 2026, finding 1 (it_engineer; docs/reports/2026-11-17-security-audit.md). sales_engineer and
// site_assistant found the signed-in caller's customer row with `.ilike('email', email)`, the e-mail unescaped: in a
// LIKE pattern `_` is any one character and `%` any run, so a supplier-portal login `john_smith@x.com` was the customer
// `john.smith@x.com` and read his conversations, PDFs and report. Escaping is not enough through PostgREST either: it
// rewrites every `*` of a like/ilike value to `%`, past any escape. An address is therefore matched in ONE place,
// supabase/functions/_shared/address_filter.ts (customerIdOf, claimedLeadIdOf, whereAddress, normalEmail).
//
// This check fails if any runtime file in supabase/functions or src/ (tests excluded):
//   1. calls `.like(` / `.ilike(` (or `.filter(col, 'like'|'ilike'|…)`, or `col.like.` / `col.ilike.` inside an or()
//      string) on an address column: email, claimed_by, from_email, to_email, cc, any `*_email`, `*_addr(ess)`,
//      or `sender*`. A constant pattern on such a column (`'%@example.invalid'`) is a pattern too: say it with eq/in, or
//      register it below with the reason;
//   2. the door stops escaping, stops refusing `*`, or customerIdOf / claimedLeadIdOf stop matching with `.eq`.
// A phone is matched by its last nine DIGITS on purpose (`.like('to_phone', '%' + tail)`, tail = digits only): a
// suffix of digits cannot hold a wildcard, and is not an address column here.
// Comments are stripped before matching, so the prose that quotes the old line never counts as one.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';

const REPO = join(import.meta.dirname, '..', '..');
const DOOR = 'supabase/functions/_shared/address_filter.ts';

// file -> number of address-column pattern reads it may keep, and why. Empty on 17 Nov 2026; a new entry needs a reason
// a reviewer can check (it is never a caller's or a sender's identity).
const REGISTERED = {};

function walk(dir) {
  const out = [];
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name.startsWith('.')) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (/\.(ts|tsx|mjs|js)$/.test(name) && !/\.(test|spec)\.(ts|tsx|mjs|js)$/.test(name) && !/\.fixtures?\.ts$/.test(name)) out.push(relative(REPO, p).split('\\').join('/'));
  }
  return out;
}

// A `//` starts a comment only when every quote before it on the line is closed (so 'https://…' is not a comment).
const stripComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').split('\n').map((l) => {
  for (let i = l.indexOf('//'); i >= 0; i = l.indexOf('//', i + 2)) {
    const before = l.slice(0, i);
    if ([`'`, '"', '`'].every((q) => (before.split(q).length - 1) % 2 === 0)) return before;
  }
  return l;
}).join('\n');

const COL = String.raw`(?:email|claimed_by|from_email|to_email|cc|[a-z_]*_email|[a-z_]*_addr(?:ess)?|sender[a-z_]*)`;
const PATTERNS = [
  new RegExp(String.raw`\.(?:i?like)\(\s*['"\`]` + COL + String.raw`['"\`]`, 'g'),
  new RegExp(String.raw`\.filter\(\s*['"\`]` + COL + String.raw`['"\`]\s*,\s*['"\`](?:not\.)?(?:i?like)(?:\(\w+\))?['"\`]`, 'g'),
  new RegExp(String.raw`(?:^|[,(\`'"])` + COL + String.raw`\.(?:not\.)?i?like(?:\(\w+\))?\.`, 'gm'),
];
export const patternReads = (src) => PATTERNS.reduce((n, re) => n + (stripComments(src).match(re) || []).length, 0);

const FILES = [...walk(join(REPO, 'supabase', 'functions')), ...walk(join(REPO, 'src'))];

test('the walk found the functions, the two doors that once matched by pattern, and the address door', () => {
  assert.ok(FILES.length > 300, `walked ${FILES.length} runtime files`);
  for (const f of [DOOR, 'supabase/functions/sales_engineer/lib/caller.ts', 'supabase/functions/site_assistant/index.ts']) assert.ok(FILES.includes(f), f);
});

test('the matcher sees the old line and its variants, and not prose, eq, or a phone suffix', () => {
  assert.equal(patternReads(`await admin.from('customers').select('id').ilike('email', email).maybeSingle();`), 1);
  assert.equal(patternReads(`q.like("claimed_by", x)`), 1);
  assert.equal(patternReads("q.ilike(`to_email`, x)"), 1);
  assert.equal(patternReads(`q.ilike('from_email', '%' + esc + '%')`), 1);
  assert.equal(patternReads(`q.filter('email', 'ilike', x)`), 1);
  assert.equal(patternReads("q.or(`email.ilike.${a},claimed_by.ilike.${a}`)"), 2);
  assert.equal(patternReads(`q.or('owner_email.not.ilike.%x%')`), 1);
  assert.equal(patternReads(`// was .ilike('email', email)\nq.eq('email', e)`), 0);
  assert.equal(patternReads(`q.eq('email', e).like('to_phone', '%' + tail).ilike('subject', '%undeliver%')`), 0);
  assert.equal(patternReads(`q.like('provider_email_id', 'm365:%')`), 0);
  assert.equal(patternReads("q.or(`email_domain.ilike.${dom},domain.ilike.${dom}`)"), 0);
});

test('no runtime file matches an address by a pattern (use _shared/address_filter.ts)', () => {
  const found = [];
  for (const f of FILES) {
    if (f === DOOR) continue;
    const n = patternReads(readFileSync(join(REPO, f), 'utf8'));
    const allowed = REGISTERED[f]?.reads ?? 0;
    if (n !== allowed) found.push(`${f}: ${n} address pattern read(s)${allowed ? `, ${allowed} registered` : ''}`);
  }
  for (const f of Object.keys(REGISTERED)) if (!FILES.includes(f)) found.push(`${f}: registered but gone (the register must not point at nothing)`);
  assert.deepEqual(found, [], 'an address matched with like/ilike is a wildcard waiting for `_`, `%` or `*`:\n' + found.join('\n'));
});

test('the door stays a door: exact reads, escaped literals, and `*` refused', () => {
  const src = stripComments(readFileSync(join(REPO, DOOR), 'utf8'));
  assert.match(src, /export function customerIdOf[\s\S]*?\.from\('customers'\)\.select\('id'\)\.eq\('email', e\)/);
  assert.match(src, /export function claimedLeadIdOf[\s\S]*?\.from\('leads'\)\.select\('id'\)\.eq\('claimed_by', e\)/);
  assert.match(src, /if \(s\.includes\('\*'\)\) return null;/);
  assert.match(src, /replace\(\/\[\\\\%_\]\/g/);
  for (const f of ['supabase/functions/sales_engineer/lib/caller.ts', 'supabase/functions/site_assistant/index.ts']) {
    assert.match(stripComments(readFileSync(join(REPO, f), 'utf8')), /customerIdOf\(admin, email\)/, `${f} resolves its caller through the door`);
  }
});
