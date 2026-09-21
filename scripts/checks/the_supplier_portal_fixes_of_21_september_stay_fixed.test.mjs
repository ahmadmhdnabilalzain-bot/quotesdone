// THE SUPPLIER-PORTAL FIXES OF 21 SEP 2026 STAY FIXED (sales_engineer; supplier audit findings 7, 25, 26,
// 27, 30, 36, 37) — the causes a source reading can see. Behaviour is proved beside the code:
// supabase/functions/_shared/quote_documents.test.ts (job number on every document, the Arabic inquiry BOQ),
// supabase/functions/supplier_api/quote_review.test.ts (job number in the review, Arabic acknowledgements),
// supabase/functions/_shared/boq_arabic.test.ts (the BOQ vocabulary), and two verdict-row probes in
// scripts/sql/ (the notice reference and the emirate gate, against the live database).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const read = (...p) => readFileSync(join(ROOT, ...p), 'utf8');
const walk = (d, ok) => readdirSync(d).flatMap((n) => {
  const p = join(d, n);
  return statSync(p).isDirectory() ? (n === 'node_modules' ? [] : walk(p, ok)) : (ok(n) ? [p] : []);
});
// Comments are blanked so a comment that DESCRIBES the old shape cannot fail (or pass) the check.
const code = (s) => s.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, (m) => m.replace(/[^\n]/g, ' '));

test('finding 7: no edge function or portal page makes a job number out of a uuid prefix', () => {
  // Supplier saw D958E1EA, customer saw 151767 for one job. The one job number is inquiries.rfq_no, read
  // through jobNoOf (_shared/quote_documents.ts) — the only place allowed to hold the uuid fallback.
  const files = [...walk(join(ROOT, 'supabase', 'functions'), (n) => n.endsWith('.ts') && !n.includes('.test.') && !n.includes('.fixture.')),
                 ...walk(join(ROOT, 'src'), (n) => /\.tsx?$/.test(n))];
  const found = [];
  for (const p of files) {
    const rel = p.slice(ROOT.length).replace(/\\/g, '/');
    const lines = code(readFileSync(p, 'utf8')).split('\n');
    lines.forEach((l, i) => {
      if (/slice\(0,\s*8\)\s*\.toUpperCase\(\)/.test(l) && !(rel.endsWith('_shared/quote_documents.ts') && /export const jobNoOf/.test(lines[i - 1] || ''))) found.push(`${rel}:${i + 1}`);
    });
  }
  assert.deepEqual(found, [], 'read the job number through jobNoOf / jobNo (inquiries.rfq_no)');
});

test('finding 7: quoteRef and jobNo take the inquiry (with rfq_no), not a bare id', () => {
  const qd = code(read('supabase', 'functions', '_shared', 'quote_documents.ts'));
  assert.match(qd, /export function quoteRef\(inq: \{[^}]*rfq_no/);
  assert.doesNotMatch(qd, /quoteRef\((?:i|inq)\.id\b/);
  const qr = code(read('supabase', 'functions', 'supplier_api', 'quote_review.ts'));
  assert.match(qr, /export const jobNo = [\s\S]{0,200}jobNoOf\(/, 'jobNo must delegate to the one reader');
  for (const f of [['supabase', 'functions', 'supplier_api', 'index.ts'], ['supabase', 'functions', 'customer_api', 'index.ts']]) {
    assert.doesNotMatch(code(read(...f)), /quoteRef\(\s*(?:String\()?[a-z_.]*(?:inquiry_id|iid)\b/, `${f.join('/')}: quoteRef is handed the inquiry row`);
  }
});

test('finding 7: the notice trigger file prints the job number, not the uuid prefix', () => {
  const s = read('scripts', 'sql', 'one_job_number_on_every_portal_document_and_notice.sql');
  const body = s.slice(s.indexOf('create or replace function public.fn_notifications_speak_the_recipients_language'));
  assert.match(body, /'QD-' \|\| public\.fn_job_no\(new\.inquiry_id\)/);
  assert.doesNotMatch(body.replace(/--[^\n]*/g, ''), /left\(replace\(new\.inquiry_id/);
});

test('finding 25: the canonical matcher honours a stated emirate limit', () => {
  const m = read('scripts', 'sql', 'MANIFEST.txt') + '\n' + read('scripts', 'sql', 'PENDING.txt');
  const files = m.split('\n').map((l) => l.split(' :: ')[0].trim()).filter((l) => /^scripts\/sql\/.+\.sql$/.test(l));
  const defs = files.filter((f) => { try { return /create or replace function public\.fn_match_capability\(/i.test(read(f)); } catch { return false; } });
  const last = read(defs[defs.length - 1]).replace(/--[^\n]*/g, '');
  assert.match(last, /cardinality\(loc\.stated\) = 0/, `${defs[defs.length - 1]}: no stated limit = UAE-wide`);
  assert.match(last, /exists \(select 1 from unnest\(loc\.stated\) e where e ilike p_emirate\)\)/, 'a stated limit is a GATE, not only a tie-break');
});

test('finding 30: asking the customer stays open after a quote exists', () => {
  const t = code(read('src', 'components', 'portal', 'supplier', 'InquiriesTab.tsx'));
  const m = t.match(/<ClarifyThread[^>]*canAsk=\{([^}]*)\}/);
  assert.ok(m, 'ClarifyThread is rendered on the inquiry');
  assert.doesNotMatch(m[1], /\bq\b|\.quotes?\b/,'canAsk must not depend on whether a quote exists');
});

test('finding 36: a message is placed and labelled by who is reading, and a supplier message marks contact', () => {
  const cc = code(read('src', 'components', 'portal', 'comms', 'CommunicationCenter.tsx'));
  assert.match(cc, /const me = data\?\.role/);
  // The supplier chat (ConversationView). The customer's own WhatsApp/e-mail channel view is customer-only
  // by construction and keeps its fixed 'customer' side.
  assert.match(cc, /m\.sender === me \? w\.you : thread\.counterpart/, 'the supplier-chat label follows the reader');
  const api = code(read('supabase', 'functions', 'messages_api', 'index.ts'));
  assert.match(api, /role === 'supplier'[\s\S]{0,200}supplier_ack_at/, 'sending as the supplier records the contact');
});

test('finding 26/27: the Arabic BOQ reads the sales engineer vocabulary and its description column has a width', () => {
  const rfq = code(read('src', 'components', 'portal', 'supplier', 'RfqParts.tsx'));
  assert.match(rfq, /r\.description_ar/);
  assert.match(rfq, /r\.section_ar/);
  assert.match(rfq, /<th scope="col" className="[^"]*min-w-\[[^"]*">\{ar \? 'الوصف'/, 'the description column keeps a minimum width in RTL');
  const api = code(read('supabase', 'functions', 'supplier_api', 'index.ts'));
  assert.match(api, /boqWithArabic\(/);
  const qd = code(read('supabase', 'functions', '_shared', 'quote_documents.ts'));
  assert.match(qd, /r\.description_ar/, 'the inquiry PDF prints the Arabic description on an Arabic page');
  for (const f of ['InquiriesTab.tsx', 'QuotationsTab.tsx']) {
    assert.doesNotMatch(code(read('src', 'components', 'portal', 'supplier', f)), /'AED ' \+/, `${f}: prices go through aedIn(lang, …)`);
  }
});
