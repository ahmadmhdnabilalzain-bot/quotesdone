// THE CANONICAL FILE OF EVERY ROUTINE, AS THE REPOSITORY DECIDES IT (it_engineer, 10 Nov 2026).
//
// This is the repository half of scripts/checks/canonical_routine_manifest.mjs, moved here verbatim so that the
// rule has ONE owner. Until today it lived inside the check, and anything else that needed "which file is real for
// fn_x" had to re-derive it: scripts/lib/canonical_body.mjs and scripts/lib/canonical_sql.mjs are two such
// re-derivations, each a slightly different rule (they read MANIFEST order and ignore tiers 1-3 and SUPERSEDED.txt).
// The database map (scripts/architecture/database_map.mjs -> docs/architecture/database/) needs the exact rule the
// gate enforces, so it imports this instead of becoming a fourth copy. The two older helpers are left alone:
// they serve replays with pending files included, which is a different question, and merging them is not a pure move.
//
// THE RULE, in one line: the HIGHEST explicit sequence that defines a routine is canonical (tier 1
// migrations_history < tier 2 migrations < tier 3 ai-organization/db-functions < tier 4 scripts/sql in MANIFEST
// order); two files at one key is a CONFLICT, never a tie broken by a heuristic. The full reasoning, and the
// production half (drift, uncommitted DDL), stay in the check.
//
// Proved a pure move on 10 Nov 2026: the check's --all --emit output and its CSV were byte-identical before and
// after the extraction, on this repository and on the forced-conflict fixture of canonical_routines.test.mjs.
//
//   const r = canonicalRoutines()          // root = process.cwd(), exactly as the check always used
//   r.canonical.get('fn_x').file           // the canonical file
//   r.byRoutine / r.CONFLICTING / r.AMBIGUOUS / r.manifestPos / r.PENDING / r.FILES / r.definitionsIn(file)
import { readdirSync, readFileSync } from 'node:fs';
import { pendingNotes } from './pending_sql.mjs';
import { SCHEMA_MIRROR, readSchemaMirror } from './schema_mirror.mjs';

export const MANIFEST = 'scripts/sql/MANIFEST.txt';
export const SUPERSEDED = 'scripts/sql/SUPERSEDED.txt';

// Compare on TOKENS: indentation is not a finding, a changed identifier or literal is.
export const tokens = s => (String(s).match(/[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|'(?:[^']|'')*'|[^\sA-Za-z0-9_$]/g) || [])
  .join(' ').toLowerCase();

/** The repository-side canonical selection, read from the tree at `root`. */
export function canonicalRoutines(root = process.cwd().replace(/\\/g, '/')) {
  const ROOT = root;
  // The schema mirror is a directory of parts read as one (scripts/lib/schema_mirror.mjs); a missing part THROWS
  // there rather than reading as null, so the mirror can never silently look empty to this check.
  const read = p => { if (p === SCHEMA_MIRROR) return readSchemaMirror(); try { return readFileSync(`${ROOT}/${p}`, 'utf8'); } catch { return null; } };
  const lsSql = d => { try { return readdirSync(`${ROOT}/${d}`).filter(f => f.endsWith('.sql')).map(f => `${d}/${f}`); } catch { return []; } };

  // ---------------------------------------------------------------- the sequence
  // A MANIFEST line is a PATH, and a path that arrived quoted, BOM-prefixed or tab-padded is the same
  // path. Both prefix tests below used to run on a merely-trimmed line, so a quoted entry would have
  // been SKIPPED — not reported, skipped, which is the failure mode that matters: a file listed but
  // invisible to the order check reads exactly like a file that was never listed at all.
  // `grep -c '^"' scripts/sql/MANIFEST.txt` returns 0 over all 1,524 lines today, so the blind spot
  // has never been hit. It is closed here in mechanism rather than left closed in fact.
  const manifestPath = (l) => l.replace(/^﻿/, '').trim().replace(/^["']+|["']+$/g, '').trim();
  const manifestLines = (read(MANIFEST) || '').split(/\r?\n/);
  const manifestPos = new Map();
  manifestLines.forEach((l, i) => {
    const p = manifestPath(l);
    if (p.startsWith('scripts/sql/') && p.endsWith('.sql') && !manifestPos.has(p)) manifestPos.set(p, i + 1);
  });

  const NON_CANONICAL = [
    [/^scripts\/sql\/rollback\//, 'ROLLBACK'],
    [/^supabase\/rollback\//, 'ROLLBACK'],
    [/^supabase\/migrations-superseded-consolidated\//, 'SUPERSEDED_CONSOLIDATED'],
    [/^supabase\/seeds\//, 'SEED'],
    [/^holdout_v2_eval\//, 'EVAL_FIXTURE'],
    [/^vendor\//, 'THIRD_PARTY'],
  ];

  /** The explicit sequence key for a file, or null when the file may never be canonical. */
  function sequenceOf(file) {
    for (const [re, why] of NON_CANONICAL) if (re.test(file)) return { key: null, why };
    let m = file.match(/^supabase\/migrations_history\/(\d+)_/);
    if (m) return { key: `1|${m[1].padStart(20, '0')}`, version: m[1], tier: 1 };
    m = file.match(/^supabase\/migrations\/(\d+)_/);
    if (m) return { key: `2|${m[1].padStart(20, '0')}`, version: m[1], tier: 2 };
    if (/^ai-organization\/db-functions\//.test(file)) {
      return { key: `3|${file.split('/').pop()}`, version: file.split('/').pop(), tier: 3 };
    }
    if (/^scripts\/sql\/[^/]+\.sql$/.test(file)) {
      const pos = manifestPos.get(file);
      if (!pos) return { key: null, why: 'NOT_IN_MANIFEST' };
      return { key: `4|${String(pos).padStart(6, '0')}`, version: `MANIFEST:${pos}`, tier: 4 };
    }
    return { key: null, why: 'UNCLASSIFIED_LOCATION' };
  }

  // ---------------------------------------------------------------- explicit supersession
  const superseded = new Set();   // `${file}::${routine}`
  const supersededBy = new Map();
  for (const line of (read(SUPERSEDED) || '').split(/\r?\n/)) {
    const l = line.trim();
    if (!l || l.startsWith('#')) continue;
    const [file, routine, by, ...rest] = l.split('::').map(s => s.trim());
    if (!file || !routine) continue;
    superseded.add(`${file}::${routine.toLowerCase()}`);
    supersededBy.set(`${file}::${routine.toLowerCase()}`, { by, reason: rest.join('::') });
  }

  // ---------------------------------------------------------------- every definition in the repo
  /** Every CREATE FUNCTION in a file: name, declared arg text, dollar-quoted body. */
  function definitionsIn(file) {
    const t = read(file);
    if (t === null) return [];
    const out = [];
    const re = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi;
    let m;
    while ((m = re.exec(t))) {
      const from = m.index;
      const rest = t.slice(from);
      // declared arguments: from the opening paren to its match, shallow but sufficient to record
      const open = rest.indexOf('(');
      let depth = 0, close = -1;
      for (let i = open; i < rest.length && i < open + 4000; i++) {
        if (rest[i] === '(') depth++;
        else if (rest[i] === ')') { depth--; if (depth === 0) { close = i; break; } }
      }
      const args = close > open ? rest.slice(open + 1, close).replace(/\s+/g, ' ').trim() : '';
      // The body opener is the dollar quote that follows `as`. Anchoring on `as` keeps a positional
      // parameter like $1 in a default out of it, and the tag may carry digits — $k34$, $w14$ — which
      // an [A-Za-z_] class silently skipped, losing every kernel routine from the manifest.
      const dq = rest.match(/\bas\s*(\$[A-Za-z0-9_]*\$)/i);
      let body = null;
      if (dq) {
        const tag = dq[1];
        const s = rest.indexOf(tag, dq.index) + tag.length;
        const e = rest.indexOf(tag, s);
        if (e > s) body = rest.slice(s, e);
      }
      out.push({ name: m[1].toLowerCase(), args, body });
    }
    // Within ONE file the later statement wins deterministically, so a redefinition is not a conflict.
    // Distinct argument lists are overloads and both survive. Key on (name, normalised args).
    const last = new Map();
    for (const d of out) last.set(`${d.name}(${tokens(d.args)})`, d);
    return [...last.values()];
  }

  // FILES COMMITTED AND DELIBERATELY NOT APPLIED have one note each, scripts/sql/pending/<name>.txt
  // (scripts/lib/pending_sql.mjs), and are excluded from the canonical scan below. A file that has not
  // run is not the canonical definition of anything — including it would report repository -> production
  // drift for a change nobody has made yet, which is exactly what a pending founder decision looks like
  // from here. An empty note excludes nothing; it is reported below.
  const NOTES = pendingNotes();
  const PENDING = new Map([...NOTES].filter(([, why]) => why));

  const FILES = [
    ...lsSql('supabase/migrations_history'),
    ...lsSql('supabase/migrations'),
    ...lsSql('ai-organization/db-functions'),
    ...lsSql('scripts/sql'),
    ...lsSql('scripts/sql/rollback'),
    ...lsSql('supabase/migrations-superseded-consolidated'),
    ...lsSql('supabase/rollback'),
  ].filter((f) => !PENDING.has(f));

  // name -> [{file, seqKey, tier, version, args, body, canonicalEligible, whyNot}]
  const byRoutine = new Map();
  for (const file of FILES) {
    const seq = sequenceOf(file);
    for (const d of definitionsIn(file)) {
      if (!byRoutine.has(d.name)) byRoutine.set(d.name, []);
      const explicitlySuperseded = superseded.has(`${file}::${d.name}`);
      byRoutine.get(d.name).push({
        file, ...d,
        seqKey: seq.key, tier: seq.tier ?? null, version: seq.version ?? '',
        eligible: Boolean(seq.key) && !explicitlySuperseded && d.body !== null,
        whyNot: !seq.key ? (seq.why || 'NO_SEQUENCE') : explicitlySuperseded ? 'EXPLICITLY_SUPERSEDED'
          : d.body === null ? 'NO_PARSEABLE_BODY' : '',
      });
    }
  }

  // ---------------------------------------------------------------- pick the canonical file
  const CONFLICTING = [], AMBIGUOUS = [];
  const canonical = new Map();     // name -> chosen entry
  for (const [name, defs] of byRoutine) {
    const eligible = defs.filter(d => d.eligible);
    if (!eligible.length) continue;
    const top = eligible.reduce((a, b) => (b.seqKey > a.seqKey ? b : a));
    const tied = eligible.filter(d => d.seqKey === top.seqKey);
    const tiedFiles = [...new Set(tied.map(d => d.file))];
    if (tiedFiles.length > 1) {
      // TWO FILES at ONE sequence key. The order cannot decide, so nothing may.
      const bodies = new Set(tied.map(d => tokens(d.body)));
      CONFLICTING.push({ name, seqKey: top.seqKey, files: tiedFiles, distinctBodies: bodies.size });
      AMBIGUOUS.push({ name, files: tiedFiles });
      continue;
    }
    // One file, possibly carrying several overloads of this name. All of them are canonical.
    canonical.set(name, {
      ...top,
      bodies: tied.map(d => ({ args: d.args, body: d.body })),
      superseded: [...new Set(defs.filter(d => d.file !== top.file).map(d => d.file))],
    });
  }

  return { read, lsSql, manifestPath, manifestLines, manifestPos, sequenceOf, superseded, supersededBy, definitionsIn,
    NOTES, PENDING, FILES, byRoutine, canonical, CONFLICTING, AMBIGUOUS };
}
