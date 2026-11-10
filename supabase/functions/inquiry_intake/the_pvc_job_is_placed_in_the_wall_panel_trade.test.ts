// THE REAL inquiry_intake HANDLER PLACES A JOB IN THE TRADE ITS SERVICES BELONG TO (sales_engineer; evidence run of
// 10 Nov 2026, ledger 1604, finding b1). Offline: fetch and env stubbed (_shared/twilio_free_harness.ts); the model is a stub.
// The model answered the PVC wall-panel job exactly as on production: trade_codes [interior_fitout, joinery], slugs
// [interior-design, carpentry-joinery], and the four service keys. The request must come out placed in wallpaper, one
// trade, asking the wall-panel checklist's blocking specs — not a fit-out's "MEP scope" and "authority approvals".
// Run: deno test --no-lock --node-modules-dir=none -A supabase/functions/inquiry_intake/the_pvc_job_is_placed_in_the_wall_panel_trade.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-pvc-customer@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const fn = () => loadFunction('inquiry_intake', () => import('./index.ts'));
const TAX = ['wallpaper', 'joinery', 'interior_fitout'].map((code) => ({ code, label: code, group_code: 'construction_building', authority_required: [] }));
const FIELDS = [{ key: 'describe', type: 'text', options: [], question: 'Describe it', required: true }];
const CHECKLISTS = [
  { trade_code: 'interior_fitout', topic_id: 'interior_fitout:fitout-spec-checklist', topic: 'fit-out', pack_order: 0,
    specs: [{ code: 'spec_mep_scope', label_en: 'MEP scope' }, { code: 'spec_authority_approvals_and_responsibility', label_en: 'Authority approvals and responsibility' }],
    blocking: ['spec_mep_scope', 'spec_authority_approvals_and_responsibility'], spec_guide: [], site_visit_required_when: null },
  { trade_code: 'joinery', topic_id: 'joinery:spec-checklist', topic: 'joinery', pack_order: 0,
    specs: [{ code: 'spec_core_material_and_thickness', label_en: 'core material and thickness' }], blocking: ['spec_core_material_and_thickness'], spec_guide: [], site_visit_required_when: null },
  { trade_code: 'wallpaper', topic_id: 'wallpaper:spec-checklist', topic: 'wall panels', pack_order: 0,
    specs: [{ code: 'spec_panel_material_and_thickness', label_en: 'panel material and thickness' }, { code: 'spec_wall_area_m2', label_en: 'wall area in square metres' }],
    blocking: ['spec_panel_material_and_thickness', 'spec_wall_area_m2'], spec_guide: [], site_visit_required_when: null },
];
const SERVICES = [['wallpaper', 'wall_cladding'], ['wallpaper', 'wall_panels'], ['interior_fitout', 'refurbishment'], ['joinery', 'wood_panelling']]
  .map(([trade_code, code]) => ({ trade_code, code, label_en: code }));
const MODEL = { category: 'interior-design', trades: ['interior-design', 'carpentry-joinery'], status: 'needs_info', claims_ready: false,
  assistant_message: 'Understood. How large is the wall, roughly in square metres?', questions: ['How large is the wall?'], missing: [], readiness: 60, dialect: 'english',
  trade_codes: ['interior_fitout', 'joinery'], service_keys: ['wallpaper.wall_cladding', 'wallpaper.wall_panels', 'interior_fitout.refurbishment', 'joinery.wood_panelling'],
  condition: { object: 'PVC wall panels on an MDF partition', condition: 'old, scratched, some coming off' }, problem: '', options_offered: [], chosen_option: '', budget: '',
  brief: { details: { describe: 'ZZ DEMO remove old PVC wall panels and install new ones on the MDF partition' } } };

function world() {
  const w = { rpcs: [] as { fn: string; args: Row }[], intake: { id: 'ii-zz-pvc', email: EMAIL, status: 'needs_info', turns: [], customer_id: 'c-zz-pvc', category: null, brief: {} } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-pvc', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-pvc', locale: 'en' }],
      category_specs: ['interior-design', 'carpentry-joinery', 'wallpaper'].map((category) => ({ category, label: category, fields: FIELDS })),
      taxonomy_trade: TAX, taxonomy_trade_service: SERVICES, trade_spec_checklist: CHECKLISTS, sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      const r = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (u.pathname.startsWith('/functions/v1/')) {
        const body = await req.clone().json().catch(() => ({}));
        if (body.fn === 'inquiry_intake' && body.response_format) return J({ ok: true, content: JSON.stringify(MODEL), model: 'stub/model' });
        return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO: noted.' }), model: 'stub/model' });
      }
      if (r) { const args = await req.clone().json().catch(() => ({})); w.rpcs.push({ fn: r, args }); if (r === 'rl_check') return J(true); return J(null); }
      if (t === 'inquiry_state' && req.method === 'GET') return J([]);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json()); return J([]); }
      }
      return undefined;
    },
  };
  return { w, stub };
}

Deno.test('RFQ 164464 replayed: the PVC wall-panel job is placed in wallpaper, one trade, and asks the wall-panel checklist', async () => {
  const h = await fn();
  const { w, stub } = world();
  const r = await invoke(h, stub, { text: 'ZZ DEMO In our office in Business Bay, Dubai, we have an MDF partition wall covered with PVC wall panels. The panels are old, scratched and some are coming off. We want the old PVC panels removed and new PVC wall panels installed on the same MDF partition.', turn_id: 't-zz-pvc-1', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assertEquals([r.json.category, r.json.trades], ['wallpaper', ['wallpaper']], 'placed in the wall-panel trade, one trade');
  const merge = w.rpcs.filter((x) => x.fn === 'fn_inquiry_state_merge').map((x) => x.args.p_patch as Row).at(-1)!;
  assertEquals(merge.trade_codes, ['wallpaper']);
  assertEquals((merge.specs as Row).service_keys, 'wallpaper.wall_cladding, wallpaper.wall_panels', 'the placed trade\'s services only');
  const open = (r.json.blocking as { open: string[] }).open;
  assert(open.includes('spec_panel_material_and_thickness') && open.includes('spec_wall_area_m2'), JSON.stringify(open));
  assert(!open.includes('spec_mep_scope') && !open.includes('spec_authority_approvals_and_responsibility') && !open.includes('spec_core_material_and_thickness'), 'a fit-out or joinery spec was asked of a wall-panel job: ' + JSON.stringify(open));
});
