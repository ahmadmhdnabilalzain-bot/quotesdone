// profile_services.ts, offline (10 Nov 2026, sales_engineer; founder ledger 1573): the profile proposes SERVICES with the
// supplier's own words, the licence's activities are checked against them (never a rejection), his confirmed phrases go to
// the alias queue as short names only, and the request's chosen keys are read from its state.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { aliasPairsOf, licenceStatus, proposedServicesOf, servicesOfText, stateServiceKeys, type ServiceHit } from './profile_services.ts';
import type { MeaningService } from './service_meaning.ts';

const S = (trade_code: string, code: string, label_en: string, aliases: string[] = [], vec: number[] | null = null): MeaningService =>
  ({ trade_code, code, label_en, label_ar: label_en, aliases, vec, vec_ml: vec });
const VOCAB: MeaningService[] = [
  S('wallpaper', 'wall_panels', 'Wall panels', ['pvc decorative panels', 'wpc panels'], [1, 0, 0]),
  S('wallpaper', 'film_wrap', 'Architectural film & vinyl wrap', ['vinyl wrap'], [0, 1, 0]),
  S('gypsum', 'false_ceiling', 'False ceilings', ['false ceiling'], [0, 0, 1]),
];
const noEmbed = async () => { throw new Error('meaning must not be asked'); };

Deno.test('a profile line that IS a service name proposes it, with his own words and the line as evidence', async () => {
  const text = 'OUR SERVICES\nSupply and installation of PVC decorative panels, WPC panels and vinyl wrap\nGypsum board ceilings for villas';
  const r = await servicesOfText(text, { services: VOCAB.map((v) => ({ ...v, vec: null, vec_ml: null })), embed: noEmbed, budget: { left: 40 } });
  assertEquals(r.services.map((s) => s.key), ['wallpaper.film_wrap', 'wallpaper.wall_panels']);
  const wp = r.services.find((s) => s.key === 'wallpaper.wall_panels')!;
  assertEquals([wp.via, wp.phrase], ['exact_name', 'PVC decorative panels']);
  assert(wp.snippet.startsWith('Supply and installation of PVC decorative panels'));
  assertEquals(r.meaning, 'service_vectors_missing', 'no vectors: meaning says why it did not read');
});

Deno.test('a line nothing names is read by meaning, within the budget, and proposes its nearest service with the clause', async () => {
  // a clause whose vector equals false_ceiling's, and whose words carry its head word ("ceilings")
  const embed = async (t: string) => (/ceiling/i.test(t) ? [0, 0, 1] : [0.1, 0.1, 0.1]);
  const budget = { left: 40 };
  const r = await servicesOfText('Gypsum board ceilings for villas', { services: VOCAB, embed, budget });
  assertEquals(r.meaning, 'on');
  assertEquals(r.services.map((s) => [s.key, s.via]), [['gypsum.false_ceiling', 'meaning']]);
  assert(budget.left < 40, 'the clauses read were not taken from the shared budget');
  const spent = await servicesOfText('Gypsum board ceilings', { services: VOCAB, embed, budget: { left: 0 } });
  assertEquals([spent.meaning, spent.services.length], ['budget_spent', 0]);
});

const hit = (key: string, phrase = key): ServiceHit => ({ key, trade: key.split('.')[0], label_en: key, via: 'exact_name', phrase, snippet: phrase });

Deno.test('the licence check: supported when the activities name the trade, not covered when they do not, unclear with no activities', () => {
  const docs = [
    { kind: 'licence', status: 'read', name: 'licence.pdf', activities: ['Gypsum Works Contracting'], trades: [{ code: 'gypsum' }] },
    { kind: 'profile', status: 'read', name: 'profile.pdf', services: [hit('gypsum.false_ceiling'), hit('wallpaper.wall_panels', 'PVC decorative panels')] },
  ];
  const { proposed, licence_check } = proposedServicesOf(docs, '2026-11-10T00:00:00Z');
  assertEquals(proposed.map((p) => [p.key, p.licence]), [['gypsum.false_ceiling', 'supported'], ['wallpaper.wall_panels', 'not_covered']]);
  assertEquals(licence_check.not_covered, ['wallpaper.wall_panels']);
  assertEquals(licence_check.activities, ['Gypsum Works Contracting']);
  // never a rejection: the not-covered service is still proposed
  assert(proposed.some((p) => p.key === 'wallpaper.wall_panels'));
  // no licence read, or a licence whose activities could not be read: every service is 'unclear'
  const none = proposedServicesOf([docs[1]]);
  assertEquals([none.licence_check.read, none.proposed.map((p) => p.licence)], [false, ['unclear', 'unclear']]);
  const blank = proposedServicesOf([{ kind: 'licence', status: 'read', name: 'l', activities: [], trades: [] }, docs[1]]);
  assertEquals(blank.proposed.map((p) => p.licence), ['unclear', 'unclear']);
  assertEquals(licenceStatus('gypsum', { read: true, licence_trades: ['gypsum'] }), 'supported');
});

Deno.test('a document not read proposes nothing, and a key named twice is proposed once, from the first document', () => {
  const { proposed } = proposedServicesOf([
    { kind: 'profile', status: 'reading', name: 'p0', services: [hit('gypsum.false_ceiling')] },
    { kind: 'profile', status: 'read', name: 'p1', services: [hit('wallpaper.wall_panels', 'first')] },
    { kind: 'catalogue', status: 'read', name: 'c1', services: [hit('wallpaper.wall_panels', 'second')] },
  ]);
  assertEquals(proposed.map((p) => [p.key, p.doc, p.phrase]), [['wallpaper.wall_panels', 'p1', 'first']]);
});

Deno.test('only short phrases for services he CONFIRMED go to the alias queue', () => {
  const pairs = aliasPairsOf([
    { phrase: 'PVC decorative panels', key: 'wallpaper.wall_panels' },
    { phrase: 'pvc decorative panels ', key: 'wallpaper.wall_panels' },                      // the same, once
    { phrase: 'We supply and install every kind of panel for villas and offices', key: 'wallpaper.wall_panels' },   // a sentence
    { phrase: 'Vinyl wrap', key: 'wallpaper.film_wrap' },                                        // not confirmed
    { phrase: 'ab', key: 'wallpaper.wall_panels' },
  ], ['wallpaper.wall_panels']);
  assertEquals(pairs, [{ phrase: 'PVC decorative panels', key: 'wallpaper.wall_panels' }]);
});

Deno.test('the request\'s chosen keys come from its state: a string, a list or an entry, key-shaped and live only', () => {
  const known = new Set(['wallpaper.wall_panels', 'wallpaper.film_wrap']);
  assertEquals(stateServiceKeys({ specs: { service_keys: { value: 'wallpaper.wall_panels, wallpaper.film_wrap' } } }, known), ['wallpaper.film_wrap', 'wallpaper.wall_panels']);
  assertEquals(stateServiceKeys({ specs: { service_keys: ['wallpaper.wall_panels', 'PVC panels', 'x.y'] } }, known), ['wallpaper.wall_panels']);
  assertEquals(stateServiceKeys({ specs: { service_keys: { value: 'wallpaper.wall_panels | gypsum.false_ceiling' } } }), ['gypsum.false_ceiling', 'wallpaper.wall_panels']);
  assertEquals(stateServiceKeys({ specs: {} }, known), []);
  assertEquals(stateServiceKeys(null, known), []);
});
