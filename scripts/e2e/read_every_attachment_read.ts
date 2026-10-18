// scripts/e2e/read_every_attachment_read.ts — reads the ZZ DEMO sample through the REAL readers (Deno).
// Assigned: sales_engineer + customer_support (reading), it_engineer (harness). Driven by read_every_attachment_accuracy.mjs.
//
// Every file goes through _shared/read_every_attachment (code first, then the vision model on ai_gateway's existing
// extract_text route, one more asking), and each quotation also through supplier_api/quote_review_flow
// readQuotationFile — the reader the supplier's quotation review uses. The model is reached ONLY inside the run's own
// tagged rehearsal window (x-qd-e2e-run + x-qd-e2e-secret + the service-role bearer, ledger 1119), for the ZZ DEMO
// subject the harness created; the window's cap is enforced by fn_kernel_paid_provider_gate.
//
//   SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY QD_RUN_TAG QD_SUBJECT QD_SECRET QD_E2E_SECRET deno run -A … <corpus> <out.json> <model|none>
import { readEveryAttachment, gatewayVision, type Vision } from '../../supabase/functions/_shared/read_every_attachment.ts';
import { readQuotationFile } from '../../supabase/functions/supplier_api/quote_review_flow.ts';

const [dir, outPath, mode] = Deno.args;
const URL_ = Deno.env.get('SUPABASE_URL')!, SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TAG = Deno.env.get('QD_RUN_TAG') || '', SUBJECT = JSON.parse(Deno.env.get('QD_SUBJECT') || 'null');
let vision: Vision | null = null;
let calls = 0;
if (mode === 'model') {
  if (!/^[a-z0-9]{4,16}$/.test(TAG) || !SUBJECT) { console.error('QD_RUN_TAG and QD_SUBJECT are required'); Deno.exit(2); }
  const base = gatewayVision(`${URL_}/functions/v1/ai_gateway`, Deno.env.get('QD_SECRET')!, { subject: SUBJECT,
    headers: { Authorization: `Bearer ${SERVICE}`, 'x-qd-e2e-run': TAG, 'x-qd-e2e-secret': Deno.env.get('QD_E2E_SECRET') || '' } });
  vision = async (r) => { calls++; const a = await base(r); if (!a.ok) console.log(`  model: ${a.why}`); return a; };
}
const truth = JSON.parse(await Deno.readTextFile(`${dir}/truth.json`));
const out: Record<string, unknown>[] = [];
for (const d of truth.docs) {
  const bytes = await Deno.readFile(`${dir}/${d.file}`);
  const before = calls; const t0 = Date.now();
  const a = await readEveryAttachment(bytes, d.file, d.mime, vision);
  const low = a.text.toLowerCase().replace(/[,\s]+/g, ' ');
  const found = d.must.filter((w: string) => low.includes(w));
  const row: Record<string, unknown> = { id: d.id, path: d.path, degraded: d.degraded, status: a.status, by: a.by, model_attempts: a.model_attempts,
    reason: a.reason, must: d.must, found, words_ok: found.length === d.must.length, chars: a.text.length, ms: Date.now() - t0 };
  if (d.total) {
    const q = await readQuotationFile(bytes, d.file, d.mime, [], undefined, vision);
    row.quote_total = q.proposal?.amount ?? null; row.quote_total_ok = q.proposal?.amount === d.total;
  }
  row.model_calls = calls - before;
  out.push(row);
  console.log(`${d.id}: ${a.status} by ${a.by ?? '-'} (${found.length}/${d.must.length} words${d.total ? ', total ' + row.quote_total : ''})`);
}
await Deno.writeTextFile(outPath, JSON.stringify({ mode, run_tag: TAG || null, read_at: new Date().toISOString(), model_calls: calls, docs: out }, null, 1));
