// scripts/e2e/document_intake_read.ts — the CODE half of the document intake accuracy suite (Deno).
// Assigned: sales_engineer (reading), it_engineer (harness). Driven by scripts/e2e/document_intake_accuracy.mjs.
//
// Every corpus document goes through the SAME modules the edge functions run, imported, not copied:
//   _shared/document_expiry.ts      the licence's fields read by code (labelled values only, never inferred)
//   _shared/supplier_doc_trades.ts  readDocForTrades: the words of a licence / profile / catalogue turned into
//                                   trade codes by exact code or by meaning (fn_norm_trades + gte-small vectors,
//                                   read live from production, read-only), the same call process_docs makes.
// Nothing is written: readDocForTrades is pure; proposeTradesFromDocs (which stores) is not called.
//
//   SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… deno run -A scripts/e2e/document_intake_read.ts <corpus dir> <out.json>
import { createClient } from 'jsr:@supabase/supabase-js@2';
import * as DX from '../../supabase/functions/_shared/document_expiry.ts';
import { readDocForTrades, type DocKind } from '../../supabase/functions/_shared/supplier_doc_trades.ts';
import { liveTradeDeps } from '../../supabase/functions/_shared/trade_resolve.ts';

const [dir, outPath] = Deno.args;
if (!dir || !outPath) { console.error('usage: <corpus dir> <out.json>'); Deno.exit(2); }
const truth = JSON.parse(await Deno.readTextFile(`${dir}/truth.json`));
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
// With a rehearsal tag (the harness's model window) a profile's or catalogue's trades are chosen by the model, tagged and
// capped; without one the chooser is left out and the read is code alone (stated in code.json: model_choice).
const TAG = Deno.env.get('QD_RUN_TAG');
const deps = await liveTradeDeps(admin, 'document_intake_accuracy', TAG ? { subject: JSON.parse(Deno.env.get('QD_SUBJECT') || 'null'),
  headers: { Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`, 'x-qd-e2e-run': TAG, 'x-qd-e2e-secret': Deno.env.get('QD_E2E_SECRET') || '' } } : {});
if (!TAG) deps.chooseTrades = undefined;
const budget0 = deps.budget.left;

// deno-lint-ignore no-explicit-any
const anyDX = DX as any;
const out: Record<string, unknown>[] = [];
for (const d of truth.docs) {
  if (!d.file) { out.push({ id: d.id, code: null, trades: null }); continue; }
  const bytes = await Deno.readFile(`${dir}/${d.file}`);
  const isPdf = /pdf/i.test(d.mime);
  const text = isPdf ? await DX.pdfText(bytes) : null;
  // The reader as deployed reads the name and the expiry; the field reader (7 Oct 2026) reads every labelled field.
  const code = typeof anyDX.readLicenceFields === 'function'
    ? await anyDX.readLicenceFields(bytes, d.mime)
    : { legal_name_en: await DX.readLicenceName(bytes, d.mime), expiry_date: (await DX.readExpiry(bytes, d.mime))?.expiry ?? null };
  deps.budget.left = budget0;   // one process_docs call per supplier: each document starts with the full meaning budget
  const kind: DocKind = d.kind === 'licence' ? 'licence' : d.kind === 'catalogue' ? 'catalogue' : 'profile';
  const ev = await readDocForTrades({ path: `corpus/${d.file}`, name: d.file, kind, bytes, mime: d.mime, names: [d.registered_name ?? null] }, deps);
  out.push({ id: d.id, text_chars: text?.length ?? 0, code,
    trades: { status: ev.status, reason: ev.reason ?? null, codes: [...new Set((ev.trades || []).map((t) => t.code))].sort(),
              hits: (ev.trades || []).map((t) => ({ code: t.code, via: t.via, phrases: t.phrases, snippet: t.snippet, similarity: t.similarity ?? null })),
              exact: ev.exact ?? null, meaning: ev.meaning ?? null, choice: ev.choice ?? null, rejected: ev.rejected ?? null } });
}
await Deno.writeTextFile(outPath, JSON.stringify({ read_at: new Date().toISOString(), model_choice: !!TAG, field_reader: typeof anyDX.readLicenceFields === 'function', docs: out }, null, 1));
console.log(`read ${out.length} documents -> ${outPath}`);
