// Inventory of every object the recovered P2-C1 migrations create or alter.
// Used to build an exact teardown set for the replay verification, instead of
// guessing at name patterns.
//
//   node scripts/inventory_recovered.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const MIG = join(process.cwd(), 'supabase', 'migrations');
const files = readdirSync(MIG)
  .filter(f => /^2026080222\d{2}_.*\.sql$/.test(f) || /^2026080223\d{2}_.*\.sql$/.test(f))
  .sort();

const out = {
  files: files.length,
  createTable: new Set(), createView: new Set(), createMatView: new Set(),
  createType: new Set(), createFunction: new Set(), createTrigger: new Set(),
  createIndex: new Set(), createPolicy: new Set(),
  alterTable: new Set(), alterType: new Set(), dropInMigration: [],
  insertInto: new Set(),
};

const rx = [
  [/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?("?[a-zA-Z0-9_]+"?)/gi, 'createTable'],
  [/create\s+(?:or\s+replace\s+)?view\s+(?:if\s+not\s+exists\s+)?(?:public\.)?("?[a-zA-Z0-9_]+"?)/gi, 'createView'],
  [/create\s+materialized\s+view\s+(?:if\s+not\s+exists\s+)?(?:public\.)?("?[a-zA-Z0-9_]+"?)/gi, 'createMatView'],
  [/create\s+type\s+(?:public\.)?("?[a-zA-Z0-9_]+"?)/gi, 'createType'],
  [/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?("?[a-zA-Z0-9_]+"?)/gi, 'createFunction'],
  [/create\s+(?:or\s+replace\s+)?trigger\s+("?[a-zA-Z0-9_]+"?)/gi, 'createTrigger'],
  [/create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?("?[a-zA-Z0-9_]+"?)/gi, 'createIndex'],
  [/create\s+policy\s+("[^"]+"|[a-zA-Z0-9_]+)/gi, 'createPolicy'],
  [/alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?("?[a-zA-Z0-9_]+"?)/gi, 'alterTable'],
  [/alter\s+type\s+(?:public\.)?("?[a-zA-Z0-9_]+"?)/gi, 'alterType'],
  [/insert\s+into\s+(?:public\.)?("?[a-zA-Z0-9_]+"?)/gi, 'insertInto'],
];

for (const f of files) {
  const sql = readFileSync(join(MIG, f), 'utf8');
  for (const [re, key] of rx) {
    for (const m of sql.matchAll(re)) out[key].add(m[1].replace(/"/g, ''));
  }
  for (const m of sql.matchAll(/^\s*drop\s+(table|view|type|function|trigger|index|policy)\s+[^\n;]{0,120}/gim)) {
    out.dropInMigration.push(`${f}: ${m[0].trim()}`);
  }
}

const S = s => [...s].sort();
console.log(JSON.stringify({
  files: out.files,
  createTable: S(out.createTable),
  createView: S(out.createView),
  createMatView: S(out.createMatView),
  createType: S(out.createType),
  createFunction: S(out.createFunction),
  createTrigger: S(out.createTrigger),
  createPolicy: S(out.createPolicy).length,
  createIndex: S(out.createIndex).length,
  alterTable: S(out.alterTable),
  alterType: S(out.alterType),
  insertInto: S(out.insertInto),
  dropInMigration: out.dropInMigration,
}, null, 1));
