// profile_services.ts, offline (10 Nov 2026, sales_engineer; founder ledger 1573): the profile proposes SERVICES with the
// supplier's own words, the licence's activities are checked against them (never a rejection), his confirmed phrases go to
// the alias queue as short names only, and the request's chosen keys are read from its state.
import { assertEquals } from 'jsr:@std/assert@1';
import { aliasPairsOf, stateServiceKeys } from './profile_services.ts';

// servicesOfText, proposedServicesOf and licenceStatus were deleted with the code proposal path (ruling 1627, 11 Nov 2026): the
// reading is the model's, tested in the_model_reads_the_suppliers_documents_together.test.ts.

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
