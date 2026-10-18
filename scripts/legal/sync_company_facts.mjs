// sync_company_facts.mjs — make every place say what src/content/company_facts.json says (founder rule C,
// 23 Sep 2026: "every change to company knowledge must reach EVERY place at once, with no mismatch anywhere").
//
//   node scripts/legal/sync_company_facts.mjs --write-repo       the website texts (legal.json, messages, function
//                                                                prompts) take the source's figures; the signed
//                                                                Supplier Agreement module is re-exported
//   node scripts/legal/sync_company_facts.mjs --probe            production, read only: every knowledge row, policy
//                                                                key and signed registry entry that disagrees; exit 1
//   node scripts/legal/sync_company_facts.mjs --emit-sql <file>  one transaction that brings production into line:
//                                                                the signed registry (pages bodies -> legal_documents
//                                                                -> app_secrets pins, versions and labels), each stale
//                                                                knowledge row (guarded by its md5, embedding cleared
//                                                                so kb_embed re-embeds it), and the policy keys
//
// How one change travels: edit company_facts.json -> --write-repo -> commit (the PR merge rebuilds the website on
// Vercel) -> --emit-sql -> `node scripts/apply_sql.mjs <file> --apply --ddl` -> deploy supplier_api (it carries the
// agreement text and hash). A new agreement version makes every supplier accept again on next sign-in: the portal
// compares leads.accepted_terms_version with app_secrets.terms_version (SupplierPortal needsReaccept), and Supplier
// Agreement clause 23 gives 30 days' notice of a material change. The check that fails when any of this is skipped
// is scripts/checks/company_facts_agree_everywhere.test.mjs (repository) and --probe (production).
import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { loadFacts, findings, wrongWordings, rewrite, fixWordings, currentDocs, signedBody } from './company_facts.mjs';

const ROOT = new URL('../../', import.meta.url);
const F = loadFacts();
const args = process.argv.slice(2);
const md5 = (s) => createHash('md5').update(s, 'utf8').digest('hex');
const sha = (s) => createHash('sha256').update(s, 'utf8').digest('hex');
const tag = (s) => { let t = 'qd'; while (s.includes(`$${t}$`)) t += 'x'; return `$${t}$`; };
const q = (s) => { const t = tag(s); return `${t}${s}${t}`; };
const legalPath = new URL('src/content/legal.json', ROOT);

if (args.includes('--write-repo')) {
  const legal = JSON.parse(readFileSync(legalPath, 'utf8'));
  let n = 0;
  for (const k of currentDocs(legal)) for (const g of ['en', 'ar']) { const r = rewrite(legal[k][g].html); legal[k][g].html = r.text; n += r.changed; }
  // legal.json is written without indentation (measured: JSON.stringify(v, null, 2) with leading spaces removed)
  writeFileSync(legalPath, JSON.stringify(legal, null, 2).replace(/^ +/gm, ''));
  for (const p of F.surfaces.repo.filter((x) => x !== 'src/content/legal.json')) {
    const u = new URL(p, ROOT); const r0 = rewrite(readFileSync(u, 'utf8')); const r1 = fixWordings(r0.text); const r = { text: r1.text, changed: r0.changed + r1.changed };
    if (r.changed) { writeFileSync(u, r.text); n += r.changed; console.log(`${p}: ${r.changed}`); }
  }
  const e = spawnSync(process.execPath, [new URL('export_supplier_agreement.mjs', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'), F.documents['supplier-agreement'].version], { encoding: 'utf8' });
  console.log(e.stdout.trim() || e.stderr.trim());
  console.log(`${n} statement(s) rewritten. Wordings the source rules out are reported, not rewritten:`);
  for (const k of currentDocs(legal)) for (const g of ['en', 'ar']) for (const w of wrongWordings(legal[k][g].html)) console.log(`  legal.json ${k}/${g}: "${w.text}"`);
  process.exit(0);
}

const { sql } = await import('../lib/db.mjs');

// Rows are pre-filtered in SQL by the words every fact's statements share, so a 2.6-million-row kb_chunks is not
// read whole; the exact reading is the same findings() the repository check uses.
const PREFILTER = `(AED ?[0-9]|درهم|[0-9]%|per annum|سنويًا|times the fee|أضعاف|reveal fee|رسوم الكشف|first [0-9,]+|revit|rvt|ifc|dgn|microstation|ريفيت|مايكروستيشن)`; // 28 Sep 2026: + the drawing formats (drawing_upload_formats)
async function staleRows() {
  const out = [];
  for (const s of F.surfaces.db) {
    const where = [`${s.col} ~* '${PREFILTER}'`, s.where].filter(Boolean).join(' and ');
    let rows;
    try { rows = await sql(`select ${s.key}::text k, ${s.col} v from public.${s.table} where ${where}`); }
    catch (e) { out.push({ surface: s, error: String(e.message).slice(0, 200) }); continue; }
    for (const r of rows) {
      const f = findings(r.v || ''), w = wrongWordings(r.v || '');
      if (f.length || w.length) out.push({ surface: s, key: r.k, old: r.v, findings: f, wordings: w });
    }
  }
  return out;
}
async function policyDrift() {
  const bad = [];
  for (const [k, f] of Object.entries(F.facts)) for (const d of f.db || []) {
    if (d.table !== 'decision_policy') continue;
    const r = await sql(`select value #>> '{}' v from public.decision_policy where key = '${d.key}'`);
    const got = r[0] ? Number(r[0].v) : null, want = f.value * (d.scale || 1);
    if (got !== want) bad.push({ fact: k, key: d.key, got, want });
  }
  return bad;
}
async function registryDrift() {
  const bad = [];
  for (const [k, d] of Object.entries(F.documents)) if (d.registry_slug) {
    const r = await sql(`select version, effective_date::text d from public.legal_documents where slug = '${d.registry_slug}'`);
    if (!r[0] || r[0].version !== d.version) bad.push({ doc: k, registry: r[0]?.version, source: d.version });
  }
  return bad;
}

if (args.includes('--probe')) {
  const rows = await staleRows(), pol = await policyDrift(), reg = await registryDrift();
  for (const r of rows) {
    if (r.error) { console.log(`ERROR ${r.surface.table}: ${r.error}`); continue; }
    for (const f of r.findings) console.log(`${r.surface.table}#${r.key}: ${f.fact} says ${f.got}, source ${f.want}: "${f.text}"`);
    for (const w of r.wordings) console.log(`${r.surface.table}#${r.key}: ${w.rule} worded "${w.text}"`);
  }
  for (const p of pol) console.log(`decision_policy.${p.key}: ${p.got}, source ${p.want} (${p.fact})`);
  for (const g of reg) console.log(`legal_documents.${g.doc}: registry ${g.registry}, source ${g.source}`);
  const n = rows.filter((r) => !r.error).length + pol.length + reg.length;
  console.log(n ? `DRIFT: ${n} place(s) disagree with company_facts.json ${F.version}` : `production agrees with company_facts.json ${F.version}`);
  process.exit(n || rows.some((r) => r.error) ? 1 : 0);
}

const at = args.indexOf('--emit-sql');
if (at >= 0) {
  const file = args[at + 1];
  if (!file || !file.endsWith('.sql')) { console.error('usage: --emit-sql scripts/sql/<name>.sql'); process.exit(1); }
  const legal = JSON.parse(readFileSync(legalPath, 'utf8'));
  const L = [];
  L.push(`-- GENERATED by scripts/legal/sync_company_facts.mjs --emit-sql from src/content/company_facts.json ${F.version}`);
  L.push(`-- and src/content/legal.json. Do not edit by hand: change the source and generate again.`);
  L.push(`--`);
  L.push(`-- WHAT THIS CHANGES`);
  L.push(`--   1. The signed registry: pages.legal_terms_body and pages.legal_supplier_body become the bodies derived from`);
  L.push(`--      legal.json (company_facts.mjs signedBody, proved byte-equal to production's v12 body on 23 Sep 2026);`);
  L.push(`--      trg_pages_legal_sync carries them to legal_documents and app_secrets.supplier_terms_html; the versions,`);
  L.push(`--      dates, SHA-256 pins and labels follow. Every supplier and customer accepts the new version on next sign-in.`);
  L.push(`--   2. Every knowledge row --probe found stating a figure the source does not (guarded by the md5 of the row as`);
  L.push(`--      read, so a row edited since is left alone and reported by the next --probe), embedding cleared.`);
  L.push(`--   3. The decision_policy keys the seats and routines read for each figure.`);
  L.push(`-- WHAT THIS DOES NOT CHANGE: how a charge is computed (see the file for the version-aware administrative fee).`);
  L.push(`-- It ends with a verdict row; apply_sql.mjs exits 3 on PROBE FAILED.`);
  L.push('', '-- no begin/commit: the applier runs the file as one transaction, and a replaying check must never commit it', '');
  const docs = [];
  for (const [k, d] of Object.entries(F.documents)) if (d.page_slug) {
    const n = d.version.replace(/^v/, '');
    const body = signedBody(legal[k], k === 'supplier-agreement' ? n : null);
    docs.push({ k, d, n, sha: sha(body) });
    L.push(`-- ${k} ${d.version}`);
    L.push(`update public.pages set html = ${q(body)}, updated_at = now() where slug = '${d.page_slug}';`);
    L.push(`update public.legal_documents set version = '${d.version}', effective_date = date '${d.date}', content_sha256 = encode(sha256(convert_to(body_html, 'UTF8')), 'hex'), updated_at = now() where slug = '${d.registry_slug}';`);
    L.push(`update public.app_secrets set value = (select encode(sha256(convert_to(html, 'UTF8')), 'hex') from public.pages where slug = '${d.page_slug}'), updated_at = now() where key = '${d.secrets.sha}';`);
    L.push(`update public.app_secrets set value = '${d.version}', updated_at = now() where key in (${d.secrets.version.map((x) => `'${x}'`).join(', ')});`);
    L.push(`update public.app_secrets set value = '${d.secrets.label[1]}${n}', updated_at = now() where key = '${d.secrets.label[0]}';`, '');
  }
  const rows = (await staleRows()).filter((r) => !r.error);
  L.push(`-- knowledge rows (${rows.length})`);
  for (const r of rows) {
    const s = r.surface; const fixed = fixWordings(rewrite(r.old).text).text;
    const note = r.wordings.length ? ` -- ALSO worded against canonical_statements: ${r.wordings.map((w) => w.text).join(' | ').replace(/\n/g, ' ')}` : '';
    if (fixed === r.old) { L.push(`-- ${s.table}#${r.key}: only a wording finding, rewrite by hand${note}`); continue; }
    // The key is compared UNCAST: the untyped literal takes the column's type, so the primary key's index is used.
    // With ${s.key}::text each kb_chunks row was found by a full scan of an 8 GB table and the apply outran the
    // statement timeout (24 Sep 2026, measured: DataFileRead for 5 minutes on the first attempt).
    L.push(`update public.${s.table} set ${s.col} = ${q(fixed)}${s.embed ? `, ${s.embed} = null` : ''} where ${s.key} = '${r.key.replace(/'/g, "''")}' and md5(${s.col}) = '${md5(r.old)}';${note}`);
  }
  L.push('', '-- policy keys');
  for (const f of Object.values(F.facts)) for (const d of f.db || []) if (d.table === 'decision_policy') {
    L.push(`insert into public.decision_policy (key, value, description) values ('${d.key}', to_jsonb(${f.value * (d.scale || 1)}::numeric), ${q(`${d.note || f.unit}. Source: src/content/company_facts.json ${F.version}.`)})`);
    L.push(`  on conflict (key) do update set value = excluded.value, updated_at = now();`);
  }
  // the seats' rendered company knowledge (ops_knowledge qd-company:*) is built from company_faq and decision_policy
  // by these two routines; re-render so the rows above and the keys reach it in the same transaction
  L.push('', '-- re-render the company knowledge the seats read', `do $s$ begin perform public.fn_company_org_directory_sync(); perform public.fn_company_self_knowledge_sync(); end $s$;`);
  L.push('', '-- verdict');
  const checks = docs.map(({ d, sha: h }) => `(select count(*) = 1 from public.legal_documents where slug = '${d.registry_slug}' and version = '${d.version}' and content_sha256 = '${h}')`);
  checks.push(...docs.map(({ d }) => `(select value from public.app_secrets where key = '${d.secrets.version[0]}') = '${d.version}'`));
  L.push(`select case when ${checks.join('\n   and ')}\n  then 'PROBE OK' else 'PROBE FAILED: the registry does not carry the generated bodies and versions' end as verdict;`);
  L.push('');
  writeFileSync(new URL(file, ROOT), L.join('\n'));
  console.log(`wrote ${file}: ${docs.length} signed document(s), ${rows.length} knowledge row(s)`);
  process.exit(0);
}
console.error('usage: --write-repo | --probe | --emit-sql <file>');
process.exit(1);
