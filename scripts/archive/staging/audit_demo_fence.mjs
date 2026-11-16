// Audit the production demo fence. Every number here is a count of ROWS THAT BREACH the fence, so
// a healthy estate reads zero on every line and the file needs no interpretation.
//
// ── WHY THIS IS COUNTS AND NOT VALUES ───────────────────────────────────────────────────────────
// The first version selected the single fixture's `routing` with a bare scalar subselect. That was
// correct while exactly one fenced inquiry existed and it raised 21000 — "more than one row
// returned by a subquery used as an expression" — the moment part 4 seeded six more. The gate that
// proves the fence died with a SQL error instead of reporting on the fence, which is the worst
// possible failure for a safety check: it looks like a broken script rather than an unguarded
// estate. Counting breaches is independent of how many fixtures there are.
//
// ── AND IT NOW COVERS THE QUOTE LEG ─────────────────────────────────────────────────────────────
// Part 4 added twenty-four fenced quotes. notify_new_quote_sms addresses a CUSTOMER and is gated
// only by `inq.customer_id is null`, so the quote leg is a real path to a real person's phone.
// Auditing only the inquiry leg would have watched the door the fixtures do not use.
// 23 Sep 2026: this imported the guard by absolute file:// url into one person's checkout, so it
// ran nowhere else and no path-rewriting sweep could see it. Relative, like every other importer.
import { mgmtRead, PROD_REF } from '../../lib/qd_guard.mjs';

const r = await mgmtRead(PROD_REF, `
  with i as (select id from public.inquiries where brief_source='qd_demo_fixture'),
       q as (select id from public.quotes where source='qd_demo_fixture'),
       l as (select id from public.leads where source='qd_demo_fixture')
  select
    (select count(*) from public.notifications n
       where n.inquiry_id in (select id from i) or n.quote_id in (select id from q))::text notifs,
    (select count(*) from public.inquiry_matches m where m.inquiry_id in (select id from i))::text matches,
    (select count(*) from public.inquiries where id in (select id from i) and routing is not null)::text dispatched,
    (select count(*) from public.inquiries where id in (select id from i) and customer_id is not null)::text has_customer,
    (select count(*) from public.inquiries where id in (select id from i) and rfq_ready is true)::text ready,
    (select count(*) from public.leads where id in (select id from l)
       and public.fn_is_matchable(verified, banned, matching_blocked,
                                  approval_status, permanently_closed, chat_strikes))::text matchable,
    (select count(*) from i)::text fixture_inquiries,
    (select count(*) from q)::text fixture_quotes,
    (select count(*) from l)::text fixture_leads,
    (select count(*) from public.notifications where status='queued')::text queued_total`);

const x = r[0];
// Every one of these must be zero. They are listed with the sentence each would mean if it were not.
const LEGS = [
  ['notifs', 'a notification was addressed to somebody'],
  ['matches', 'a fixture reached the matcher'],
  ['dispatched', 'dispatch_inquiry ran for a fixture'],
  ['has_customer', 'a fixture is attached to a real customer'],
  ['ready', 'a fixture has rfq_ready=true, so dispatch could fire'],
  ['matchable', 'a demo company passes fn_is_matchable and could be shown to a customer'],
];

console.log(`fixtures on production: ${x.fixture_leads} lead(s), ${x.fixture_inquiries} inquiry(s), ${x.fixture_quotes} quote(s)`);
const bad = LEGS.filter(([k]) => Number(x[k]) > 0);
for (const [k, meaning] of LEGS) {
  const n = Number(x[k]);
  console.log(`  ${n > 0 ? 'BREACH' : 'ok    '} ${k.padEnd(13)} ${x[k]}${n > 0 ? '  — ' + meaning : ''}`);
}
// Context, never a verdict: queued notifications from unrelated causes are somebody else's number.
console.log(`queued notifications on production, all causes: ${x.queued_total}`);
console.log(bad.length
  ? `\nFENCE BREACH on ${bad.length} leg(s): ${bad.map(([k]) => k).join(', ')}`
  : '\nFENCE HELD: nothing was matched, nothing was notified, nothing was dispatched, and no demo company is matchable.');
process.exit(bad.length ? 1 : 0);
