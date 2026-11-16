// db_region.test.ts - the WhatsApp reply's callees run in the database's region (customer_support, 10 Nov 2026; see db_region.ts).
// Red on main: llm.ts, wa_inbound/shared.ts, ml_embed_client.ts and meaning_embed.ts built their ai_gateway / embed_ml URLs with
// no region, so a Twilio webhook entering at us-east-1 ran the gateway there (p50 3.3 s of its own work per call).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { DB_REGION, inDbRegion } from './db_region.ts';

const here = new URL('.', import.meta.url);
const src = (rel: string) => Deno.readTextFileSync(new URL(rel, here));

Deno.test('a function URL is pinned to the database region, once, whatever query it already has', () => {
  assertEquals(DB_REGION, 'ap-southeast-1');
  assertEquals(inDbRegion('https://x.supabase.co/functions/v1/ai_gateway'), 'https://x.supabase.co/functions/v1/ai_gateway?forceFunctionRegion=ap-southeast-1');
  assertEquals(inDbRegion('https://x.supabase.co/functions/v1/embed_ml?a=1'), 'https://x.supabase.co/functions/v1/embed_ml?a=1&forceFunctionRegion=ap-southeast-1');
  // a caller that already names a region keeps its own (never two parameters)
  assertEquals(inDbRegion('https://x/functions/v1/f?forceFunctionRegion=eu-west-1'), 'https://x/functions/v1/f?forceFunctionRegion=eu-west-1');
  // the receiving function still sees its own path (observe.ts pathOf, the tests' pathname matches)
  assertEquals(new URL(inDbRegion('https://x/functions/v1/ai_gateway')).pathname, '/functions/v1/ai_gateway');
});

Deno.test("every ai_gateway and embed_ml call on the WhatsApp reply's path names the database region", () => {
  for (const [file, slug] of [['./llm.ts', 'ai_gateway'], ['../wa_inbound/shared.ts', 'ai_gateway'], ['./ml_embed_client.ts', 'embed_ml']] as const) {   // meaning_embed.ts removed 16 Nov 2026 (no caller; ruling 1627)
    const code = src(file).split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
    const sites = code.match(new RegExp("[^\\n]*'/functions/v1/" + slug + "'[^\\n]*", 'g')) ?? [];
    assert(sites.length > 0, file + ' no longer calls ' + slug + ' by its literal path (no_function_calls_an_undeployed_function reads it)');
    for (const s of sites) assert(/inDbRegion\(/.test(s), file + ' calls ' + slug + ' without inDbRegion: ' + s.trim());
  }
});
