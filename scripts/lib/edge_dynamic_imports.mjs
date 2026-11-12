// EVERY LITERAL DYNAMIC IMPORT IN AN EDGE FUNCTION, AND WHETHER IT RESOLVES (it_engineer, 12 Nov 2026; final audit F3).
//
// `deno check` over every index.ts (the gate's deno-all step) type-checks a dynamic import whose target exists, but a
// literal `await import('./x.ts')` whose target is MISSING passes silently: Deno leaves a dynamic branch's resolution
// error to run time (measured 12 Nov 2026 with deno 2.9.4: a file importing './missing.ts' checks with exit 0).
// resilience_ping/ticks/customer_support.ts imported '../_shared/duty_voice.ts' (resolves to resilience_ping/_shared/,
// which does not exist) from the #1874 split on 10 Nov: "Module not found" 115 times, and the complaint and incident
// updates to people were never written. The gate now names each target as a root of the same deno check, where a
// missing one is an error, and reports the missing ones by file and line first.
import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join, resolve, dirname, relative } from 'node:path';

const LITERAL = /import\(\s*(['"])(\.{1,2}\/[^'"\n]+)\1\s*[,)]/g;

function* tsFiles(dir) {
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules' || name.startsWith('.')) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) yield* tsFiles(p);
    else if (/\.(ts|tsx|mts)$/.test(name)) yield p;
  }
}

/** { targets: repo-relative files that non-test sources import dynamically, missing: [{ file, line, spec }],
 *    roots: targets plus every missing one's resolved path, for deno check, which then fails on the missing ones }. */
export function edgeDynamicImports(repo) {
  const root = join(repo, 'supabase', 'functions');
  const targets = new Set(); const missing = [];
  for (const file of tsFiles(root)) {
    const lines = readFileSync(file, 'utf8').split('\n');
    lines.forEach((text, i) => {
      if (/^\s*(\/\/|\*|\/\*)/.test(text)) return;   // a specifier in a comment is prose, not an import
      for (const m of text.matchAll(LITERAL)) {
        const target = resolve(dirname(file), m[2]);
        const rel = relative(repo, file);
        if (!existsSync(target)) missing.push({ file: rel, line: i + 1, spec: m[2] });
        else if (!/\.test\.tsx?$|\.check\.ts$/.test(file)) targets.add(relative(repo, target));
      }
    });
  }
  const roots = [...targets, ...missing.map((m) => relative(repo, resolve(repo, dirname(m.file), m.spec)))];
  return { targets: [...targets].sort(), missing, roots: [...new Set(roots)].sort() };
}
