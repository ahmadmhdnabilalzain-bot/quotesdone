// ONE drawing_boq request in a fresh process, as a fresh edge worker would run it, for a_duct_run_is_measured_sheet_by_sheet
// .test.ts. The request body arrives on stdin; the REAL handler (index.ts, every network edge stubbed by twilio_free_harness)
// answers it once, and this prints {status, json, cpu_ms} - cpu_ms being THIS process's CPU over the handler call only (the
// module load is not counted). Its own process, so no other test's work is counted in it (17 Nov 2026: measured in the test's
// process, the drawing_boq + customer_api run counted the other files' async work and failed).
import process from 'node:process';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const stub: Stub = { rpc: { fn_internal_auth: { ok: true, context: 'fn.customer_api', credential_id: 7, legacy: false } }, handle: async () => undefined };
const fn = await loadFunction('drawing_boq', () => import('./index.ts'));
const body = JSON.parse(await new Response(Deno.stdin.readable).text());
const cpu = () => { const u = process.cpuUsage(); return (u.user + u.system) / 1000; };
const t0 = cpu();
const r = await invoke(fn, stub, body);
const cpu_ms = Math.round(cpu() - t0);
console.log(JSON.stringify({ status: r.status, json: r.json, cpu_ms }));
