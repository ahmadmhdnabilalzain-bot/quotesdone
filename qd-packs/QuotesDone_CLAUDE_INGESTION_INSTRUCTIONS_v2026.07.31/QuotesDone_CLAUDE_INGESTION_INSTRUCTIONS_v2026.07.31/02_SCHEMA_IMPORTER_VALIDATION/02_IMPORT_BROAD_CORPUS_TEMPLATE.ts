/**
 * Token-free corpus importer: streams package files directly into Supabase.
 * Install: npm i @supabase/supabase-js csv-parse
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, KB_CORPUS_ROOT
 */
import { createClient } from '@supabase/supabase-js';
import { createReadStream, promises as fs } from 'node:fs';
import { createInterface } from 'node:readline';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { parse } from 'csv-parse/sync';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const root = process.env.KB_CORPUS_ROOT;
if (!url || !key || !root) throw new Error('Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY or KB_CORPUS_ROOT');
const supabase = createClient(url, key, { auth: { persistSession: false } });
const BATCH = Number(process.env.KB_BATCH_SIZE || 500);

function sha256(value: string): string { return createHash('sha256').update(value).digest('hex'); }
async function upsert(table: string, rows: unknown[], onConflict: string) {
  if (!rows.length) return;
  const { error } = await supabase.schema('kb_stage').from(table).upsert(rows as any[], { onConflict });
  if (error) throw new Error(`${table}: ${error.message}`);
}
async function* readJsonl(file: string) {
  const rl = createInterface({ input: createReadStream(file, { encoding: 'utf8' }), crlfDelay: Infinity });
  let lineNo=0;
  for await (const line of rl) { lineNo++; if (!line.trim()) continue; yield { lineNo, value: JSON.parse(line) }; }
}
async function importSources(file: string) {
  const text=await fs.readFile(file,'utf8');
  const rows=parse(text,{columns:true,skip_empty_lines:true});
  await upsert('sources', rows.map((r:any)=>({source_id:r.source_id,title:r.title,publisher:r.publisher||null,url:r.url||null,source_type:r.source_type||null,jurisdiction:r.jurisdiction||null,published_date:r.published_date||null,accessed_date:r.accessed_date||null,notes:r.notes||null,raw:r})), 'source_id');
}
async function importRecords(file:string, runId:string) {
  let batch:any[]=[];
  for await (const {lineNo,value:r} of readJsonl(file)) {
    if (!r.record_id) throw new Error(`${file}:${lineNo} missing record_id`);
    const contentSha=sha256(JSON.stringify(r));
    batch.push({...r, source_ids:r.source_ids||[], keywords_en:r.keywords_en||[], keywords_ar:r.keywords_ar||[], exceptions:r.exceptions||[], ingestion_run_id:runId, content_sha256:contentSha});
    if (batch.length>=BATCH) { await upsert('records',batch,'record_id'); batch=[]; }
  }
  await upsert('records',batch,'record_id');
}
async function importPackage(dir:string) {
  const manifest=JSON.parse(await fs.readFile(path.join(dir,'21_ingestion_manifest.json'),'utf8'));
  const pkg=JSON.parse(await fs.readFile(path.join(dir,'01_manifest.json'),'utf8'));
  const packageId=pkg.package_id;
  const version=pkg.version || pkg.package_version || manifest.version || 'unknown';
  const zipHash=pkg.zip_sha256 || null;
  const { data:runRows, error:runErr }=await supabase.schema('kb_stage').from('ingestion_runs').upsert({package_id:packageId,package_version:version,package_sha256:zipHash,status:'started'},{onConflict:'package_id,package_version,package_sha256'}).select('id').limit(1);
  if (runErr || !runRows?.[0]) throw new Error(runErr?.message || 'Cannot create ingestion run');
  const runId=runRows[0].id;
  await importSources(path.join(dir,'19_source_registry.csv'));
  // Claude should add taxonomy import mapped to the exact generated taxonomy shape.
  for (const file of manifest.load_order || []) {
    if (!file.endsWith('.jsonl')) continue;
    await importRecords(path.join(dir,file),runId);
  }
  const { error }=await supabase.schema('kb_stage').from('ingestion_runs').update({status:'imported',completed_at:new Date().toISOString()}).eq('id',runId);
  if (error) throw error;
  console.log(JSON.stringify({packageId,runId,status:'imported'}));
}

const dirs=(await fs.readdir(root,{withFileTypes:true})).filter(x=>x.isDirectory()&&x.name.startsWith('QD-KB-')).map(x=>path.join(root,x.name)).sort();
for (const dir of dirs) await importPackage(dir);
