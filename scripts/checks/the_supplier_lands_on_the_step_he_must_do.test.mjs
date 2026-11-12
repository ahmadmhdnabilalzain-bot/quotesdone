// THE SUPPLIER LANDS ON THE STEP HE MUST DO (12 Nov 2026, customer_support; founder ruling 1645). Paid certification on production,
// J10 at 390 px, right after "Submit for approval": header, the card "Registration received. We are checking it now. Nothing is
// needed from you", six tabs over three rows (~170 px), a 580 px "Profile score" card whose first row sent him to the Services tab
// he was on, and only ~1,150 px down "Here is what we understood your company does", while three services waited to be ticked.
// Local shell walk (the real SupplierPortal, Dashboard, tabs, score card and ServicesTab on a stubbed API), before -> after:
//   360x740: services step heading y 1,314 -> 494 (proposals), 1,391 -> 571 (cards); 390x664: 1,265 -> 469, 1,342 -> 547;
//   tabs ~170 px -> 58 px; the card follows the tab (reading / one step left); CLS 0 to 0.016.
//   node --test scripts/checks/the_supplier_lands_on_the_step_he_must_do.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as RR from '../../src/components/portal/supplier/registrationReceived.ts';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const DASH = R('src/components/portal/supplier/core/Dashboard.tsx');
const SCORE = R('src/components/portal/supplier/ProfileScore.tsx');
const TAB = R('src/components/portal/supplier/ServicesTab.tsx');

test('for an unconfirmed supplier on the Services tab, the services step renders ABOVE the score card, without its "Confirm your services" row', () => {
  const i = DASH.indexOf("{shownTab === 'services' && (scopeOpen");
  assert.ok(i > 0, 'the Services tab no longer decides its order by whether his services are confirmed');
  const unconfirmed = DASH.slice(i, DASH.indexOf(': <>', i));
  assert.ok(unconfirmed.indexOf('<ServicesTab') >= 0 && unconfirmed.indexOf('<ServicesTab') < unconfirmed.indexOf('<ProfileScore'), 'the score card renders above the services step for an unconfirmed supplier');
  assert.match(unconfirmed, /<ProfileScore [^>]*hide=\{\['scope'\]\}/, 'the score card offers "Go to Services" on the Services tab');
  assert.match(unconfirmed, /\{svc \? <div className="mt-4"><ProfileScore/, 'the score card must wait for the tab (it was drawn first and pushed down: CLS 0.2-0.33)');
  assert.match(SCORE, /todo = all\.filter\(\(i\) => !hide\.includes\(i\.key\)\)/);
});

test('the card follows what the Services tab knows, in each of the three states', () => {
  const base = { approvalStatus: 'pending', submitted: true, reason: 'documents_being_read', signingOnly: false, scopeOpen: true };
  const reading = RR.registrationReceived({ ...base, services: { confirmed: false, reading: true, waiting: false } });
  assert.equal(reading.text(true), RR.READING_HERE); assert.equal(reading.text(false), RR.READING_THERE);
  assert.match(RR.READING_HERE, /reading your documents/); assert.match(RR.READING_HERE, /appear below/);
  for (const [label, sv] of [['proposals waiting', { confirmed: false, reading: false, waiting: true }], ['cards waiting', { confirmed: false, reading: false, waiting: true }]]) {
    const c = RR.registrationReceived({ ...base, services: sv });
    assert.equal(c.kind, 'services', label);
    assert.equal(c.text(true), 'One step left: confirm your services below.', label + ' (on the Services tab: nothing sends him elsewhere)');
    assert.doesNotMatch(c.text(true), /Nothing is needed/, label);
  }
  // after Confirm: what is true then (the gate re-reads; the dashboard is read again)
  assert.equal(RR.registrationReceived({ ...base, reason: 'services_unconfirmed', services: { confirmed: true, reading: false, waiting: false } }).text(true), RR.NOTHING_NEEDED);
  // a hold that asks for something still comes first
  assert.equal(RR.registrationReceived({ ...base, reason: 'licence_expiry_unread', services: { confirmed: false, reading: false, waiting: true } }).text(true), RR.ONE_THING_NEEDED);
});

test('the tab tells the workspace, and the workspace reads its status again when the reading lands and after each Confirm', () => {
  assert.match(TAB, /onStatus\(\{ confirmed: !!d\.confirmed, reading, waiting, confirmedAt: confirmedAt\.current \}\)/);
  assert.match(TAB, /confirmedAt\.current \+= 1;\n\s*load\(\);/);
  assert.match(DASH, /if \(p && \(\(p\.reading && !s\.reading\) \|\| s\.confirmedAt !== p\.confirmedAt\)\) load\(\);/);
});

test('the tabs are one row on a phone that scrolls, with a fade while more follow; they wrap from sm up', () => {
  assert.match(DASH, /data-testid="main-tabs" className=\{cn\('qd-tabs flex flex-nowrap gap-1 overflow-x-auto [^']*sm:inline-flex sm:flex-wrap sm:overflow-visible/);
  assert.match(DASH, /\{tabMore\.end \? <span aria-hidden className="pointer-events-none absolute [^"]*bg-linear-to-l from-navy-deep/);
  assert.match(DASH, /aria-current=\{tab === k \? 'page' : undefined\}/, 'the current tab is still announced');
});
