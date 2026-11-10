// Where the embedding model is fetched from (9 Nov 2026): Hugging Face when ML_MODEL_HF_REPO names a repo, else Storage.
// A malformed value must fall back to Storage, never break every embedding.
import { assertEquals } from 'jsr:@std/assert@1';
import { modelFromHf } from './ml_embed_recipe.ts';

Deno.test('a well-formed owner/name repo id selects Hugging Face', () => {
  assertEquals(modelFromHf('Quotesdone/multilingual-e5-small-ar-en'), 'Quotesdone/multilingual-e5-small-ar-en');
  assertEquals(modelFromHf('  Quotesdone/multilingual-e5-small-ar-en  '), 'Quotesdone/multilingual-e5-small-ar-en');
});

Deno.test('unset, empty or malformed falls back to Storage (null)', () => {
  for (const v of [undefined, '', 'multilingual-e5-small-ar-en', 'https://huggingface.co/x/y', 'a/b/c', '../x', 'x/'])
    assertEquals(modelFromHf(v), null, String(v));
});

Deno.test('the Hugging Face model is pinned to a full commit sha, never a movable branch', async () => {
  const { ML_MODEL_HF_REVISION } = await import('./ml_embed_recipe.ts');
  assertEquals(/^[0-9a-f]{40}$/.test(ML_MODEL_HF_REVISION), true);
  const src = await Deno.readTextFile(new URL('./ml_embed.ts', import.meta.url));
  assertEquals(/revision:\s*ML_MODEL_HF_REVISION/.test(src), true, 'ml_embed.ts must pass the pinned revision to pipeline()');
});
