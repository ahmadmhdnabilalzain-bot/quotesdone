// function_sources.mjs — the whole runtime source of one edge function, for checks that read it as TEXT.
//
// Until 9 Nov 2026 the large edge functions were single files (customer_api/index.ts 2,516 lines,
// supplier_api 2,116, resilience_ping 2,034), and about 110 checks read `<fn>/index.ts` and asserted
// a property of its text. When a function is split into modules inside its own folder, a check that
// kept reading index.ts alone would read a short router and pass or fail on nothing. Checks read the
// function through here instead.
//
// A deployed function IS its folder: `supabase functions deploy <fn>` bundles index.ts and whatever it
// imports. So the source is every runtime .ts file in supabase/functions/<fn>/ (recursively), with
// index.ts first and the rest in path order, joined by a newline. Tests (*.test.ts), offline checks
// (*.check.ts), fixtures/ and test_*/ helpers are not runtime and are left out. Code the function
// imports from _shared/ is NOT included: a check about shared code reads that module by name.
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';

export const REPO = join(import.meta.dirname, '..', '..');
const FUNCTIONS = join(REPO, 'supabase', 'functions');

const NOT_RUNTIME = (name) => /\.(test|check)\.ts$/.test(name) || name === 'fixtures' || name.startsWith('test_') || name.startsWith('_test');

/** Repo-relative paths of a function's runtime files: index.ts first, then path order. */
export function functionFiles(fn) {
  const root = join(FUNCTIONS, fn);
  if (!existsSync(join(root, 'index.ts'))) throw new Error(`function_sources: supabase/functions/${fn}/index.ts does not exist`);
  const out = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir).sort()) {
      if (NOT_RUNTIME(name)) continue;
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (name.endsWith('.ts') || name.endsWith('.tsx')) out.push(relative(REPO, p).split('\\').join('/'));
    }
  };
  walk(root);
  const index = `supabase/functions/${fn}/index.ts`;
  return [index, ...out.filter((f) => f !== index)];
}

/** The function's runtime source as one string (index.ts first). */
export function functionSource(fn) {
  return functionFiles(fn).map((f) => readFileSync(join(REPO, f), 'utf8')).join('\n');
}

/**
 * Repo-relative paths of a SHARED module that was split into a barrel and a folder (supabase/functions/_shared/<name>.ts and
 * _shared/<name>/**.ts): the barrel first, then the runtime files of the folder in path order. Tests, offline checks and
 * fixtures are left out, exactly as in functionFiles. A shared module that is one file is that one file.
 */
export function sharedModuleFiles(name) {
  const shared = join(FUNCTIONS, '_shared');
  const barrel = `supabase/functions/_shared/${name}.ts`;
  if (!existsSync(join(REPO, barrel))) throw new Error(`function_sources: ${barrel} does not exist`);
  const out = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir).sort()) {
      if (NOT_RUNTIME(entry)) continue;
      const p = join(dir, entry);
      if (statSync(p).isDirectory()) walk(p);
      else if (entry.endsWith('.ts') || entry.endsWith('.tsx')) out.push(relative(REPO, p).split('\\').join('/'));
    }
  };
  if (existsSync(join(shared, name))) walk(join(shared, name));
  return [barrel, ...out];
}

/** A shared module's runtime source as one string (the barrel first, then its folder). */
export function sharedModuleSource(name) {
  return sharedModuleFiles(name).map((f) => readFileSync(join(REPO, f), 'utf8')).join('\n');
}
