// A DEAD WORKER IS ASKED AGAIN, A PAGE IS NEVER PUBLISHED ON ONE (17 Nov 2026, sales_engineer; paid proof 623d9200).
// Production, 17 Nov 17:19 UTC (function logs, SELECT): concurrent tile crops shared an isolate, its CPU cap was counted over
// all of them, and two crops answered HTTP 546 "CPU Time exceeded". A crop that does not come back is a view the model is
// never asked, so the page was HELD 'pixels_unverified' (ai_cost_log: 12-15 of each page's 25 views asked), and no sheet of
// the 8-sheet set reached a supplier. drawing_redact asked a worker again only on a relay refusal (a 502/503 no worker served).
// Here the REAL handler runs the manual path (what customer_api sends) on sheet 1 of the e2e set, every edge stubbed: the
// paint, tile and checker answers come from this file, so no JPEG is decoded and no model is asked.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. \
//     --allow-net=deno.land,esm.sh supabase/functions/drawing_redact/a_dead_worker_is_asked_again.check.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { planBoxes, planStrips, readPdfPlan } from '../_shared/drawing_plan.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { supplierBoxes } from '../_shared/supplier_copy.ts';
// Imported BEFORE the harness replaces fetch: drawing_redact_page.ts loads imagescript, whose codec .wasm is fetched from
// deno.land at import (the reason this is a .check.ts with that one host, like ./a_sheet_is_redacted_within_the_edge_budget).
import { bytesToB64 } from '../_shared/drawing_redact_page.ts';
import { VIEWS_PER_CROP, pageSizeFromMediaBox, planTiles } from '../_shared/drawing_pixel_gate.ts';

const SET8 = Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_8_sheets.pdf', import.meta.url));
const SHEET1 = bytesToB64(Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_sheet1_portal_2600.jpg', import.meta.url)));
const SECRET = 'zz-cred-0123456789abcdef0123';
const J = (o: unknown, status = 200, headers: Record<string, string> = {}) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', ...headers } });
// What the edge answers when an isolate is killed past its CPU cap (the runtime served it, so not a relay refusal).
const DIED = () => J({ code: 'WORKER_RESOURCE_LIMIT', message: 'Function failed due to not having enough compute resources' }, 546, { 'x-served-by': 'supabase-edge-runtime' });

const seeds = seedTerms({ name: 'ZZ DEMO Drawing', email: 'qd-cust@example.invalid', phone: '', extra: ['ZZ DEMO mechanical set.pdf'] });
const plan = (await readPdfPlan(async (b: any) => b.step === 'boxes' ? { ok: true, ...(await planBoxes(SET8, b.from, b.to, b.seed_terms, b.set_seeds)) } : { ok: true, ...(await planStrips(SET8, b.from, b.to)) }, seeds))!;
const boxes = supplierBoxes(plan.tb, null, 8)!;

/** One page through the real handler. `tileDies(n)` / `paintDies(n)`: does the n-th call (1-based) of that worker die? */
async function onePage(o: { tileDies?: (n: number, view: string) => boolean; paintDies?: (n: number) => boolean }) {
  const marks = new Map<string, string>(); let tiles = 0, paints = 0, asked = 0, cropCalls = 0, deadCalls = 0;
  const stub: Stub = {
    rpc: { fn_internal_auth: { ok: true, context: 'fn.customer_api', credential_id: 7, legacy: false } },
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/drawing_redact') {
        const b = await req.clone().json();
        if (b.mode === 'paint') { paints++; return o.paintDies?.(paints) ? DIED() : J({ ok: true, jpg_b64: b.jpg_b64 }); }
        if (b.mode === 'tile') { tiles++; if (o.tileDies?.(tiles, JSON.stringify(b.tile))) return DIED(); const id = 'V' + tiles; marks.set(id, b.mark); return J({ ok: true, jpg_b64: id }); }
        // Several views a worker (mode 'tiles', 17 Nov 2026): the n-th CALL dies or cuts all its views.
        if (b.mode === 'tiles') { cropCalls++; if (o.tileDies?.(cropCalls, JSON.stringify(b.views.map((v: any) => v.tile)))) { deadCalls++; return DIED(); } return J({ ok: true, jpgs: b.views.map((v: any) => { const id = 'V' + (++tiles); marks.set(id, v.mark); return id; }) }); }
        return J({ ok: false, error: 'unexpected_mode' }, 400);
      }
      if (u.pathname === '/functions/v1/ai_gateway') {
        asked++;
        const id = /base64,(V\d+)/.exec(await req.clone().text())?.[1] ?? '';
        return J({ ok: true, model: 'zz/checker', content: JSON.stringify({ mark: marks.get(id) ?? '', clean: true, addressed: false, regions: [] }) });
      }
      return undefined;
    },
  };
  const fn = await loadFunction('drawing_redact', () => import('./index.ts'));
  const r = await invoke(fn, stub, { __secret: SECRET, images: [{ mime: 'image/jpeg', data: SHEET1 }], prefix: 'redacted/zz/page', owner_customer_id: crypto.randomUUID(), owner_email: 'qd-cust@example.invalid', source_path: 'drawings/zz/zz.pdf', page_offset: 0, seed_terms: [...new Set([...seeds, ...plan.tb.setSeeds])], original_b64: bytesToB64(SET8), manual_boxes: [boxes[0]] });
  return { status: r.status, json: r.json, tiles, paints, asked, cropCalls, deadCalls, uploads: r.calls.filter((c) => c.method === 'POST' && c.url.includes('/storage/v1/object/')).length };
}

Deno.test('control: with every worker answering, the sheet is checked view by view and published', async () => {
  const r = await onePage({});
  assertEquals(r.status, 200);
  assertEquals(r.json.pages_out, 1, JSON.stringify(r.json.verify_detail));
  assertEquals(r.asked, r.tiles, 'every view cut was asked');
  assertEquals(r.uploads, 1);
});

Deno.test('a crop worker that dies (546, the isolate it shared was past the CPU cap) is asked again, and the page is published', async () => {
  const r = await onePage({ tileDies: (n) => n === 2 || n === 5 });
  assertEquals(r.json.pages_out, 1, `held: ${JSON.stringify(r.json.verify_detail)}`);
  assertEquals(r.deadCalls, 2);
  assertEquals(r.cropCalls, Math.ceil(r.tiles / VIEWS_PER_CROP) + 2, 'each dead worker was asked once more');
  assertEquals(r.asked, r.tiles, 'every view was asked once it was cut');
});

Deno.test('a paint that dies once is asked again, and the page is published', async () => {
  const r = await onePage({ paintDies: (n) => n === 1 });
  assertEquals(r.paints, 2);
  assertEquals(r.json.pages_out, 1, `held: ${JSON.stringify(r.json.verify_detail)}`);
});

Deno.test('FAIL CLOSED: a crop that never comes back holds the page, after three asks; a paint likewise', async () => {
  let dead = '';   // the first group of views asked dies every time it is cut
  const t = await onePage({ tileDies: (_n, views) => (dead ||= views) === views });
  assertEquals(t.deadCalls, 3, 'the dead worker was asked three times');
  assertEquals(t.asked, t.tiles, 'no view of the dead worker was ever shown');
  assertEquals(t.tiles, planTiles(pageSizeFromMediaBox(36 * 72, 24 * 72)).calls - VIEWS_PER_CROP, 'its views were never cut');
  assertEquals(t.json.pages_out, 0, 'views never asked: the page is held');
  assertEquals(t.uploads, 0);
  assertEquals(t.json.verify_detail[0].skipped, 'pixels_unverified');
  const p = await onePage({ paintDies: () => true });
  assertEquals(p.paints, 3, 'the paint was asked three times');
  assertEquals(p.json.pages_out, 0);
  assertEquals(p.json.verify_detail[0].skipped, 'paint_failed');
  assertEquals(p.asked, 0, 'nothing unpainted is ever shown to the checker');
});

Deno.test('a refusal of the request itself (400) is final, never asked again', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assert(/if \(r\.ok \|\| \[400, 403, 413\]\.includes\(r\.status\)\) return r;/.test(src));
  for (const mode of ['repaint', 'paint', 'tile', 'tiles']) assert(src.includes(`await workerAnswer(ask, '${mode}', stopAt)`), `${mode} goes through workerAnswer`);
});
