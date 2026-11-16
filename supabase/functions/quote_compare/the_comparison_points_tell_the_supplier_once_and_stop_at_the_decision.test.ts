// quote_compare/the_comparison_points_tell_the_supplier_once_and_stop_at_the_decision.test.ts — the two gaps the COMPARE3
// hand-back left open on the comparison's points (sales_engineer builder COMPARE4, 15 Nov 2026). Seat: sales_engineer.
//   1. A supplier who already SUBMITTED is told ONCE that the sales engineer has a question about his quotation, through the
//      estate's supplier notice path (customer_support's delivery door, English only, the address checked, one key per quote
//      and point set) and its WhatsApp template; never the customer, never the points' text.
//   2. When the customer reveals any supplier or the request is concluded, every open point and its hand-over close as
//      superseded with the reason, a queued notice is cancelled, and nothing is asked or promised after that.
// The SQL is EXECUTED by scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer_probe.sql on the local
// Postgres 16 (never production); these tests hold the file's shape and the customer's page to it.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/quote_compare/the_comparison_points_tell_the_supplier_once_and_stop_at_the_decision.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { INQUIRY_A, journeyA, SUPPLIER_NAMES } from '../_shared/request_fit.journey_a.fixture.ts';
import { enforceFit, pointsHandoff, withAnswers } from '../_shared/request_fit.ts';
import { compareDocument } from '../_shared/quote_documents.ts';
import { CLOSED_REQUEST_STATUSES } from '../_shared/request_closed.ts';
import { tmplKey } from '../send_whatsapp/templates.ts';

const SQL = Deno.readTextFileSync(new URL('../../../scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer.sql', import.meta.url));
const PROBE = Deno.readTextFileSync(new URL('../../../scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer_probe.sql', import.meta.url));
const INDEX = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
/** The body of one routine in the file, comments stripped (a check that greps source must not match its own comment). */
const body = (name: string) => {
  const at = SQL.indexOf('function public.' + name + '(');
  assert(at >= 0, name + ' is not defined');
  const start = SQL.indexOf('$fn$', at); const end = SQL.indexOf('$fn$', start + 4);
  return SQL.slice(start, end).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
};

Deno.test('1. the notice: customer_support\'s door, requested by the sales engineer, to the supplier, in English, once per quote and point set', () => {
  const n = body('fn_sales_engineer_comparison_points_notice');
  assertMatch(n, /fn_customer_support_takes_delivery\(/);
  for (const kv of ["'type', 'quote_comparison_points'", "'requested_by', 'sales_engineer'", "'to_role', 'supplier'", "'lang', 'en'", "'channel', 'email'", "'dedupe_key', v_key"]) {
    assert(n.includes(kv), kv);
  }
  // the address is checked as every seat clock checks it (suppression, unsubscribe, dead domain, fixture/real), and a key
  // already asked is refused: one notice per quote per point set, never repeated
  assertMatch(n, /fn_seat_clock_refusal\(public\.fn_inquiry_is_demo\(v_inquiry\), v_to, 'quote_comparison_points'\)/);
  assertMatch(n, /fn_seat_clock_asked\(v_key\)/);
  assertMatch(n, /'quote_comparison_points:' \|\| coalesce\(v_quote::text, p_review::text\) \|\| ':'\s*\|\| left\(md5\(array_to_string\(array\(select distinct k from unnest\(p_keys\) k order by 1\)/);
  // only a SUBMITTED conversation, and never after the decision
  assertMatch(n, /v_status is distinct from 'submitted'/);
  assertMatch(n, /t\.revealed_at is not null/);
  // nothing of the customer: no customers table, no inquiry text, no point text in the letter
  assert(!/public\.customers|summary|raw_input|label_en|v_pt|->> 'supplier'/.test(n), 'the notice reads the customer or the points');
  assert(n.includes("'[؀-ۿ"), 'an Arabic company name, trade or emirate is left out (z05, ruling 1008)');
  assertMatch(n, /'The sales engineer has a question about your quotation for '/);
  // the handler calls it only when it recorded new points, and a notice that fails never undoes them
  const raise = body('fn_sales_engineer_comparison_points_raise');
  assertMatch(raise, /if v_n > 0 then\s+begin\s+v_notice := public\.fn_sales_engineer_comparison_points_notice\(p_id, v_review, v_keys\);\s+exception when others then/);
});

Deno.test('1b. its WhatsApp twin rides the supplier_account_notice template, as the hold desk\'s notices do', () => {
  assertEquals(tmplKey('quote_comparison_points'), 'supplier_account_notice');
  assertEquals(tmplKey('quote_comparison_points'), tmplKey('quote_spec_hold'));
});

Deno.test('2. the reveal and the end of the request supersede every open point and hand-over, with the reason', () => {
  const s = body('fn_sales_engineer_comparison_points_supersede');
  assertMatch(s, /set state = 'superseded', answered_at = now\(\), closed_reason = left\(v_reason, 300\)/);
  assertMatch(s, /x\.code = 'comparison_point' and x\.state = 'open'/);
  assertMatch(s, /fn_seat_handoff_complete\(v_id, jsonb_build_object\('superseded', true, 'reason', left\(v_reason, 300\)/);
  assertMatch(s, /set status = 'cancelled'[\s\S]*n\.type = 'quote_comparison_points' and n\.inquiry_id = p_inquiry and n\.status in \('queued', 'held'\)/);
  // the inquiry trigger fires on the one list of ends (request_closed.ts) plus 'revealed'
  const t = body('trg_request_decision_supersedes_comparison_points');
  const listed = [...(t.match(/in \(([^)]*)\)/)?.[1] ?? '').matchAll(/'([a-z_]+)'/g)].map((m) => m[1]).sort();
  assertEquals(listed, ['revealed', ...CLOSED_REQUEST_STATUSES].sort());
  assertMatch(SQL, /create trigger z33_request_decision_supersedes_comparison_points after update of status on public\.inquiries/);
  assertMatch(SQL, /create trigger z31_reveal_supersedes_comparison_points after insert or update of revealed_at on public\.transactions/);
  assertMatch(body('trg_reveal_supersedes_comparison_points'), /NEW\.revealed_at is not null[\s\S]*TG_OP = 'INSERT' or OLD\.revealed_at is null/);
  assertMatch(SQL, /alter table public\.quote_review_request add column if not exists closed_reason text;/);
  // every new routine is closed to public, anon and authenticated, by its exact signature (apply discipline 2)
  for (const sig of ['fn_sales_engineer_comparison_points_notice(bigint, uuid, text[])', 'fn_sales_engineer_comparison_points_supersede(uuid, text)',
    'trg_request_decision_supersedes_comparison_points()', 'trg_reveal_supersedes_comparison_points()']) {
    assert(SQL.includes('revoke execute on function public.' + sig + ' from public, anon, authenticated;'), sig);
  }
  for (const name of ['fn_sales_engineer_comparison_points_notice', 'fn_sales_engineer_comparison_points_supersede', 'trg_request_decision_supersedes_comparison_points', 'trg_reveal_supersedes_comparison_points']) {
    assertMatch(SQL, new RegExp('function public\\.' + name + "\\([^)]*\\)\\s+returns \\w+ language plpgsql security definer set search_path to 'public', 'pg_temp'"));
  }
});

Deno.test('2b. the probe proves both gaps on its own fixtures and always rolls back', () => {
  for (const s of ["'submitted'", "'open')", 'insert into public.transactions', "set status = 'expired'", "'already sent'", 'closed_reason', '1:customer_named', '4:notice_still_queued', '4:asked_after_reveal']) {
    assert(PROBE.includes(s), s);
  }
  assert(PROBE.includes("raise exception 'CHK<<PROBE OK") && !/\bcommit\b/i.test(PROBE.replace(/--.*$/gm, '')), 'a pure probe');
  assert(!/@(?!example\.invalid)[a-z0-9.-]+\.[a-z]{2,}/i.test(PROBE.replace(/--.*$/gm, '')), 'every address is a fixture');
});

Deno.test('2c. after the decision the page says the point is no longer asked, and stops promising that QuotesDone asks', () => {
  const { fits } = journeyA('en');
  const h = pointsHandoff(fits['Supplier A'], { inquiry_id: INQUIRY_A.id, quote_id: 'q-a', label: 'Supplier A' })!;
  const [k0, k1] = h.p_payload.points.map((p) => p.key);
  // quote_compare maps a superseded row to 'closed'
  assertMatch(INDEX, /p\.state === 'superseded' \? \{ state: 'closed', answer: null \}/);
  const closed = withAnswers(fits['Supplier A'], { [k0]: { state: 'answered', answer: 'The price is final.' }, [k1]: { state: 'closed', answer: null } });
  assertEquals(closed.asks.map((x) => x.state), ['answered', 'closed', 'asked']);
  for (const lang of ['en', 'ar'] as const) {
    const a = journeyA(lang).analysis; const rf = a.request_fit;
    rf.quotes = rf.quotes.map((q: { label: string }) => q.label === 'Supplier A' ? { ...q, asks: closed.asks.map(({ en, ar, state, answer }) => ({ en, ar, state, answer })) } : q);
    const page = JSON.stringify(compareDocument({ analysis: a, inquiry: INQUIRY_A as never, lang, maskNames: SUPPLIER_NAMES, date: '15 November 2026', date_ar: '15 نوفمبر 2026' }).body);
    assert(page.includes(lang === 'en' ? 'No longer asked: a supplier was chosen or the request ended' : 'لم يعد مطروحًا: تم اختيار مورّد أو انتهى الطلب'), lang);
    assert(page.includes(lang === 'en' ? 'Not answered yet' : 'لم تصل الإجابة بعد'), 'a point still asked keeps its wording: ' + lang);
  }
  // the advice (written when enforceFit re-orders the model's first place): while any point is still asked it promises the
  // ask; once every point is closed it does not. The model's first is set to each quote in turn until one is re-ordered.
  const advice = (state: 'asked' | 'closed', lang: 'en' | 'ar') => {
    const f = Object.fromEntries(Object.entries(journeyA(lang).fits).map(([l, fit]) => [l, { ...fit, asks: fit.asks.map((x) => ({ ...x, state })) }]));
    for (const first of Object.keys(f)) {
      const a = { top3: [{ label: first, why: '', tradeoff: '' }], advice: 'MODEL' };
      enforceFit(a, f, lang, {});
      if (a.advice !== 'MODEL') return String(a.advice);
    }
    throw new Error('no first place was re-ordered');
  };
  assert(advice('asked', 'en').includes('QuotesDone asks the supplier to confirm'));
  assert(!advice('closed', 'en').includes('asks the supplier'), advice('closed', 'en'));
  assert(advice('asked', 'ar').includes('تطلب QuotesDone من المورّد'));
  assert(!advice('closed', 'ar').includes('تطلب QuotesDone من المورّد'), advice('closed', 'ar'));
  assert(advice('closed', 'en').startsWith('We ranked the quotes on what you asked for'));
});
