// WHAT IS LEFT OF THE MEANING LAYER (16 Nov 2026, it_engineer; simplification wave A, DUP item 5). proposeByMeaning, the code
// matcher these tests drove on hand-made vectors, was removed under ruling 1627 with meaning_embed.ts (a service is understood by
// the model reading the documents). Kept and tested here: the vector recipe the stored vectors are built from
// (scripts/kb/embed_taxonomy_services.mjs), parseVec (service_vocabulary.serviceVocab) and the exact-name lookup.
//   deno test -A supabase/functions/_shared/service_meaning.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { parseVec, serviceEmbedText, serviceMlText, textSha } from './service_meaning.ts';
import { exactService } from './service_rewrite.ts';

Deno.test('a pgvector string parses; anything else is null', () => {
  assertEquals(parseVec('[0.5,-0.25]'), [0.5, -0.25]);
  assertEquals(parseVec([0.5, -0.25]), [0.5, -0.25]);
  assertEquals(parseVec(null), null);
  assert(parseVec('not a vector') === null);
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
