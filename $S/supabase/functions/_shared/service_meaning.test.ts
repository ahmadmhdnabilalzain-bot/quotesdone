// THE MEANING LAYER'S RULES, on hand-made vectors (no model, no network). What gte-small itself does with
// real lines is proved against the live model by scripts/checks/a_catalogue_line_is_understood_by_meaning.test.mjs.
//   deno test -A supabase/functions/_shared/service_meaning.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { headWords, MEANING_FLOOR, parseVec, proposeByMeaning, type MeaningService } from './service_meaning.ts';

// Unit vectors on a few axes: cos(a, b) is exactly what the test says it is.
const v = (...xs: number[]) => { const n = Math.hypot(...xs); return xs.map((x) => x / n); };
const at = (sim: number) => v(sim, Math.sqrt(1 - sim * sim), 0, 0);   // cos with [1,0,0,0] = sim
const svc = (trade_code: string, code: string, label_en: string, vec: number[], aliases: string[] = []): MeaningService =>
  ({ trade_code, code, label_en, label_ar: 'خدمة', aliases, vec });
const COPIERS = svc('office_equipment', 'photocopiers', 'Photocopiers & copiers', [1, 0, 0, 0], ['photocopier', 'copier']);
const TRAYS = svc('electrical', 'cable_tray', 'Cable trays & containment', [1, 0, 0, 0], ['cable tray']);
const SERVICING = svc('office_equipment', 'printer_service', 'Printer & copier servicing', [1, 0, 0, 0]);

Deno.test('head words are what the service IS', () => {
  assertEquals(headWords('Photocopiers & copiers'), ['photocopier', 'copier']);
  assertEquals(headWords('Cable trays & containment'), ['tray', 'containment']);
  assertEquals(headWords('Office machines (shredders, laminators, binders)'), ['machine', 'shredder', 'laminator', 'binder']);
  assertEquals(headWords('Hardware supply'), ['hardware']);
  assertEquals(headWords('UPS systems'), ['ups']);
});

Deno.test('a line whose words hold the head of the nearest service is proposed, with the line as the reason', () => {
  const p = proposeByMeaning([{ text: 'we distribute office printers and copiers', vec: at(0.90) }], [COPIERS]);
  assertEquals(p.map((x) => [x.key, x.because, x.word]), [['office_equipment.photocopiers', 'head_word', 'copier']]);
  assertEquals(p[0].lines, ['we distribute office printers and copiers']);
});

Deno.test('a nearest neighbour alone is never accepted', () => {
  assertEquals(proposeByMeaning([{ text: 'Gold partner', vec: at(0.95) }], [COPIERS]), []);
  // A shared word that is not the head ("cable" is not "cable trays") is not corroboration either.
  assertEquals(proposeByMeaning([{ text: 'Cables', vec: at(0.95) }], [TRAYS]), []);
});

Deno.test('below the floor nothing is proposed, whatever words it shares', () => {
  assertEquals(proposeByMeaning([{ text: 'copiers', vec: at(MEANING_FLOOR - 0.01) }], [COPIERS]), []);
});

// REWRITTEN 22 Sep 2026 (finding SP-F-06). This test used to assert the OPPOSITE: that two lines
// above a stricter cosine floor, with no word agreeing anywhere, were accepted as `two_lines`. That
// is similarity alone, twice — two lines of one catalogue are the same hand writing about the same
// business, not an independent witness — and it contradicted the founder's "exact match or no
// match". The rule was removed; the check now pins the corrected behaviour.
Deno.test('two lines that only look similar are still not accepted — a word has to agree', () => {
  const lines = (s: number) => [{ text: 'first line about office kit', vec: at(s) }, { text: 'another unrelated wording', vec: at(s) }];
  assertEquals(proposeByMeaning(lines(0.85), [COPIERS]), []);
  assertEquals(proposeByMeaning(lines(0.99), [COPIERS]), []);
  // The same two lines, one of them naming the head word, are accepted — on the word, not the pair.
  assertEquals(proposeByMeaning([{ text: 'we sell copiers', vec: at(0.9) }, { text: 'another unrelated wording', vec: at(0.9) }], [COPIERS])
    .map((x) => x.because), ['head_word']);
});

Deno.test('installation work is a candidate only for a line that speaks of that work, and never for a supplier of goods', () => {
  // SERVICING is exactly as near as COPIERS; without a work word it is not even a candidate.
  assertEquals(proposeByMeaning([{ text: 'we distribute printers and copiers', vec: at(0.9) }], [SERVICING, COPIERS]).map((x) => x.key), ['office_equipment.photocopiers']);
  assertEquals(proposeByMeaning([{ text: 'we repair printers and copiers', vec: at(0.9) }], [SERVICING]).map((x) => x.key), ['office_equipment.printer_service']);
  assertEquals(proposeByMeaning([{ text: 'we repair printers and copiers', vec: at(0.9) }], [SERVICING], { supplyOnly: true }), []);
});

Deno.test('what the word rules already found is not proposed again; a pgvector string parses', () => {
  assertEquals(proposeByMeaning([{ text: 'copiers', vec: at(0.9) }], [COPIERS], { stated: ['office_equipment.photocopiers'] }), []);
  assertEquals(parseVec('[0.5,-0.25]'), [0.5, -0.25]);
  assertEquals(parseVec(null), null);
  assert(parseVec('not a vector') === null);
});

// ── 29 Sep 2026, decision point 93 (b): clauses, the Arabic space, the recipe, the embedder ──────────────
import { headWordsAr, meaningClauses, meaningSpace, ML_FLOOR, serviceEmbedText, serviceMlText, textSha } from './service_meaning.ts';
import { embedLines } from './meaning_embed.ts';
import { exactService } from './service_rewrite.ts';

Deno.test('a sentence is read clause by clause; what follows "for" says where, not what', () => {
  assertEquals(meaningClauses('We need to supply and install ducting for the new majlis'), ['We need to supply', 'install ducting']);
  assertEquals(meaningClauses('Chiller maintenance and AMC contracts for towers and villas'), ['Chiller maintenance', 'AMC contracts']);
  assertEquals(meaningClauses('Supply of cable trays'), ['Supply of cable trays'], '"of" is not cut: the service follows it');
  assertEquals(meaningClauses('Point OF SALE'), ['Point OF SALE']);
  assertEquals(meaningClauses('نقوم بأعمال الجبس والأسقف المستعارة والدهانات'), ['نقوم بأعمال الجبس', 'الأسقف المستعارة', 'الدهانات']);
  assertEquals(meaningClauses('Dubai and Sharjah'), [], 'glue is never read');
});

Deno.test('an Arabic line is read in the multilingual space, an English one in gte-small', () => {
  assertEquals(meaningSpace('الأسقف المستعارة'), 'ml');
  assertEquals(meaningSpace('False ceilings'), 'gte');
  assertEquals(headWordsAr('الأسقف المعلقة'), ['اسقف']);
  assertEquals(headWordsAr('مجاري الهواء والتهوية'), ['مجاري', 'تهويه']);
});

Deno.test('ARABIC: the multilingual vector only shortlists; the first service a name word agrees with is taken', () => {
  const CEIL = { trade_code: 'gypsum', code: 'false_ceiling', label_en: 'False ceilings', label_ar: 'الأسقف المعلقة', aliases: [], vec: null, vec_ml: v(0.99, 0.14, 0, 0) } as MeaningService;
  const FORGE = { trade_code: 'castings_forgings', code: 'forgings', label_en: 'Forgings', label_ar: 'المطروقات', aliases: [], vec: null, vec_ml: [1, 0, 0, 0] } as MeaningService;
  // FORGE is nearer, as measured for الدهانات on the live space; nothing in the line agrees with it, so CEIL is taken.
  const p = proposeByMeaning([{ text: 'الأسقف المستعارة', vec: [1, 0, 0, 0], space: 'ml' }], [FORGE, CEIL]);
  assertEquals(p.map((x) => [x.key, x.because, x.word]), [['gypsum.false_ceiling', 'head_word', 'اسقف']]);
  // Noise: nothing agrees, nothing is proposed, however near.
  assertEquals(proposeByMeaning([{ text: 'نحن شركة رائدة', vec: [1, 0, 0, 0], space: 'ml' }], [FORGE, CEIL]), []);
  // Below the floor, nothing is shortlisted.
  assertEquals(proposeByMeaning([{ text: 'الأسقف المستعارة', vec: v(ML_FLOOR - 0.05, 0, Math.sqrt(1 - (ML_FLOOR - 0.05) ** 2), 0), space: 'ml' }], [{ ...CEIL, vec_ml: [1, 0, 0, 0] }]), []);
  // An English line never reads the multilingual vector, nor an Arabic line the gte one.
  assertEquals(proposeByMeaning([{ text: 'false ceilings', vec: [1, 0, 0, 0], space: 'gte' }], [CEIL]), []);
});

Deno.test('ENGLISH: the one nearest service, as calibrated; the shortlist is the Arabic space only', () => {
  const near = svc('x', 'near', 'Forgings', [1, 0, 0, 0]);
  // COPIERS at 0.9 is second: an English line takes only the first, which no word agrees with.
  assertEquals(proposeByMeaning([{ text: 'copiers', vec: [1, 0, 0, 0] }], [near, { ...COPIERS, vec: at(0.9) }]), []);
});

Deno.test('the vector recipe: aliases feed the vector (English ones for gte), both names, the trade; the sha follows the text', async () => {
  const s = { label_en: 'Hardware supply', label_ar: 'توريد الأجهزة', aliases: ['laptop', 'desktop', 'توريد حواسيب'] };
  const t = { label: 'IT services', label_ar: 'خدمات تقنية المعلومات' };
  assertEquals(serviceEmbedText(s, t), 'Hardware supply: laptop, desktop (IT services). توريد الأجهزة (خدمات تقنية المعلومات)');
  assert(serviceMlText(s, t).includes('توريد حواسيب') && serviceMlText(s, t).includes('laptop'));
  assertEquals(await textSha('a'), 'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb');
  assert((await textSha(serviceEmbedText(s, t))) !== (await textSha(serviceEmbedText({ ...s, aliases: ['laptop'] }, t))), 'a new alias must make the vector stale');
});

Deno.test('the exact path is a name lookup: a curated alias, whole; a name two services share names neither', () => {
  const A = { trade_code: 'doors', code: 'wooden', label_en: 'Wooden doors', label_ar: 'أبواب خشبية', aliases: ['timber doors', 'wood door'] };
  const B = { trade_code: 'joinery', code: 'doors', label_en: 'Joinery doors', label_ar: 'أبواب النجارة', aliases: ['wood door'] };
  assertEquals(exactService('Timber Doors', [A, B])?.code, 'wooden');
  assertEquals(exactService('wood door', [A, B]), null, 'shared by two services: exact or none');
  assertEquals(exactService('timber doors for the villa', [A, B]), null, 'a sentence is not a name');
  assertEquals(exactService('أبواب خشبيّة', [A, B])?.code, 'wooden', 'a diacritic does not change the name');
});

Deno.test('embedLines: each line in its own space, never more than 8 at once, in order, a failure kept as null', async () => {
  let live = 0, peak = 0; const asked: string[] = [];
  const out = await embedLines(Array.from({ length: 20 }, (_, k) => (k === 3 ? 'فشل' : k % 2 ? 'الأسقف ' + k : 'ceiling ' + k)), async (t, space) => {
    live++; peak = Math.max(peak, live); asked.push(space);
    await new Promise((r) => setTimeout(r, 2)); live--;
    return t === 'فشل' ? null : [1, 0];
  });
  assert(peak <= 8, `${peak} in flight`);
  assertEquals(out.map((l) => l.space).slice(0, 4), ['gte', 'ml', 'gte', 'ml']);
  assertEquals(out[3].vec, null);
  assertEquals(out.filter((l) => l.vec).length, 19);
});
