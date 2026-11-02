// ai_gateway never runs an embedding model in its own worker (it_engineer, 2 Nov 2026). On 1-2 Nov six gateway requests
// died with "CPU Time exceeded" (HTTP 546); four were tiny {action:'embed'} calls killed ~400 ms after boot, two per
// worker, by the in-process model. Every vector now comes from embed_ml through _shared/ml_embed_client.ts.
//   deno test supabase/functions/ai_gateway/embed_is_remote.test.ts
import { assert, assertMatch } from 'jsr:@std/assert';

const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url)).replace(/\r\n/g, '\n');

Deno.test('the gateway source builds no model session of its own', () => {
  assert(!/Supabase\s*\??\.\s*ai/.test(src), 'ai_gateway/index.ts reaches the in-process model again');
  assert(!/\.Session\s*\(/.test(src), 'ai_gateway/index.ts opens a model session again');
});

Deno.test('its one embed() asks embed_ml for the same gte-small space', () => {
  assertMatch(src, /import \{ embedGteRemote \} from '\.\.\/_shared\/ml_embed_client\.ts'/);
  const body = src.slice(src.indexOf('async function embed('), src.indexOf('\n}\n', src.indexOf('async function embed(')));
  assertMatch(body, /embedGteRemote\(admin,/);
});
