// The Dropbox tree repair of 7 Oct 2026 (it_engineer + sales_engineer; founder gate ledger 1162).
// The plan and its rules: dropbox_tree_repair_plan.ts. Nothing is ever deleted.
//
//   deno run -A scripts/it/dropbox_tree_repair.ts                        DRY RUN (default): reads only, writes the plan
//   deno run -A scripts/it/dropbox_tree_repair.ts --apply                writes the doc_backups RECORDS of the
//                                                                        unrecorded real files (metadata only)
//   deno run -A scripts/it/dropbox_tree_repair.ts --apply --moves --founder-ok=<ledger id>
//                                                                        also MOVES (merge, ownerless, demo): HELD until
//                                                                        the founder's explicit OK; refused unless that
//                                                                        founder_instruction row approves the Dropbox moves
//   --max=<n>   records written in one run (default 50)
// Run by the release operator after merge. The plan, the before/after counts and every operation's result
// are written to --out (default: the Desktop sandbox-evidence folder). No token or secret is printed.
import { DropboxClient, memoryStore, refreshAccessToken, TokenCache } from '../../supabase/functions/dropbox_backup/dropbox.ts';
import { capRecords, counts, founderApprovesMoves, plan, recordOutcome, recordStatement, ROOT, type Listed, type Row, type Ruling } from './dropbox_tree_repair_plan.ts';

const REF = 'htdblwldjkcgjvmqkbeh';
const args = new Set(Deno.args);
const opt = (k: string) => Deno.args.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3);
const APPLY = args.has('--apply'), MOVES = args.has('--moves'), FOUNDER_OK = opt('founder-ok');
const DATE = opt('date') ?? new Date().toISOString().slice(0, 10);
const home = Deno.env.get('USERPROFILE') ?? Deno.env.get('HOME') ?? '';
const OUT = opt('out') ?? home + '/Desktop/QuotesDone Sandbox Test 2026-10/backups/';
const MAX = opt('max') !== undefined ? Number(opt('max')) : undefined;

const mgmt = (Deno.env.get('SUPABASE_ACCESS_TOKEN') ?? await Deno.readTextFile(home + '/.supabase/access-token')).trim();
async function sql<T = Record<string, unknown>>(query: string): Promise<T[]> {
  for (let i = 0; ; i++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { method: 'POST',
      headers: { Authorization: 'Bearer ' + mgmt, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }) });
    if ((r.status === 429 || r.status >= 500) && i < 6) { await r.body?.cancel(); await new Promise((x) => setTimeout(x, 2000 * 2 ** i)); continue; }
    if (!r.ok) throw new Error('sql ' + r.status + ' ' + (await r.text()).slice(0, 200));
    return await r.json();
  }
}
const lit = (s: unknown) => s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
// The moves touch real files: the founder's own ruling must exist AND approve them (review of #1284).
if (MOVES) {
  const id = /^\d+$/.test(FOUNDER_OK ?? '') ? Number(FOUNDER_OK) : null;
  const r = id === null ? [] : await sql<Ruling>(`select id, instruction, subject, status from public.founder_instruction where id = ${id}`);
  const v = APPLY ? founderApprovesMoves(r[0]) : { ok: false, why: '--moves needs --apply' };
  if (!v.ok) { console.log(JSON.stringify({ ok: false, refused: 'moves touch real files: ' + v.why })); Deno.exit(2); }
}
const sec = Object.fromEntries((await sql<{ key: string; value: string }>("select key, value from public.app_secrets where key in ('dropbox_refresh_token', 'dropbox_app_key', 'dropbox_app_secret')")).map((r) => [r.key, r.value]));
const dbx = new DropboxClient(new TokenCache(memoryStore(), () => refreshAccessToken(sec.dropbox_refresh_token, sec.dropbox_app_key, sec.dropbox_app_secret)));

async function list(root: string): Promise<Listed[]> {
  const out: Listed[] = [];
  let r = await dbx.call('api', 'files/list_folder', { path: root, recursive: true, limit: 2000 });
  for (;;) {
    if (!r.ok) throw new Error('list_folder ' + root + ' ' + r.status);
    const j = await r.json();
    for (const e of j.entries) if (e['.tag'] === 'file') out.push({ p: e.path_display, h: e.content_hash, s: e.size, m: e.server_modified });
    if (!j.has_more) return out;
    r = await dbx.call('api', 'files/list_folder/continue', { cursor: j.cursor });
  }
}
async function meta(path: string): Promise<{ hash: string; size: number } | null> {
  const r = await dbx.call('api', 'files/get_metadata', { path }); const t = await r.text();
  if (r.status === 409 && t.includes('not_found')) return null;
  if (!r.ok) throw new Error('get_metadata ' + r.status);
  const j = JSON.parse(t); return { hash: j.content_hash, size: j.size };
}

const readRows = () => sql<Row>(`
  select d.id, d.entity, d.entity_id, d.dropbox_path, d.dropbox_content_hash, d.dedupe_key, d.status,
         case d.entity
           when 'supplier' then exists (select 1 from public.leads l where l.id::text = d.entity_id)
           when 'customer' then exists (select 1 from public.customers c where c.id::text = d.entity_id)
           when 'inquiry'  then exists (select 1 from public.inquiries i where i.id::text = d.entity_id)
           when 'quote'    then exists (select 1 from public.quotes q where q.id::text = d.entity_id) end as owner_exists
    from public.doc_backups d where d.dropbox_path is not null`);
const measure = async () => {
  const rows = await readRows();
  const listed = [...await list(ROOT + '/Suppliers'), ...await list(ROOT + '/Customers')];
  return { rows, listed, plan: plan(rows, listed, DATE) };
};

const before = await measure();
const report: Record<string, unknown> = { mode: !APPLY ? 'dry-run' : MOVES ? 'apply records + moves' : 'apply records', date: DATE,
  before: counts(before.plan) };
if (before.plan.collisions.length) report.refused = 'two operations would land on one path';
Deno.mkdirSync(OUT, { recursive: true });
Deno.writeTextFileSync(OUT + `dropbox_tree_repair_plan_${DATE}.json`, JSON.stringify(before.plan, null, 1));

if (APPLY && !report.refused) {
  // D: records only. The customer of a "(id8)" folder is resolved to its full id when it still exists.
  const done: unknown[] = [];
  const cap = capRecords(before.plan.records, MAX);
  report.records_held_by_cap = cap.held;
  for (const rec of cap.take) {
    const ent = rec.entity === 'customer'
      ? (await sql<{ id: string }>(`select id::text id from public.customers where left(id::text, 8) = ${lit(rec.entity_ref)} limit 2`))
      : [];
    const entityId = rec.entity === 'customer' ? (ent.length === 1 ? ent[0].id : 'dropbox:' + rec.entity_ref) : rec.entity_ref;
    let err: string | null = null;
    try { await sql(recordStatement(rec, entityId, lit)); } catch (e) { err = String((e as Error).message); }
    done.push({ path: rec.path, ...recordOutcome(err) });
  }
  report.records = done;
  report.records_failed = done.filter((d) => !(d as { recorded: boolean }).recorded).length;

  if (MOVES) {
    const moved: unknown[] = [];
    for (const m of before.plan.moves) {
      const pre = await meta(m.from);
      if (!pre) { moved.push({ ...m, result: 'source not found, skipped' }); continue; }
      if (m.hash && pre.hash !== m.hash) { moved.push({ ...m, result: 'stopped: Dropbox content differs from the record' }); break; }
      const r = await dbx.call('api', 'files/move_v2', { from_path: m.from, to_path: m.to, autorename: false, allow_ownership_transfer: false });
      if (!r.ok) { moved.push({ ...m, result: 'stopped: move_v2 ' + r.status }); await r.body?.cancel(); break; }
      await r.body?.cancel();
      const post = await meta(m.to);
      const ok = !!post && post.hash === pre.hash && post.size === pre.size && !(await meta(m.from));
      if (ok && m.id !== null) await sql(`update public.doc_backups set dropbox_path = ${lit(m.to)}, verified_at = now() where id = ${m.id}`);
      moved.push({ ...m, result: ok ? 'moved, hash verified' : 'stopped: hash or size differs after the move' });
      if (!ok) break;
    }
    report.moves = moved;
    report.founder_ok = FOUNDER_OK;
  }
  report.after = counts((await measure()).plan);
}
Deno.writeTextFileSync(OUT + `dropbox_tree_repair_${report.mode === 'dry-run' ? 'dry_run' : 'apply'}_${DATE}.json`, JSON.stringify(report, null, 1));
console.log(JSON.stringify({ mode: report.mode, before: report.before, after: report.after ?? null, refused: report.refused ?? null }));
