// PROOF BY EXECUTION for §14 the vault, §16 the unified inbox, and the §3 pre-send brief.
//
//   node scripts/staging/verify_portal_inbox.mjs
import { makeCustomer, call, newRun } from '../lib/demo_factory.mjs';

const run = newRun();
const fail = [];
const ok = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${String(name).padEnd(26)} ${detail}`);
  if (!cond) fail.push(name);
};
const body = (r) => (r && r.json ? r.json : r);

const cust = await makeCustomer(run);

// ── §14 the vault answers to its own name ───────────────────────────────────────────────────────
const v = body(await call('customer_documents', cust.jwt, { action: 'documents', limit: 20 }));
ok('vault action=documents', v && v.ok === true, `count=${v?.count} empty_reason=${v?.empty_reason}`);
const vLegacy = body(await call('customer_documents', cust.jwt, { action: 'list', limit: 20 }));
ok('legacy action=list', vLegacy && vLegacy.ok === true, 'the older spelling still reaches the same branch');
const vBad = body(await call('customer_documents', cust.jwt, { action: 'nope' }));
ok('unknown action', !!vBad?.error, `${vBad?.error}: ${String(vBad?.detail || '').slice(0, 70)}`);

// ── §16 the inbox declares its channels ─────────────────────────────────────────────────────────
const t = body(await call('messages_api', cust.jwt, { action: 'threads' }));
ok('threads', t && t.ok === true, `role=${t?.role} threads=${(t?.threads || []).length}`);
ok('channels declared', Array.isArray(t?.channels) && ['chat', 'whatsapp', 'email', 'call'].every((c) => t.channels.includes(c)),
  `channels=[${(t?.channels || []).join(',')}]`);
// A brand-new customer has no WhatsApp, no e-mail and no calls, so the ASSERTION is that the query
// ran and returned nothing — not that rows came back. A non-empty result here would mean the inbox
// had matched somebody else's correspondence, which is the failure this scoping exists to prevent.
ok('no cross-customer leak', (t?.threads || []).every((th) => th.channel === 'chat'),
  `${(t?.threads || []).length} thread(s), channels present=[${[...new Set((t?.threads || []).map((x) => x.channel))].join(',') || 'none'}] — a fresh customer must match no WhatsApp, e-mail or call rows`);

// ── §3 the brief states what will be required and how far it will reach ─────────────────────────
// The interview asks for whatever the category checklist marks required, so a fixed two turns is
// not enough for every category. This drives it to `ready` the way demo_factory's runIntake does,
// but keeps the LAST RESPONSE — runIntake returns only the status, and the brief is the subject.
let brief = null, last = null, turns = 0, intakeId = null;
const answers = [
  'I need 5,000 fire rated doors for a hotel in Dubai, 60 minute rating, steel core, delivered in 90 days.',
  'Budget is around AED 4,000,000. Doors go to floors 1 to 20. Single trade, no other works.',
];
for (let i = 0; i < 8; i++) {
  const missing = Array.isArray(last?.missing) ? last.missing.map(String) : [];
  const text = i < answers.length ? answers[i]
    : `Details: ${missing.slice(0, 6).map((m) => `${m}: standard specification, please assume typical values`).join('; ') || 'please proceed with typical values'}.`;
  last = body(await call('inquiry_intake', cust.jwt, intakeId ? { intake_id: intakeId, text } : { text }));
  turns++;
  if (!last || last.error) break;
  intakeId = last.intake_id || intakeId;
  if (last.status === 'ready') { brief = last.brief; break; }
}
ok('intake replies', !!last && !last.error, `status=${last?.status} category=${last?.category} after ${turns} turn(s)`);
ok('intake reaches ready', !!brief, brief ? `ready in ${turns} turn(s)` : `never reached ready in ${turns} turns (last status=${last?.status}, missing=${JSON.stringify(last?.missing)})`);
if (brief) {
  ok('required_documents', Array.isArray(brief.required_documents),
    `${(brief.required_documents || []).length} item(s) — source: ${brief.required_documents_source}`);
  ok('supplier_count', 'supplier_count' in brief,
    `${brief.supplier_count} — basis: ${String(brief.supplier_count_basis || '').slice(0, 90)}`);
  ok('quantity extracted', 'quantity' in brief, `quantity=${JSON.stringify(brief.quantity)}`);
  ok('timeline extracted', 'timeline' in brief, `timeline=${JSON.stringify(brief.timeline)}`);
} else {
  ok('brief present', false, 'the interview never reached ready, so the §3 keys could not be measured');
}

console.log(`\n${fail.length ? 'FAILED: ' + fail.join(', ') : 'ALL PASS'}`);
process.exit(fail.length ? 1 : 0);
