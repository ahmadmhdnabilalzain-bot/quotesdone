// THE SEAT EXAM, MODEL ON (ledger 1084, 19 Oct 2026). Seat: it_engineer. The answering half of
// scripts/eval/seat_exam_llm_on.mjs, which opens the run's window, chooses the items, grades and records.
//
// Each item is put to the seat through think() itself, end to end (decompose, retrieve, synthesise, verify), the
// way the seat answers at work. No step is stubbed. The calls carry the run's tag (E2E_RUN), so they are let through
// only inside that run's open, capped rehearsal window and are logged against it in ai_cost_log.
//
//   deno run -A --node-modules-dir=none scripts/eval/seat_exam_llm_on.ts <in.json> <out.json>
//   in.json: [{ "id": "...", "seat": "sales_engineer", "wording": "..." }]   env: QD_E2E_RUN_TAG, QD_E2E_SECRET
const REF = 'htdblwldjkcgjvmqkbeh';
const [inFile, outFile] = Deno.args;
const tag = Deno.env.get('QD_E2E_RUN_TAG') ?? '';
const secret = Deno.env.get('QD_E2E_SECRET') ?? '';
if (!inFile || !outFile || !/^[a-z0-9]{4,16}$/.test(tag) || !secret) throw new Error('usage: <in.json> <out.json> with QD_E2E_RUN_TAG and QD_E2E_SECRET set');

const home = Deno.env.get('USERPROFILE') ?? Deno.env.get('HOME') ?? '';
const mgmt = (Deno.env.get('SUPABASE_ACCESS_TOKEN') ?? await Deno.readTextFile(`${home}/.supabase/access-token`).catch(() => '')).trim();
if (!mgmt) throw new Error('SUPABASE_ACCESS_TOKEN is not set (docs/runbooks/cloud-sessions.md)');
const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: `Bearer ${mgmt}` } })).json();
const service = keys.find((k: { name: string }) => k.name === 'service_role')?.api_key;
if (!service) throw new Error('no service_role key from the management API');
// llm.ts and e2e_run.ts read these at import, so they are set before the dynamic imports below.
Deno.env.set('SUPABASE_URL', `https://${REF}.supabase.co`);
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', service);
const { createClient } = await import('jsr:@supabase/supabase-js@2');
const { think, defaultDeps } = await import('../../supabase/functions/_shared/think.ts');
const { E2E_RUN } = await import('../../supabase/functions/_shared/e2e_run.ts');
const admin = createClient(`https://${REF}.supabase.co`, service, { auth: { persistSession: false } });

const items = JSON.parse(await Deno.readTextFile(inFile)) as { id: string; seat: string; wording: string }[];
const out: Record<string, unknown>[] = [];
for (const it of items) {
  // A held answer keeps the model's own last words, so the cause of a hold is read, not guessed.
  const llmTrail: { phase: string; content: string; error: string | null }[] = [];
  const retrieved: Record<string, unknown>[] = [];   // what retrieval handed the seat, per planned step
  const r = await E2E_RUN.run({ tag, secret }, async () => {
    const live = defaultDeps(admin as never, 'knowledge_exam');   // the exam's own gateway credential: app_secrets.cred_fn_knowledge_exam
    const deps = { ...live, llm: async (...a: Parameters<typeof live.llm>) => {
      const x = await live.llm(...a);
      llmTrail.push({ phase: String(a[0]), content: String(x.content ?? '').slice(0, 1500), error: x.error ?? null });
      return x;
    }, rpc: async (f: string, args: Record<string, unknown>) => {
      const x = await live.rpc(f, args);
      if (/^fn_reason_retrieve/.test(f)) retrieved.push({ fn: f, trade: args.p_trade ?? null, kind: args.p_kind ?? null, area: args.p_area ?? null,
        top: (Array.isArray(x.data) ? x.data : []).slice(0, 6).map((r: { source: string; id: string; similarity: number }) => `${r.source}:${r.id}@${Number(r.similarity).toFixed(3)}`), error: x.error?.message ?? null });
      return x;
    } };
    try {
      return await think(deps as never,
        { seat: it.seat as never, surface: 'think.answer', question: it.wording, context: { audience: 'internal' } as never, subject: { fixture: true } as never });
    } catch (e) { return { status: 'error', answer: '', reason: (e as Error).message } as never; }
  });
  out.push({ id: it.id, seat: it.seat, wording: it.wording, status: r.status, answer: r.answer ?? '', model: r.model ?? null,
             reason: r.reason ?? null, ...(r.status === 'answered' ? {} : { llm_trail: llmTrail }), retrieved, verified: r.verified?.status ?? null, sources: (r.sources ?? []).map((s: { id: string }) => s.id).slice(0, 8) });
  console.log(`${it.id} ${r.status} ${(r.answer ?? '').slice(0, 90).replace(/\n/g, ' ')}`);
}
await Deno.writeTextFile(outFile, JSON.stringify(out, null, 1));
