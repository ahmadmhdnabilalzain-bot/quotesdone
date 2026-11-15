// A SITE-VISIT JOB ASKS ONCE FOR PHOTOS, AND NEVER HOLDS FOR THEM (15 Nov 2026, sales_engineer; founder ledger 1704: "For stuff that
// requires a site visit. The sales engineer should ask for photos. It will make it easier for suppliers to quote.").
//
// Offline, stub model, the REPOSITORY packs through the loader's own mapping and the runtime's own reader (as
// a_request_is_ready_only_when_every_blocking_spec_is_answered.test.ts does).
//   1. WHEN: only when the model put the trade in "site_visit", and only for a checklist that names shots; a job with no visit
//      asks nothing; a checklist whose sentence names a file asks nothing.
//   2. ONCE: a turn stamped photo_ask, or a record that holds `asked`, means never again.
//   3. WORDING PER TRADE: the shots are the job checklist's own, in the customer's language; the draft says photos are optional.
//   4. OPTIONAL: readiness and the blocking gate never read photos: a ready request with no photo stays ready.
//   5. THE RECORD: photos by check job, a shot kept only when it was asked, a retry never adds one twice; the suppliers' notes say
//      which shots exist and which do not, counting only copies the check released.
//   6. THE HANDLER: the turn a visit applies answers photo_ask with the shots, stays ready, stamps the turn and keeps the record;
//      the next turn asks nothing and the prompt no longer carries the photo block.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { checklistsOf as loaderRows } from '../../../scripts/kb/load_trade_spec_checklists.mjs';
import { activeChecklists, checklistsOf, readinessOf, universalOf, type TradeContext } from '../_shared/inquiry_trades.ts';
import { blockingGate } from './blocking_gate.ts';
import { askedBefore, forSpec, photoAskDraft, photoAskNow, photoPromptBlock, shotsFor, siteNotes, withPhotos } from '../_shared/site_photos.ts';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const ROOT = new URL('../../../', import.meta.url);
type Row = Record<string, unknown>;
// deno-lint-ignore no-explicit-any
const packOf = (code: string): any => JSON.parse(Deno.readTextFileSync(new URL(`knowledge/packs/${code}.json`, ROOT)));
// deno-lint-ignore no-explicit-any
const tableRows = (codes: string[]): Row[] => codes.flatMap((c) => loaderRows(packOf(c), c + '.json').map(({ refused: _r, ...r }: any) => r));
function ctxOf(codes: string[]): TradeContext {
  const checklists = checklistsOf(tableRows(codes));
  return { codes, trades: codes.map((c) => ({ code: c, label: c, group_code: null })), services: [], specs: Object.fromEntries(codes.map((c) => [c, (checklists[c] ?? []).flatMap((k) => k.specs)])), approvals: {}, checklists };
}
function blockingKeys(ctx: TradeContext, topics: string[] = []): string[] {
  const out: string[] = [];
  for (const lists of Object.values(activeChecklists(ctx, topics))) for (const c of lists) for (const code of c.blocking) {
    const k = universalOf(c.specs.find((s) => s.code === code)!.label_en) ?? code;
    if (!out.includes(k)) out.push(k);
  }
  return out;
}
const JOB = (n: number) => `${String(n).padStart(8, '0')}-0000-4000-8000-000000000000`;

Deno.test('the ask fires only for a site-visit job whose checklist names shots', () => {
  const hvac = ctxOf(['hvac']);
  assertEquals(photoAskNow(hvac, ['hvac:spec-split-ac'], [], [], null), [], 'asked with no site visit');
  const shots = photoAskNow(hvac, ['hvac:spec-split-ac'], ['hvac'], [], null);
  assertEquals(shots.length, 6);
  assertEquals(shots[0].shot, 'Each indoor unit, from the front');
  assert(shots.every((s) => s.trade === 'hvac' && s.topic_id === 'hvac:spec-split-ac'));
  // a trade placed but not in site_visit adds nothing; two trades with visits share one list of at most six
  const two = ctxOf(['hvac', 'painting']);
  assertEquals(shotsFor(two, ['hvac:spec-split-ac', 'painting:interior-repaint-spec'], ['painting']).every((s) => s.trade === 'painting'), true);
  assert(shotsFor(two, ['hvac:spec-split-ac', 'painting:interior-repaint-spec'], ['hvac', 'painting']).length <= 6);
  // a checklist whose sentence names a file (a machined part needs the drawing) asks for no photo even when "site_visit" names it
  assertEquals(photoAskNow(ctxOf(['cnc_machining']), [], ['cnc_machining'], [], null), []);
});

Deno.test('asked once: a stamped turn or a record that holds the ask means never again', () => {
  const hvac = ctxOf(['hvac']);
  const turns = [{ role: 'user', text: 'x' }, { role: 'assistant', text: 'y', photo_ask: ['Each indoor unit, from the front'] }, { role: 'user', text: 'no photos sorry' }];
  assert(askedBefore(turns, null));
  assertEquals(photoAskNow(hvac, [], ['hvac'], turns, null), []);
  assertEquals(photoPromptBlock(hvac, [], turns, null), '', 'the prompt still offers the ask after it was made');
  const rec = withPhotos(null, shotsFor(hvac, [], ['hvac']), []);
  assertEquals(photoAskNow(hvac, [], ['hvac'], [], rec), []);
  assert(photoPromptBlock(hvac, [], [], null).startsWith('PHOTOS FOR A SITE-VISIT JOB'), 'no photo block before the ask');
});

Deno.test('wording per trade, in the customer\'s language, and the draft says photos are optional', () => {
  const paint = shotsFor(ctxOf(['painting']), ['painting:interior-repaint-spec'], ['painting']).map((s) => s.shot.toLowerCase()).join(' | ');
  assertMatch(paint, /wall/); assertMatch(paint, /damp/);
  const roof = shotsFor(ctxOf(['waterproofing']), ['waterproofing:spec-roof-waterproofing'], ['waterproofing']).map((s) => s.shot.toLowerCase()).join(' | ');
  assertMatch(roof, /roof/); assertMatch(roof, /leak/);
  const pool = shotsFor(ctxOf(['swimming_pools']), [], ['swimming_pools']).map((s) => s.shot.toLowerCase()).join(' | ');
  assertMatch(pool, /way in for workers/); assertMatch(pool, /ground/);
  const hv = shotsFor(ctxOf(['hvac']), [], ['hvac']);
  const en = photoAskDraft(hv, 'en');
  assertMatch(en, /^A final price may need a site visit\./); assertMatch(en, /optional/); assertMatch(en, /Each outdoor unit and where it sits/);
  const ar = photoAskDraft(hv, 'ar');
  assertMatch(ar, /اختيارية/); assertMatch(ar, /كل وحدة خارجية ومكانها/);
  assertMatch(photoPromptBlock(ctxOf(['hvac']), [], [], null, 'ar'), /كل وحدة داخلية/);
});

Deno.test('photos are optional: a ready request with no photo stays ready, and readiness never reads photos', () => {
  const ctx = ctxOf(['hvac']);
  const specs = Object.fromEntries(blockingKeys(ctx).map((k) => [k, 'ZZ DEMO stated']));
  const r = readinessOf(ctx, [], specs, [], ['hvac']);
  assert(r.ready, JSON.stringify(r.open));
  assertEquals(blockingGate('ready', ctx, [], specs, [], ['hvac']).status, 'ready');
  const src = Deno.readTextFileSync(new URL('supabase/functions/_shared/inquiry_trades.ts', ROOT)) + Deno.readTextFileSync(new URL('supabase/functions/inquiry_intake/blocking_gate.ts', ROOT));
  assert(!/photo_ask|site_photos|photosNow/.test(src.replace(/\/\/.*$/gm, '')), 'the readiness rule reads photos');
});

Deno.test('the record: by check job, the asked shot kept, a retry never twice; the suppliers are told what exists and what does not', () => {
  const asked = shotsFor(ctxOf(['hvac']), [], ['hvac']);
  let rec = withPhotos(null, asked, [{ shot: asked[1].shot, job_id: JOB(1) }, { shot: 'my passport', job_id: JOB(2) }, { shot: asked[0].shot, job_id: 'not-a-job' }]);
  assertEquals(rec.photos, [{ shot: asked[1].shot, job_id: JOB(1), via: 'portal' }, { shot: null, job_id: JOB(2), via: 'portal' }]);
  rec = withPhotos(rec, [], [{ shot: asked[1].shot, job_id: JOB(1) }, { job_id: JOB(3) }], 'whatsapp');
  assertEquals(rec.photos.length, 3, 'a retry added a photo twice');
  assertEquals(rec.photos[2], { shot: null, job_id: JOB(3), via: 'whatsapp' });
  assertEquals(rec.asked.length, 6, 'the ask was lost');
  // only released copies count: photo 1 released, photo 2 withheld, photo 3 released
  const n = siteNotes(rec, new Set([JOB(1), JOB(3)]));
  assertEquals(n.provided, [asked[1].shot]);
  assertEquals(n.not_provided.length, 5);
  assertEquals([n.extra, n.withheld], [1, 1]);
  const spec = forSpec(rec)!;
  assertEquals(spec.photos.map((p) => p.via), ['portal', 'portal', 'whatsapp']);
  assertEquals(forSpec({ nonsense: true }), null);
});

// ── the handler ────────────────────────────────────────────────────────────────────────────────────────────────────────
const EMAIL = 'zz-demo-photos-customer@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
function world(model: Row, intake: Row) {
  const w = { prompts: [] as string[], intake: { id: 'ii-zz-photos', email: EMAIL, status: 'needs_info', turns: [], customer_id: 'c-zz-photos', category: null, brief: {}, ...intake } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-photos', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-photos', locale: 'en' }], category_specs: [{ category: 'general', label: 'x', fields: [] }],
      taxonomy_trade: [{ code: 'hvac', label: 'HVAC', group_code: 'mep_building_systems', authority_required: [] }],
      taxonomy_trade_service: [], trade_spec_checklist: tableRows(['hvac']), sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      const r = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (u.pathname.startsWith('/functions/v1/')) {
        const body = await req.clone().json().catch(() => ({}));
        if (body.fn === 'inquiry_intake' && body.response_format) { w.prompts.push(String(body.sys)); return J({ ok: true, content: JSON.stringify(model), model: 'stub/model' }); }
        return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO: a final price may need a visit; photos of the units would help, and they are optional.' }), model: 'stub/model' });
      }
      if (r) return J(r === 'rl_check' ? true : null);
      if (t === 'inquiry_state' && req.method === 'GET') return J([{ conv_key: 'intake:ii-zz-photos', surface: 'request_chat', specs: {}, unknown: {}, asked: {}, message_count: 2, status: 'open', trade_codes: ['hvac'] }]);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json()); return J([]); }
      }
      return undefined;
    },
  };
  return { w, stub };
}
const fnOf = () => loadFunction('inquiry_intake', () => import('./index.ts'));
const readyModel = (siteVisit: string[]) => {
  const keys = blockingKeys(ctxOf(['hvac']));
  const details = { ...Object.fromEntries(keys.filter((k) => k !== 'location').map((k) => [k, 'ZZ DEMO stated'])), location: 'Dubai' };
  return { category: 'general', trades: ['general'], status: 'ready', claims_ready: true, assistant_message: 'All set: your request is ready to send.', questions: [], missing: [], readiness: 100,
    dialect: 'english', trade_codes: ['hvac'], service_keys: [], checklist_topics: ['hvac:spec-split-ac'], site_visit: siteVisit, photos_asked: false, condition: {}, problem: '', options_offered: [], chosen_option: '', budget: '',
    brief: { summary: 'replace split AC units', emirate: 'Dubai', details } };
};

Deno.test('the handler: the turn a visit applies asks once, changes no status, stamps the turn; the next turn asks nothing', async () => {
  // the same turn without the visit is the control: the ask must not move the status, the open keys or the blocking verdict
  const control = await invoke(await fnOf(), world(readyModel([]), {}).stub, { intake_id: 'ii-zz-photos', text: 'ZZ DEMO replace three wall splits in a villa in Dubai', turn_id: 't-zz-photos-0', lang: 'en' });
  const { w, stub } = world(readyModel(['hvac']), {});
  const r = await invoke(await fnOf(), stub, { intake_id: 'ii-zz-photos', text: 'ZZ DEMO replace three wall splits in a villa in Dubai', turn_id: 't-zz-photos-1', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assertEquals([r.json.status, JSON.stringify(r.json.missing_keys), JSON.stringify((r.json.blocking as Row).open)],
    [control.json.status, JSON.stringify(control.json.missing_keys), JSON.stringify((control.json.blocking as Row).open)], 'the photo ask moved the status or the open specs');
  assert(r.json.status !== 'held');
  const ask = r.json.photo_ask as { optional: boolean; shots: { shot: string }[] };
  assert(ask && ask.optional === true && ask.shots.length === 6, JSON.stringify(r.json.photo_ask));
  assert(w.prompts[0].includes('PHOTOS FOR A SITE-VISIT JOB'), 'the prompt does not carry the shots');
  const turns = w.intake.turns as Row[];
  const last = turns.filter((t) => t.role === 'assistant').at(-1)!;
  assertEquals((last.photo_ask as string[]).length, 6, 'the asking turn is not stamped');
  assertEquals(((w.intake.brief as Row).site_photos as Row & { asked: unknown[] }).asked.length, 6, 'the record does not keep the ask');
  // the next turn: the customer says no photos; nothing is asked again and it stays ready
  const again = await invoke(await fnOf(), stub, { intake_id: 'ii-zz-photos', text: 'ZZ DEMO no photos, sorry', turn_id: 't-zz-photos-2', lang: 'en' });
  assertEquals(again.json.photo_ask, null, 'asked twice');
  assert(again.json.status !== 'held', 'held after "no photos"');
  assert(!w.prompts[1].includes('PHOTOS FOR A SITE-VISIT JOB'), 'the prompt offers the ask again');
});

Deno.test('the handler: a job with no site visit asks for no photo', async () => {
  const { stub } = world(readyModel([]), {});
  const r = await invoke(await fnOf(), stub, { intake_id: 'ii-zz-photos', text: 'ZZ DEMO three new wall splits for a new villa in Dubai', turn_id: 't-zz-photos-3', lang: 'en' });
  assertEquals(r.status, 200);
  assertEquals(r.json.photo_ask, null);
  assertEquals(r.json.site_photos, null);
});
