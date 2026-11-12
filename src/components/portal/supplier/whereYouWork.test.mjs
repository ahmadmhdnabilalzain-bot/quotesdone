// node --test src/components/portal/supplier/whereYouWork.test.mjs
// WHERE HE WORKS IS ONE LIST, SET IN ONE PLACE (12 Nov 2026, sales_engineer, built by it_engineer; walk of 12 Nov 2026, blocker B1).
// The walk unticked an emirate on Services and saw Profile still list it (ev_emirates_services.jpg against ev_emirates_profile.jpg):
// the Profile tab had its own checkboxes, saved to a second column the matcher combined with the first. This fails if the Profile
// tab offers its own emirate checkboxes again, sends the emirates on its save, or prints the list in other words than Services.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { WHERE_YOU_WORK, whereYouWorkLine } from './whereYouWork.ts';
import { FLOW_COPY } from './servicesCopy.ts';

const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');

test('Profile prints the list as Services does: the emirates by name, or "Not set: all of the UAE"', () => {
  assert.equal(whereYouWorkLine(['Sharjah', 'Dubai']), 'Dubai, Sharjah');
  assert.equal(whereYouWorkLine([]), 'Not set: all of the UAE');
  assert.equal(FLOW_COPY.where_all, 'Not set: all of the UAE');
  assert.equal(whereYouWorkLine(null), FLOW_COPY.where_all);
  assert.equal(WHERE_YOU_WORK.title, FLOW_COPY.where, 'one name on both screens');
});

test('the Profile tab shows the list read-only with the way to Services, and its save does not send the emirates', () => {
  assert.doesNotMatch(form, /\{isEdit && <EmirateCheckboxes/, 'Profile has its own emirate checkboxes again');
  assert.match(form, /data-testid="profile-where-you-work"/);
  assert.match(form, /goTo\('services'\)/, 'no way from Profile to where the list is set');
  assert.match(form, /\.\.\.\(isEdit \? \{\} : \{ service_emirates: emirates \}\)/, 'the Profile save sends the emirates');
});
