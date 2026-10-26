// QuotesDone operational 86 mapping importer — starter
// Run locally/server-side; do not paste corpus contents into Claude context.
import { createClient } from "@supabase/supabase-js";
import { createReadStream } from "node:fs";
import { readFile, readdir } from "node:fs/promises";
import * as readline from "node:readline";
import * as path from "node:path";

const supabase = createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!);
const root = process.argv[2];
if (!root) throw new Error("Usage: tsx import_operational_86.ts <extracted-package-root>");

async function readJsonl(file:string){ const out:any[]=[]; const rl=readline.createInterface({input:createReadStream(file),crlfDelay:Infinity}); for await (const line of rl){ if(line.trim()) out.push(JSON.parse(line)); } return out; }
async function batchUpsert(table:string, rows:any[], onConflict:string, size=500){ for(let i=0;i<rows.length;i+=size){ const {error}=await supabase.from(table).upsert(rows.slice(i,i+size),{onConflict}); if(error) throw error; } }

async function main(){
 const live=(await supabase.from("catalog_supplier_categories").select("num,slug,name").order("num")).data ?? [];
 if(live.length!==86) throw new Error(`Expected 86 live catalogue rows, found ${live.length}`);
 const liveByNum=new Map(live.map((x:any)=>[x.num,x]));
 const dir=path.join(root,"01_ROUTE_MANIFESTS"); const files=(await readdir(dir)).filter(x=>x.endsWith(".json")).sort();
 const routes:any[]=[]; const maps:any[]=[];
 for(const fn of files){ const m=JSON.parse(await readFile(path.join(dir,fn),"utf8")); const l=liveByNum.get(m.catalog_num); if(!l) throw new Error(`Missing live category ${m.catalog_num}`); routes.push({catalog_num:m.catalog_num,route_key:m.route_key,expected_catalog_slug:m.expected_catalog_slug,catalog_name:l.name,route_type:m.route_type,coverage_status:m.coverage_status,version:m.version,manifest:m}); for(const p of m.knowledge_mappings) for(const s of p.subcategories) maps.push({catalog_num:m.catalog_num,package_slug:p.package_slug,subcategory_slug:s,priority:p.priority,package_zip:p.package_zip}); }
 await batchUpsert("kb_operational_route",routes,"catalog_num"); await batchUpsert("kb_operational_route_map",maps,"catalog_num,package_slug,subcategory_slug");
 const aliases=await readJsonl(path.join(root,"00_CONTROL","03_OPERATIONAL_ALIAS_LEXICON.jsonl")); await batchUpsert("kb_operational_alias",aliases,"catalog_num,language,alias");
 const tests=await readJsonl(path.join(root,"00_CONTROL","04_OPERATIONAL_ROUTE_TESTS.jsonl")); await batchUpsert("kb_operational_route_test",tests.map(t=>({test_id:t.test_id,catalog_num:t.expected_catalog_num,input:t.input,expected_action:t.expected_action,expected:t})),"test_id");
 console.log({routes:routes.length,mappings:maps.length,aliases:aliases.length,tests:tests.length});
}
main().catch(e=>{console.error(e);process.exit(1)});
