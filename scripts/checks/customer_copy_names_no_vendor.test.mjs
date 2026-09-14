// WHAT A CUSTOMER READS NEVER NAMES OUR STORAGE OR DATABASE VENDOR.
//
// The founder, 14 Sep 2026 (public.founder_instruction 197): the two infrastructure vendors must not
// appear in anything a customer or supplier reads. Measured that day: the public FAQ named the
// document-storage vendor 14 times across EN and AR, including a whole question about it, a list of
// every vendor under "Which APIs are available?", and a claim that it synced "every 15 minutes".
// The same wording sat in seven public company_faq rows the website widget answers from.
// scripts/sql/customers_are_not_told_we_keep_copies_or_which_vendors_we_use.sql removed them.
//
// This check reads the customer-facing copy and fails on either vendor name. The pattern is built
// from pieces below so that this comment, and the explanation in the SQL file, cannot match it.
// Comments in .ts files are stripped first: code comments are for engineers, not customers.
//
//   A. files: the site content JSON and the portal strings.
//   B. the database, when a management token is present: every row the widget may answer from
//      (v_support_corpus where is_public) and the message templates. Without a token it is skipped
//      and says so; CI's checks job has no token.
//
//   node --test scripts/checks/customer_copy_names_no_vendor.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const VENDOR = new RegExp(['drop' + 'box', 'supa' + 'base'].join('|'), 'i');
const VENDOR_SQL = ['drop' + 'box', 'supa' + 'base'].join('|');

// Customer-facing copy only. legal.json is deliberately absent: the Privacy Policy and Terms are
// versioned documents with acceptance records, and changing them is the founder's decision.
const FILES = [
  'src/content/marketing.json',
  'src/content/services.json',
  'src/content/company.json',
  'src/content/categories.json',
  'src/components/me/portalText.ts',
];

const stripComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

test('customer-facing files name no infrastructure vendor', () => {
  const hits = [];
  for (const rel of FILES) {
    const full = path.join(REPO, rel);
    assert.ok(existsSync(full), `${rel} is missing — update FILES if it moved`);
    let text = readFileSync(full, 'utf8');
    if (rel.endsWith('.ts')) text = stripComments(text);
    text.split('\n').forEach((line, i) => {
      const m = line.match(VENDOR);
      if (m) hits.push(`${rel}:${i + 1}: …${line.slice(Math.max(0, m.index - 60), m.index + 60)}…`);
    });
  }
  assert.deepEqual(hits, [], 'vendor named in customer copy:\n' + hits.join('\n'));
});

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

test('rows the widget and templates answer from name no infrastructure vendor', { skip: !token && 'no management token' }, async () => {
  const query = `
    select 'corpus:' || src || '/' || src_id as k from public.v_support_corpus
     where is_public and (coalesce(title,'') || ' ' || content) ~* '(${VENDOR_SQL})'
    union all select 'response_template:' || key from public.response_template where body ~* '(${VENDOR_SQL})'
    union all select 'messaging_template:' || template_key from public.messaging_template t where t::text ~* '(${VENDOR_SQL})'`;
  const r = await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const body = await r.text();
  assert.ok(r.ok, `query failed: ${r.status} ${body}`);
  const rows = JSON.parse(body);
  assert.deepEqual(rows.map((x) => x.k), [], 'vendor named in rows a customer can be answered from');
});
