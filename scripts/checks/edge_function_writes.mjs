// WHICH TABLES DOES EACH EDGE FUNCTION WRITE, AND WHERE IT CANNOT TELL, IT SAYS SO.
//
// The Phase C kernel-coverage gate needs a conjunction: a source reaches the kernel when it writes
// some table T, and T carries a trigger that calls a kernel door. The second half is measurable in
// pg_proc. This produces the first half.
//
// TWO EARLIER ATTEMPTS FAILED, BOTH SILENTLY, AND THAT IS THE DESIGN CONSTRAINT.
//
//   1. A regex for `.from('t')` with a 200-character lookahead for a write method. It missed
//      `inquiries` in customer_api, which plainly writes it — the chain spans more characters than
//      the window. It reported "no writes" where the truth was "I did not look far enough".
//   2. A substring test for the table name anywhere in the file. Sound for ACCUSING — a file that
//      never names a table certainly does not write it — and useless for CLEARING, because a file
//      that names it may only read it. It also matched two `//` comments in inquiry_intake.
//
// Both returned an empty answer where the honest answer was "I cannot tell". An extractor that
// cannot say "I don't know" will eventually clear a real kernel bypass, which is the one failure
// this whole exercise exists to prevent.
//
// SO: every `.from(...)` and every `.rpc(...)` call site is classified into exactly one of
//   RESOLVED     — the argument is a string literal and the chain reaches a write method
//   READ_ONLY    — string literal, no write method in the chain
//   UNRESOLVABLE — anything else: a variable, a template with a substitution, a helper parameter,
//                  a computed name, or an rpc whose target is not on the read-only allow-list
// UNRESOLVABLE is a hard failure. It is never folded into "writes nothing".
//
// The walk is a real TypeScript AST (typescript 5.5.4 via `deno eval`/npm), not a regex, so a call
// chain of any length and any formatting resolves the same way.
//
//   node scripts/checks/edge_function_writes.mjs            # print the map, exit 1 on unresolvable
//   node scripts/checks/edge_function_writes.mjs --write    # regenerate the committed CSV
//   node scripts/checks/edge_function_writes.mjs --json     # machine-readable
import { readdirSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { tmpdir, homedir } from 'node:os';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FN_DIR = join(REPO, 'supabase', 'functions');
const CSV = join(REPO, 'docs', 'phase-c', 'PHASE_C_EDGE_FUNCTION_WRITES.csv');
const WRITE = process.argv.includes('--write');
const JSON_OUT = process.argv.includes('--json');

// supabase-js terminal methods that mutate. `select` after them is a projection, not a read.
const WRITE_METHODS = new Set(['insert', 'update', 'upsert', 'delete']);

// An rpc() target is NOT opaque: pg_proc knows what every routine writes. Resolving it against the
// database is a measurement; an allow-list of names would be a guess. A routine that writes nothing
// contributes nothing; one that writes T means this edge function writes T transitively.
const PROD = 'htdblwldjkcgjvmqkbeh';
const LOCAL = join(homedir(), '.supabase', 'access-token');
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(LOCAL) ? readFileSync(LOCAL, 'utf8') : '')).trim();
const ROUTINE_WRITES_SQL = [
  "with body as (select p.proname,",
  "  regexp_replace(regexp_replace(p.prosrc,'/[*].*?[*]/',' ','g'),'--[^\\n]*',' ','g') src",
  "  from pg_proc p join pg_namespace n on n.oid=p.pronamespace",
  " where n.nspname='public' and p.prokind='f'),",
  "t as (select tablename from pg_tables where schemaname='public')",
  "select b.proname, string_agg(distinct t.tablename, ',' order by t.tablename) writes",
  "  from body b join t on b.src ~ ('(insert\\s+into|update|delete\\s+from)\\s+(public\\.)?'",
  "                                 || t.tablename || '\\M')",
  " group by b.proname",
].join('\n');

async function routineWrites() {
  if (!token) return null;
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: ROUTINE_WRITES_SQL }),
  });
  if (!r.ok) {
    console.error(`could not read routine write-sets from production (${r.status}).`);
    console.error('Refusing to treat every rpc() as writing nothing — that is the silent-clear failure.');
    process.exit(1);
  }
  const m = new Map();
  for (const row of await r.json()) {
    m.set(row.proname, String(row.writes || '').split(',').filter(Boolean));
  }
  return m;
}

/**
 * The AST walk runs under deno because `npm:typescript` resolves there without a package.json
 * dependency in this repository. It returns one record per call site.
 */
function parseWithDeno(files) {
  const script = `
import ts from 'npm:typescript@5.5.4';
const files = JSON.parse(Deno.readTextFileSync(Deno.args[0]));
const out = [];
for (const f of files) {
  const src = ts.createSourceFile(f, Deno.readTextFileSync(f), ts.ScriptTarget.ESNext, true);
  const line = (n) => src.getLineAndCharacterOfPosition(n.getStart(src)).line + 1;
  // Walk up a property-access chain from a .from()/.rpc() call to collect the methods applied to it.
  const chainMethods = (node) => {
    const names = [];
    let cur = node.parent;
    while (cur) {
      if (ts.isPropertyAccessExpression(cur) && cur.expression === node) {
        names.push(cur.name.text);
        node = cur.parent && ts.isCallExpression(cur.parent) && cur.parent.expression === cur ? cur.parent : cur;
        cur = node.parent;
        continue;
      }
      if (ts.isCallExpression(cur) && cur.expression === node) { node = cur; cur = node.parent; continue; }
      if (ts.isAwaitExpression(cur) || ts.isParenthesizedExpression(cur)) { node = cur; cur = node.parent; continue; }
      break;
    }
    return names;
  };
  const visit = (node) => {
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression)) {
      const fname = node.expression.name.text;
      // NOT every .from() is a table. Array.from(...) is a built-in, and supabase .storage.from(b)
      // names a storage bucket. Both appeared as UNRESOLVABLE on the first run; neither is a table.
      const recv = node.expression.expression;
      const recvTxt = recv ? recv.getText(src) : '';
      const isArrayFrom = ts.isIdentifier(recv) && /^(Array|Uint8Array|Uint16Array|Uint32Array|Int8Array|Int16Array|Int32Array|Float32Array|Float64Array|BigInt64Array|BigUint64Array|Object|Map|Set)$/.test(recv.text);
      const isStorage = /.storage$|^storage$/.test(recvTxt);
      if ((fname === 'from' && !isArrayFrom && !isStorage) || fname === 'rpc') {
        const a = node.arguments[0];
        const literal = a && (ts.isStringLiteral(a) || (ts.isNoSubstitutionTemplateLiteral && ts.isNoSubstitutionTemplateLiteral(a)))
          ? a.text : null;
        out.push({
          file: f, line: line(node), kind: fname,
          target: literal,
          raw: literal === null ? node.getText(src).slice(0, 90).replace(/\\s+/g, ' ') : null,
          methods: chainMethods(node),
        });
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(src);
}
console.log(JSON.stringify(out));
`;
  // WINDOWS 32k COMMAND LINE. 203 absolute paths as one argv entry is 'The command line is too long'
  // — the same limit that made deno test unrunnable locally, documented in run.mjs. The
  // list goes through a temp file instead.
  const listFile = join(tmpdir(), 'qd_edge_fn_list.json');
  const scriptFile = join(tmpdir(), 'qd_edge_fn_walk.ts');
  writeFileSync(listFile, JSON.stringify(files));
  writeFileSync(scriptFile, script);
  // , not : Deno 2's eval subcommand rejects permission flags.
  const r = spawnSync('deno', ['run', '--no-lock', '-A', scriptFile, listFile],
    { encoding: 'utf8', maxBuffer: 1 << 28, shell: process.platform === 'win32' });
  if (r.error && r.error.code === 'ENOENT') {
    console.error('deno is not on PATH, and this extractor needs a real TypeScript AST.');
    console.error('A regex fallback is NOT acceptable here: it is what produced two silent wrong answers.');
    process.exit(1);
  }
  if (r.status !== 0) {
    console.error('the AST walk failed; refusing to report a table map it could not build:');
    console.error((r.stderr || '').slice(0, 2000));
    process.exit(1);
  }
  return JSON.parse(r.stdout);
}

const slugs = readdirSync(FN_DIR).filter((d) => !d.startsWith('_') && existsSync(join(FN_DIR, d, 'index.ts')));
const files = slugs.map((d) => join(FN_DIR, d, 'index.ts'));
const sites = parseWithDeno(files);

const RPC_WRITES = await routineWrites();
const EXC = JSON.parse(readFileSync(join(REPO, 'scripts', 'checks', 'edge-function-writes-exceptions.json'), 'utf8'));
const EXC_BY_SITE = new Map((EXC.sites || []).map((e) => [e.site, e]));
const EXC_USED = new Set();
const writes = new Map();   // slug -> Map(table -> Set(kind))
const unbounded = new Map(); // slug -> reason
const unresolved = [];
const slugOf = (f) => f.split(/[\\/]/).slice(-2)[0];

for (const s of sites) {
  const slug = slugOf(s.file);
  const w = s.methods.filter((m) => WRITE_METHODS.has(m));

  // A hand resolution from edge-function-writes-exceptions.json, keyed by function:line. Applied
  // before anything is called unresolvable, and recorded as used so a stale entry is caught below.
  const exc = EXC_BY_SITE.get(slug + ':' + s.line);
  if (exc) {
    EXC_USED.add(slug + ':' + s.line);
    if (exc.unbounded) { unbounded.set(slug, exc.evidence); continue; }
    for (const tbl of (exc.tables || [])) {
      if (!writes.has(slug)) writes.set(slug, new Map());
      const mm = writes.get(slug);
      if (!mm.has(tbl)) mm.set(tbl, new Set());
      mm.get(tbl).add('hand-resolved');
    }
    continue;
  }
  if (s.kind === 'rpc') {
    if (s.target === null) { unresolved.push(`${slug}:${s.line} rpc(${s.raw}) — target not a literal`); continue; }
    if (!RPC_WRITES) { unresolved.push(`${slug}:${s.line} rpc('${s.target}') — no credential to resolve it`); continue; }
    // A routine absent from the map writes no table in public: pg_proc was read, and it said so.
    // That is a measurement, not an assumption, which is why an absent credential above is fatal.
    for (const tbl of (RPC_WRITES.get(s.target) || [])) {
      if (!writes.has(slug)) writes.set(slug, new Map());
      const mm = writes.get(slug);
      if (!mm.has(tbl)) mm.set(tbl, new Set());
      mm.get(tbl).add(`rpc:${s.target}`);
    }
    continue;
  }
  // A DYNAMIC TABLE NAME ON A READ IS NOT AN UNKNOWN. The first run flagged 18 sites, and reading
  // them showed almost all were `cnt(t)` helpers — `admin.from(t).select('id', {count:'exact',
  // head:true})`. A select writes nothing whichever table it names, so the unresolved name changes
  // no answer. Only a dynamic name on a chain that DOES write is genuinely unknown, because then
  // the question "which table did it write" has no answer and the honest reply is "I cannot tell".
  if (s.target === null) {
    if (w.length) {
      unresolved.push(`${slug}:${s.line} from(${s.raw}).${w.join('.')} — WRITES to a table this cannot name`);
    }
    continue;
  }
  if (!w.length) continue;                       // read-only use of a named table
  if (!writes.has(slug)) writes.set(slug, new Map());
  const m = writes.get(slug);
  if (!m.has(s.target)) m.set(s.target, new Set());
  for (const k of w) m.get(s.target).add(k);
}

const rows = [];
for (const slug of [...writes.keys()].sort()) {
  for (const [tbl, kinds] of [...writes.get(slug)].sort((a, b) => a[0].localeCompare(b[0]))) {
    rows.push({ edge_function: slug, table: tbl, write_kind: [...kinds].sort().join('+') });
  }
}

if (JSON_OUT) { console.log(JSON.stringify({ rows, unresolved }, null, 1)); process.exit(unresolved.length ? 1 : 0); }

console.log(`edge functions scanned      ${slugs.length}`);
console.log(`call sites parsed           ${sites.length}`);
console.log(`functions with table writes ${writes.size}`);
console.log(`write rows                  ${rows.length}`);
console.log(`functions that may write anything ${unbounded.size}`);
for (const [slug, why] of [...unbounded].sort()) console.log(`   ${slug} — ${String(why).slice(0, 110)}`);
console.log(`UNRESOLVABLE call sites     ${unresolved.length}`);

// A HAND RESOLUTION THAT NO LONGER MATCHES A SITE IS STALE, and a stale entry silently covers
// nothing while looking like diligence. Same discipline as the profile and ratchet guards.
const stale = (EXC.sites || []).map((e) => e.site).filter((k) => !EXC_USED.has(k));
if (stale.length) {
  console.log(`\nSTALE exception entries: ${stale.join(', ')}`);
  console.log('Each names a call site that no longer exists at that line. Re-resolve or delete it.');
  process.exit(1);
}
for (const u of unresolved.slice(0, 40)) console.log(`   ${u}`);
if (unresolved.length > 40) console.log(`   ... and ${unresolved.length - 40} more`);

if (WRITE) {
  const csv = ['edge_function,table,write_kind', ...rows.map((r) => `${r.edge_function},${r.table},${r.write_kind}`)].join('\n');
  writeFileSync(CSV, csv + '\n');
  console.log(`\nwrote ${CSV} (${rows.length} rows)`);
}

if (unresolved.length) {
  console.log(`\nREFUSING to publish a table map with ${unresolved.length} call site(s) it could not resolve.`);
  console.log('Each one is a place where a table name is computed, or an rpc could write anything.');
  console.log('Resolve them by hand — never by treating "cannot tell" as "writes nothing", which is');
  console.log('exactly how a real kernel bypass gets cleared.');
  process.exit(1);
}
console.log('\nOK — every call site resolved.');
