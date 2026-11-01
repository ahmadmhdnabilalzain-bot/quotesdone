// EVERY REPLAY OF A scripts/sql FILE GOES THROUGH scripts/lib/safe_replay.mjs (it_engineer, 30 Sep 2026).
//
// On 30 Sep 2026 a local run of every_model_class_is_on_the_founders_matrix.test.mjs applied a pending file to
// production: the check sent the file's text in a request meant to roll back, and the file's own COMMIT ran
// first. About forty checks built that request by hand. This fails any file under scripts/ that reads SQL text
// from scripts/sql and can send text to the database, unless every send in it either is a literal written in
// the file, is a read-only request, or goes through replaySql() - or the file is one of the appliers named
// below, whose job IS to commit.
//
// The static rule is FILE-level on purpose: it cannot follow a variable, so it asks for the shape a reader can
// verify at a glance. A send whose argument is an expression, in a file that reads scripts/sql, is a finding.
//
// Plus the live proof the brief asked for: a text wrapped in its own begin/commit that creates a zz_demo_
// routine is replayed through the helper against production, and the routine is absent afterwards.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));

// Files allowed to send around the helper, each read on 30 Sep 2026. The appliers exist to commit a file, with
// their own guards; the others name scripts/sql only in a message or a MANIFEST read, and send text written in
// the file itself. A new entry needs the same reading, and its reason here.
export const ALLOWED = new Map([
  ['scripts/apply_sql.mjs', 'the applier: dry run unless --apply, then reads every routine back'],
  ['scripts/qsql.mjs', 'the operator\'s runner for one file by hand; never called by a check'],
  ['scripts/lib/safe_replay.mjs', 'the door itself'],
  ['scripts/checks/canonical_routine_manifest.mjs', 'its q() sends catalogue reads written in the file'],
  ['scripts/checks/every_tick_step_is_scheduled.mjs', 'sends two selects written in the file'],
  ['scripts/checks/language_follows_registration.mjs', 'sends WALK, an aborted probe written in the file with no interpolation'],
  ['scripts/record_inbox_placement_verdict.mjs', 'the live path sends one generated call of a routine already applied (recordSql, no file text); its --dry-run replays the pending files through replaySql'],
  ['scripts/invitation_inbox_check.mjs', 'an operator tool that queues one seed invitation on purpose'],
  ['scripts/kb/purge_kb_bulk.mjs', 'the knowledge purge driver; commits batches by design, names scripts/sql only in messages'],
  ['scripts/staging/prove_quote_builder.mjs', 'sends reads written in the file; names scripts/sql only in a message'],
]);

const READS_SQL_FILES = /scripts\/sql\b|join\([^)]*['"]sql['"]|canonicalReplay\(/;
const READS = /\breadFileSync\(|\breadFile\(|\bread\(|\bR\(|\bsrc\(/;
const SENDS = /lib\/db\.mjs|database\/query|mgmtFixture|mgmtWrite/;
// A template's interpolation that can carry a file's text: a reader call, a name that says it is one, or any name
// bound (directly or through other names) to a reader's result - the template watcher's `${def}`, cut from a file.
const READER = /readFileSync\(|\bread\(|\bR\(|\bsrc\(/;
const CARRIES_NAME = /replay|pending|file|sql/i;
const esc = (t) => t.replace(/\$/g, '\\$');
function fileNames(code) {
  const binds = [...code.matchAll(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=([^;]*)/g)].map((m) => [m[1], m[2]]);
  // the seed: a reader whose path is a .sql file (literally, or through a name bound to one); data read from
  // other files (word lists, packs) is not a replay
  const paths = new Set(binds.filter(([, rhs]) => /scripts\/sql\b|\.sql\b|['"]sql['"]/.test(rhs)).map(([n]) => n));
  const readsSql = (rhs) => READER.test(rhs) && (/scripts\/sql\b|\.sql\b|['"]sql['"]/.test(rhs)
    || [...paths].some((p) => new RegExp(`(?<![\\w$.])${esc(p)}(?![\\w$])`).test(rhs)));
  const names = new Set();
  for (let grew = true; grew;) {
    grew = false;
    for (const [n, rhs] of binds) {
      // a function is not text, and a list or array made from the text is data, not a replay
      if (names.has(n) || /^\s*(\([^)]*\)|[\w$]+)\s*=>|^\s*(async\s+)?function\b/.test(rhs)
        || /\.(map|flatMap|matchAll|split|filter)\(|JSON\.parse|^\s*\[/.test(rhs)) continue;
      if (readsSql(rhs) || [...names].some((t) => new RegExp(`(?<![\\w$.])${esc(t)}(?![\\w$])`).test(rhs))) { names.add(n); grew = true; }
    }
  }
  return names;
}
function carriesFile(tpl, names) {
  for (const m of tpl.matchAll(/\$\{([^}]*)\}/g)) {
    if (READER.test(m[1]) || CARRIES_NAME.test(m[1])) return true;
    if ((m[1].match(/[A-Za-z_$][\w$]*/g) || []).some((id) => names.has(id))) return true;
  }
  return false;
}

// The text of the balanced (...) that opens at `open`, skipping strings and templates (with their ${}).
function argsAt(code, open) {
  let depth = 0; const stack = [];
  for (let i = open; i < code.length; i++) {
    const c = code[i];
    if (stack.length && stack[stack.length - 1] !== '{') {          // inside a quote
      const q = stack[stack.length - 1];
      if (c === '\\') { i++; continue; }
      if (q === '`' && c === '$' && code[i + 1] === '{') { stack.push('{'); i++; continue; }
      if (c === q) stack.pop();
      continue;
    }
    if (c === "'" || c === '"' || c === '`') { stack.push(c); continue; }
    if (stack.length && c === '}') { stack.pop(); continue; }
    if (stack.length && c === '{') { stack.push('{'); continue; }
    if (c === '(') depth++;
    else if (c === ')' && --depth === 0) return code.slice(open + 1, i);
  }
  return code.slice(open + 1);
}

/** The sends in one file's source that bypass the helper. Empty when the file is not a replayer. */
export function bypasses(src) {
  const code = src.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' ')).replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');
  if (!READS_SQL_FILES.test(code) || !READS.test(code) || !SENDS.test(code)) return [];
  const lineOf = (i) => code.slice(0, i).split('\n').length;
  const out = [];
  const names = fileNames(code);
  // A renamed import (`import { sql as q }`) is the same sender under another name.
  const aliases = [...code.matchAll(/\b(?:sql|mgmtFixture|mgmtWrite)\s+as\s+([A-Za-z_$][\w$]*)/g)].map((a) => a[1]);
  const senders = new RegExp(`(?<![\\w.$])(${['sql', 'mgmtFixture', 'mgmtWrite', ...aliases].join('|')})\\(`, 'g');
  for (const m of code.matchAll(senders)) {
    if (/(function\s+)$/.test(code.slice(Math.max(0, m.index - 20), m.index))) continue;   // its declaration
    const args = argsAt(code, m.index + m[0].length - 1);
    if (/readOnly\s*:\s*true/.test(args)) continue;                                         // cannot write
    const first = (m[1] === 'sql' ? args : args.replace(/^\s*[\w.]+\s*,/, '')).trimStart();
    if (/^['"]/.test(first)) continue;                                                      // a literal
    if (first.startsWith('`') && !carriesFile(first.slice(0, first.indexOf('`', 1) + 1 || undefined), names)) continue;
    out.push(`line ${lineOf(m.index)}: ${code.slice(m.index, m.index + 120).split('\n')[0].trim()}`);
  }
  for (const m of code.matchAll(/database\/query/g)) {
    if (!/read_only/.test(code.slice(m.index, m.index + 400))) out.push(`line ${lineOf(m.index)}: a direct POST to the management API`);
  }
  return out;
}

function* files(dir) {
  for (const n of readdirSync(dir)) {
    if (n === 'node_modules' || n === 'sql' || n.startsWith('.')) continue;
    const p = join(dir, n);
    if (statSync(p).isDirectory()) yield* files(p);
    else if (/\.(mjs|js|cjs|ts)$/.test(n) && !/RETIRED/.test(n)) yield p;
  }
}

test('no file under scripts/ sends scripts/sql text to the database except through safe_replay', () => {
  const found = [];
  for (const p of files(join(REPO, 'scripts'))) {
    const rel = relative(REPO, p).split('\\').join('/');
    if (ALLOWED.has(rel) || rel === 'scripts/checks/every_sql_replay_goes_through_safe_replay.test.mjs') continue;
    const b = bypasses(readFileSync(p, 'utf8'));
    if (b.length) found.push(`${rel}\n    ${b.join('\n    ')}`);
  }
  assert.deepEqual(found, [], `${found.length} file(s) read scripts/sql and send text around scripts/lib/safe_replay.mjs:\n  `
    + found.join('\n  ') + '\n  Send the replay with replaySql() from scripts/lib/safe_replay.mjs.');
});

test('the rule fails a deliberately bad replayer and passes the same file through the helper', () => {
  const bad = [
    "import { sql } from '../lib/db.mjs';",
    "const replay = readFileSync('scripts/sql/x.sql', 'utf8');",
    "try { await sql(replay + '\\n' + PROBE, { retry: false }); } catch (e) { msg = e.message; }",
  ].join('\n');
  assert.equal(bypasses(bad).length, 1);
  const good = bad.replace("import { sql } from '../lib/db.mjs';", "import { replaySql } from '../lib/safe_replay.mjs';")
    .replace('await sql(', 'await replaySql(');
  assert.deepEqual(bypasses(good), []);
  assert.deepEqual(bypasses(bad.replace('sql(replay', "sql(`select 1`, replay")), []);          // a literal
  assert.deepEqual(bypasses(bad.replace('{ retry: false }', '{ readOnly: true }')), []);        // cannot write
  assert.equal(bypasses(bad.replace('{ sql }', '{ sql as q }').replace('await sql(', 'await q(')).length, 1);   // renamed
  // a body cut from a file under a name that says nothing (the template watcher's `${def}`) is still caught
  const cut = "import { sql } from '../lib/db.mjs';\nconst def = readFileSync('scripts/sql/x.sql', 'utf8').match(/create[\\s\\S]*/)[0];\n"
    + 'await sql(`${def}\n  do $p$ begin raise exception \'CHK\'; end $p$;`);';
  assert.equal(bypasses(cut).length, 1, 'a ${def} send was not flagged');
  assert.deepEqual(bypasses(cut.replace('{ sql } from \'../lib/db.mjs\'', '{ replaySql } from \'../lib/safe_replay.mjs\'').replace('await sql(', 'await replaySql(')), []);
  assert.equal(bypasses("import x from '../lib/db.mjs'; read('scripts/sql/a.sql'); await fetch(`${u}/database/query`, {});").length, 1);
});

test('a begin; create function; commit; file replayed through the helper leaves production unchanged', async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const { replaySql, ROLLBACK_MARK } = await import('../lib/safe_replay.mjs');
  const name = `zz_demo_safe_replay_${process.pid}`;
  const exists = async () => (await sql(`select count(*)::int n from pg_proc where proname = '${name}'`, { readOnly: true }))[0].n;
  try { await exists(); } catch (e) { if (/No Supabase access token|SUPABASE_ACCESS_TOKEN is not set/.test(e.message)) return t.skip('no management token'); throw e; }
  assert.equal(await exists(), 0, 'the demo routine is already on production');
  const file = `BEGIN;\ncreate function public.${name}() returns int language sql as $f$ select 1 $f$;\nCOMMIT;\n`
    + `select public.${name}();\n`;
  let msg = '';
  try { await replaySql(file, { retry: false, label: 'the zz_demo replay' }); } catch (e) { msg = String(e.message); }
  assert.match(msg, new RegExp(ROLLBACK_MARK), `the replay did not end in the helper's rollback: ${msg.slice(0, 300)}`);
  assert.equal(await exists(), 0, `${name} is on production after a replay that must roll back`);
  // rows mode: the verdict query's rows come back, and the routine it called is still rolled back.
  const rows = await replaySql(file.replace(`select public.${name}();`, `select public.${name}() as v;`), { rows: true, retry: false });
  assert.deepEqual(rows, [{ v: 1 }]);
  assert.equal(await exists(), 0, `${name} is on production after a rows-mode replay`);
});
