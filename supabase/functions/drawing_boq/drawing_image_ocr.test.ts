// A real drawing IMAGE read through the free path, scored against a person's answer key.
// deno test -A supabase/functions/drawing_boq/drawing_image_ocr.test.ts
//
// An image has no text layer, and every model route is held, so drawing_boq reads a photo only as
// the customer's browser OCR (src/components/me/ocrClient.ts: tesseract.js 7.0.0, LSTM, the
// self-hosted language data in public/ocr/lang) handed to boqFromExtracted(empty('image'), hint,
// ocr_text). This runs the same library and data locally, so no model and no network is used.
// It MEASURES; it asserts only that the path runs. The printed table is the result.
import { assert } from 'jsr:@std/assert@1';
import { createWorker } from 'npm:tesseract.js@7.0.0';
import { boqFromExtracted } from './boq_from_document.ts';
import { empty } from '../_shared/doc_read/types.ts';

const here = new URL('.', import.meta.url);
const FIXTURE = new URL('fixtures/harrogate_court_fire_alarm_gf_as_installed.png', here);
const KEY = new URL('fixtures/harrogate_court_fire_alarm_gf_as_installed.key.json', here);
const LANG = decodeURIComponent(new URL('../../../public/ocr/lang', here).pathname).replace(/^\/([A-Za-z]:)/, '$1');

type Field = { value: unknown; confidence: string };
const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9/.-]+/g, ' ').replace(/\s+/g, ' ').trim();

/** Field by field: is every keyed value present in what the reader produced? */
export function score(key: Record<string, Field>, haystack: string) {
  const h = norm(haystack);
  const addrs = new Set([...haystack.matchAll(/L1\s*\/\s*(\d{2})/gi)].map((m) => m[1]));
  const rows: { field: string; confidence: string; result: string }[] = [];
  for (const [field, f] of Object.entries(key)) {
    if (field.startsWith('_') || f.value === 'not_counted') continue;
    let result: string;
    if (field === 'address_count') result = `${addrs.size}/${f.value} distinct L1/NN read`;
    else if (field === 'sound_levels_dba') {
      const v = [...haystack.matchAll(/(\d{2})\s*dBA/gi)].map((m) => Number(m[1]));
      result = v.length ? `${v.length} dBA tags, ${Math.min(...v)}-${Math.max(...v)}` : 'WRONG (none read)';
    } else {
      const vals = Array.isArray(f.value) ? f.value.map(String) : [String(f.value)];
      // Whole words only: a bare substring let "L1" match inside the OCR noise "L182".
      const hit = vals.filter((v) => norm(v).length > 1 && (' ' + h + ' ').includes(' ' + norm(v) + ' '));
      const scored = vals.filter((v) => norm(v).length > 1);
      result = !scored.length ? 'n/a (symbol only)' : hit.length === scored.length ? 'RIGHT' : hit.length ? `PARTIAL ${hit.length}/${scored.length}` : 'WRONG (not read)';
    }
    rows.push({ field, confidence: f.confidence, result });
  }
  return rows;
}

// The suite runner (scripts/checks/run.mjs) grants no permissions; OCR needs read + npm, so it runs
// under `deno test -A` and is reported as ignored, not failed, without them.
const CAN = Deno.permissions.querySync({ name: 'read' }).state === 'granted' && Deno.permissions.querySync({ name: 'env' }).state === 'granted';
Deno.test({ name: 'drawing image: tesseract OCR + boqFromExtracted vs answer key (no model)', ignore: !CAN }, async () => {
  const key = JSON.parse(await Deno.readTextFile(KEY));
  const png = await Deno.readFile(FIXTURE);
  const worker = await createWorker('eng', 1, { langPath: LANG, gzip: true, cacheMethod: 'none' });
  let text = '', conf = 0;
  try {
    const { data } = await worker.recognize(png);
    text = data.text; conf = data.confidence;
  } finally { await worker.terminate(); }
  const out = boqFromExtracted(empty('image'), '', text);

  console.log(`\nOCR: ${text.length} chars, mean confidence ${conf.toFixed(1)}`);
  console.log(`BOQ: ${out.boq.length} lines, confidence ${out.confidence}, missing_info: ${JSON.stringify(out.missing_info)}`);
  console.log('\nLayer 1 - OCR text (what the reader receives):');
  console.table(score(key, text));
  console.log('Layer 2 - the reader\'s structured output (boqFromExtracted):');
  console.table(score(key, JSON.stringify(out)));
  assert(text.trim().length > 0, 'OCR returned no text');
  assert(out.method === 'document');
});
