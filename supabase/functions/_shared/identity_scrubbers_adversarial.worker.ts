// identity_scrubbers_adversarial.worker.ts — runs ONE scrubber on inputs sent by
// identity_scrubbers_finish_on_adversarial_input.test.ts, so a scrubber that never finishes is terminated at its limit
// and fails the test in seconds instead of hanging the suite (second review of 13 Nov 2026: with the ReDoS guard reverted,
// the suite ran until a 900 s kill).
import { identityShapesIn, knownNameRe, scrubAddresses, scrubIdentityText } from './identity_text.ts';
import { placeSpans, reducePlaces } from './identity_places.ts';
import { redactText, residualScan } from './anonymise.ts';
import { maskContacts } from './quote_documents.ts';
import { generaliseText } from './quote_generalise.ts';
import { inboxField, scrubDeep, scrubIdentity } from '../supplier_api/identity_scrub.ts';
import { stripContact, stripSupplierQuestion } from '../messages_api/strip_contact.ts';
import { scrubIdentity as boqScrub } from '../drawing_boq/boq_from_text.ts';
import { scrubModelText } from '../quote_extract/model_reading.ts';

const NAME = 'ZZ DEMO Falcon Trading LLC';
export const RUN: Record<string, (s: string) => unknown> = {
  scrubIdentityText: (s) => scrubIdentityText(s, '[X]'), identityShapesIn, reducePlaces: (s) => reducePlaces(s, '[X]'), placeSpans, scrubAddresses,
  knownNameRe: (s) => s.replace(knownNameRe(NAME, { fragments: true })!, ''), redactText: (s) => redactText(s, ['haddad']), residualScan: (s) => residualScan(s, ['haddad']),
  maskContacts: (s) => maskContacts(s, [NAME]), generaliseText: (s) => generaliseText(s, { supplierNames: [NAME] }), scrubIdentity: (s) => scrubIdentity(s, NAME, []),
  scrubDeep: (s) => scrubDeep({ a: s }, NAME, []), stripContact: (s) => stripContact(s, [NAME]), stripSupplierQuestion: (s) => stripSupplierQuestion(s, [NAME]),
  boqScrub, scrubModelText, inboxField: (s) => inboxField(s, 'ZZ DEMO Omar Haddad', ['zz demo omar haddad', 'haddad'], []),
};
// deno-lint-ignore no-explicit-any
const self_ = self as any;
self_.onmessage = (e: MessageEvent) => {
  const { who, input } = e.data as { who: string; input: string };
  const t0 = performance.now(); RUN[who](input); self_.postMessage({ ms: performance.now() - t0 });
};
self_.postMessage({ ready: true });
