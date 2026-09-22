// dwg_takeoff — the edge's DWG reader with no size ceiling, for where there is no 2 s CPU cap (22 Sep 2026).
//
// supabase/functions/_shared/doc_read/dwg.ts reads DWGs up to DWG_MAX_BYTES inside an edge function and
// answers needs:'cad_conversion' past it. This runs the SAME reader (LibreDWG WASM -> ASCII DXF ->
// readDxf) on a laptop or a CI worker and prints the take-off as JSON, so a large drawing is measured by
// the same code rather than a second one.
//
//   deno run --no-lock --node-modules-dir=auto --allow-net=cdn.jsdelivr.net --allow-read --allow-env <file.dwg>
//
// HAND-OFF NOT BUILT: nothing in the platform dispatches a large upload here yet. That needs a result
// table and a dispatcher (a GitHub Actions workflow_dispatch that reads the file from storage and writes
// the result back), which is the coordinator's call. Until then the customer is told to send DXF or PDF.
import { readDwg } from '../supabase/functions/_shared/doc_read/dwg.ts';

const file = Deno.args[0];
if (!file) { console.error('usage: dwg_takeoff.ts <file.dwg>'); Deno.exit(2); }
const r = await readDwg(Deno.readFileSync(file), { filename: file, depth: 0 }, Infinity);
console.log(JSON.stringify(r, null, 2));
Deno.exit(r.ok && r.needs === null ? 0 : 1);
