// EVERY CUSTOMER-REACHABLE READER CARRIES THE AUDIENCE RULES (customer_support, 27 Oct 2026).
// Founder rulings 1338 (27 Oct 2026, "Withhold from customers.") and 7 Oct 2026: internal facts, unverified facts and
// knowledge the AI wrote itself (kb_chunks source_kind 'generated' or 'memory') are never told to a customer or a supplier.
//
// MEASURED 27 Oct 2026 (probe, live routines): fn_reason_retrieve_library and fn_reason_retrieve_ml_library took no
// audience at all, and gave a customer, supplier, visitor, blank, unknown or NULL caller every class of row the legacy
// readers withhold: generated, memory and blank kb_chunks rows, another seat's agent notes, unvalidated agent notes,
// support rows tagged audience:internal or cited internal:memory/, unverified support rows and pending research. Nothing
// called them that day, because the one-line dispatch from fn_reason_retrieve(_ml) had been removed; the library's own
// file says the seats are handed to them once it is reconciled. fn_knowledge_library_source_sql marked every kb_chunks
// row verified, generated and memory included.
//
// WHAT FAILS (static, over the NEWEST definer of each routine: MANIFEST order, then pending files in name order, the
// order the release operator appends them; scripts/lib/pending_sql.mjs):
//   * a surviving overload of any fn_reason_retrieve* routine (CREATE minus DROP, in file order) that has no
//     p_audience text DEFAULT NULL - an unguarded overload beside a guarded one is what #1567 removed on 19 Oct;
//   * a reader whose v_internal is anything but the fail-closed form (only 'internal' or 'founder' are inside);
//   * a reader that gives unapproved research outside, or reserves its own rows for an outside caller;
//   * a DISPATCH: a reader that calls another fn_reason_retrieve* routine without passing p_audience => p_audience
//     (a literal audience, or none, both fail);
//   * a library reader branch that reads public.knowledge_library without the one customer predicate (FAST_PATH below),
//     or a helper fn_knowledge_library_customer_facing that loses one of its rules;
//   * a legacy reader branch that reads a seat store without #1567's internal rule, or agent_knowledge without the
//     '_global'-only rule; and (once #1640's file is on disk) kb_chunks without the generated/memory rule;
//   * fn_knowledge_library_source_sql marking a kb_chunks row verified without reading its source_kind.
// KNOWN-BAD CONTROLS run first, every time: the phase-1 library readers, a dispatch without an audience, a dispatch with
// a literal 'internal', a branch with its predicate removed, an old overload left undropped, the old source mapping.
// Each must fail the audit, or this check is reporting on nothing.
//
//   node --test scripts/checks/every_customer_reachable_reader_carries_the_audience_rules.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from '../lib/pending_sql.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const stripComments = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

const READER = /^fn_reason_retrieve\w*$/;
const PHASE1 = 'scripts/sql/one_knowledge_library_is_built_beside_the_nine_stores_and_read_behind_a_flag.sql';
const PR1640 = 'scripts/sql/knowledge_the_ai_wrote_itself_is_withheld_from_customers.sql';

// The one customer predicate on a knowledge_library row (l): the seat-store fast path from columns, else the helper.
export const FAST_PATH = "(v_internal or (l.verified and l.origin_store not in ('kb_chunks', 'ops_knowledge', 'agent_knowledge') "
  + "and not (l.tags && array['audience:internal', 'kind:company']) and not exists (select 1 from unnest(l.source_ids) x "
  + "where x like 'internal:%')) or public.fn_knowledge_library_customer_facing(l.id))";
const V_INTERNAL = /v_internal constant boolean := lower\(btrim\(coalesce\(p_audience, ''\)\)\) in \('internal', 'founder'\);/;
const SEAT_RULE = "(v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x "
  + "where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))";
const AGENT_RULE = "(a.agent_key = '_global' or (v_internal and a.agent_key = p_seat))";
const KB_RULE = "coalesce(c.source_kind not in ('generated', 'memory'), false)";
const RESEARCH_RULE = /r\.status <> 'rejected'(?! and \(v_internal or r\.status = 'approved'\))/;
const squash = (s) => s.replace(/\s+/g, ' ');

// ---- parsing ------------------------------------------------------------------------------------------------------
function matchParen(s, open) {               // index of the ')' closing the '(' at `open`
  let d = 0;
  for (let i = open; i < s.length; i++) {
    if (s[i] === '(') d++;
    else if (s[i] === ')' && --d === 0) return i;
  }
  return -1;
}
function splitTop(s) {                       // split on commas outside parentheses
  const out = []; let d = 0, cur = '';
  for (const ch of s) {
    if (ch === '(') d++;
    if (ch === ')') d--;
    if (ch === ',' && d === 0) { out.push(cur); cur = ''; } else cur += ch;
  }
  if (cur.trim()) out.push(cur);
  return out.map((x) => x.trim());
}
// A signature ignores type modifiers (vector(384) is vector) and spells aliases one way, as pg_proc does.
const ALIAS = { int: 'integer', int4: 'integer', int8: 'bigint', bool: 'boolean', varchar: 'character varying' };
const normType = (t) => { const x = t.trim().toLowerCase().replace(/\(\s*\d+(\s*,\s*\d+)?\s*\)/g, '').replace(/\s+/g, ' '); return ALIAS[x] ?? x; };
const paramType = (p) => normType(p.replace(/\s+(default\b|=).*$/is, '').trim().split(/\s+/).slice(1).join(' '));
const normTypes = (list) => splitTop(list).map(normType).join(',');

// Every CREATE / DROP of a function named by `want` in one file's text, in order.
export function routineEvents(text, file, want = READER) {
  const code = stripComments(text);
  const out = [];
  const re = /\b(create\s+(?:or\s+replace\s+)?function|drop\s+function\s+(?:if\s+exists\s+)?)\s*public\.(\w+)\s*\(/gi;
  let m;
  while ((m = re.exec(code))) {
    const name = m[2];
    if (!want.test(name)) continue;
    const open = re.lastIndex - 1;
    const close = matchParen(code, open);
    const args = code.slice(open + 1, close);
    if (/^drop/i.test(m[1])) { out.push({ kind: 'drop', name, key: `${name}(${normTypes(args)})`, file }); continue; }
    const params = splitTop(args);
    const key = `${name}(${params.map(paramType).join(',')})`;
    const as = /\bas\s+(\$\w*\$)/i.exec(code.slice(close));
    const tag = as[1];
    const bStart = close + as.index + as[0].length;
    const body = code.slice(bStart, code.indexOf(tag, bStart));
    out.push({ kind: 'create', name, key, params: args, body, file, at: m.index });
    re.lastIndex = bStart + body.length;
  }
  return out;
}

// The overloads that survive the whole ordered file list, each with its newest body.
export function survivors(files, want = READER) {
  const live = new Map();
  for (const { file, text } of files) {
    for (const e of routineEvents(text, file, want)) {
      if (e.kind === 'drop') live.delete(e.key); else live.set(e.key, e);
    }
  }
  return live;
}

// Split a body into union branches and CTE bodies, so a predicate is asked of the branch that reads the table.
const segments = (body) => body.split(/\bunion\b(?:\s+all)?|\)\s*,\s*\w+\s+as\s+(?:materialized\s+)?\(/i);

// ---- the audit ----------------------------------------------------------------------------------------------------
// opts.require1640: also hold a legacy reader's kb_chunks branch to founder ruling 1338.
export function auditReader(e, opts = {}) {
  const f = [];
  const where = `${e.name} (${e.file})`;
  const b = e.body;
  if (!/\bp_audience\s+text\s+default\s+null\b/i.test(e.params)) f.push(`${where}: no p_audience text DEFAULT NULL`);
  if (!V_INTERNAL.test(b)) f.push(`${where}: v_internal is not the fail-closed form`);
  if (RESEARCH_RULE.test(b)) f.push(`${where}: unapproved research reaches an outside caller`);
  // the own-row reservation is internal only
  const own = /\bown\s+integer\s*:=([^;]*);/i.exec(b);
  if (own && !(/\belse 0 end\b/.test(own[1]) && /v_internal|in \('internal', 'founder'\)/.test(own[1]))) f.push(`${where}: own rows are reserved for an outside caller`);
  if (/h\.mine/.test(b) && /reserved/.test(b) && !/when v_internal and h\.mine/.test(b) && !own) f.push(`${where}: own rows are reserved for an outside caller`);
  // a dispatch to another reader passes the caller's audience, unchanged
  const call = /\bfn_reason_retrieve\w*\s*\(/gi;
  let c;
  while ((c = call.exec(b))) {
    const open = call.lastIndex - 1;
    const args = splitTop(b.slice(open + 1, matchParen(b, open)));
    if (!args.some((a) => /^p_audience\s*=>\s*p_audience$/i.test(a) || /^p_audience$/i.test(a))) {
      f.push(`${where}: dispatches to ${c[0].replace(/\s*\($/, '')} without p_audience => p_audience`);
    }
  }
  const segs = segments(b);
  if (/public\.knowledge_library l\b/.test(b)) {
    // LIBRARY READER: every branch reading a library row carries the one predicate
    const elig = /\belig as (?:materialized )?\(([\s\S]*?)\)\s*,\s*cand as \(/i.exec(b);
    const eligOk = !!elig && squash(elig[1]).includes(FAST_PATH);
    segs.forEach((s, i) => {
      if (!/public\.knowledge_library l\b/.test(s)) return;
      if (squash(s).includes(FAST_PATH)) return;
      // the one exemption: a branch whose only library read is re-joining rows of elig by id, when elig carries it
      if (eligOk && s.match(/public\.knowledge_library l\b/g).length === 1
          && squash(s).includes('from elig e join public.knowledge_library l on l.id = e.id')) return;
      f.push(`${where}: branch ${i} reads knowledge_library without the customer predicate`);
    });
  } else {
    // LEGACY READER
    segs.forEach((s, i) => {
      if (/\bfrom scored\b|\bscored sc\b|\bhits h2?\b/.test(s)) return;   // re-reads rows the candidates already filtered
      if (/public\.(sales|accountant|it_engineer|marketing|ceo|support)_knowledge s\b/.test(s) && /\bwhere\b/.test(s) && !squash(s).includes(SEAT_RULE)) {
        f.push(`${where}: branch ${i} reads a seat store without the internal rule`);
      }
      if (/public\.agent_knowledge a\b/.test(s) && /\bwhere\b/.test(s) && !squash(s).includes(AGENT_RULE)) {
        f.push(`${where}: branch ${i} reads agent_knowledge without the '_global'-only rule`);
      }
    });
    if (opts.require1640 && /public\.kb_chunks c\b/.test(b)) {
      segs.forEach((s, i) => {
        // the branch that hands out a kb_chunks row's TEXT (a candidate branch returning only ids ranks, it tells nothing)
        if (/public\.kb_chunks c\b/.test(s) && /\bc\.content\b/.test(s) && !squash(s).includes(KB_RULE)) {
          f.push(`${where}: branch ${i} gives kb_chunks generated/memory rows outside (ruling 1338)`);
        }
      });
    }
  }
  return f;
}

export function auditHelper(e) {
  if (!e) return ['fn_knowledge_library_customer_facing is not defined'];
  const b = squash(e.body), f = [];
  for (const [rule, text] of [
    ['verified', 'select l.verified'],
    ['ruling 1338', "coalesce(nullif(btrim(c.source_kind), '') not in ('generated', 'memory'), false)"],
    ['internal tags', "not (l.tags && array['audience:internal', 'kind:company'])"],
    ['internal citations', "x like 'internal:founder_instruction/%' or x like 'internal:memory/%'"],
    ['agent notes', "x.agent_key = '_global'"],
    ['ops department rows', 'x.dept_key is null'],
    ['fails closed', 'from public.knowledge_library l where l.id = p_library_id), false)'],
  ]) if (!b.includes(text)) f.push(`fn_knowledge_library_customer_facing (${e.file}): lost the ${rule} rule`);
  return f;
}

export function auditSourceSql(e) {
  if (!e) return ['fn_knowledge_library_source_sql is not defined'];
  const kb = e.body.slice(e.body.indexOf("when 'kb_chunks' then"), e.body.indexOf("when 'ops_knowledge' then"));
  const f = [];
  if (/''\{\}''::text\[\],\s*true,\s*true,\s*c\.embedding_gte/.test(kb)) f.push(`fn_knowledge_library_source_sql (${e.file}): every kb_chunks row is verified`);
  if (!squash(kb).includes("coalesce(nullif(btrim(c.source_kind), '''') not in (''generated'', ''memory''), false), true, c.embedding_gte")) {
    f.push(`fn_knowledge_library_source_sql (${e.file}): kb_chunks verified does not read source_kind`);
  }
  return f;
}

function auditTree(files, opts) {
  const live = survivors(files);
  const f = [];
  const names = new Set([...live.values()].map((e) => e.name));
  for (const n of ['fn_reason_retrieve', 'fn_reason_retrieve_ml', 'fn_reason_retrieve_library', 'fn_reason_retrieve_ml_library']) {
    if (!names.has(n)) f.push(`${n}: no surviving definition`);
  }
  for (const e of live.values()) f.push(...auditReader(e, opts));
  const helper = [...survivors(files, /^fn_knowledge_library_customer_facing$/).values()].pop();
  f.push(...auditHelper(helper));
  f.push(...auditSourceSql([...survivors(files, /^fn_knowledge_library_source_sql$/).values()].pop()));
  return { live, findings: f };
}

const ORDERED = manifestWithPending(REPO).filter((p) => existsSync(join(REPO, p))).map((file) => ({ file, text: read(file) }));
const HAS_1640 = existsSync(join(REPO, PR1640));

// ---- known-bad controls -------------------------------------------------------------------------------------------
test('KNOWN-BAD: the phase-1 library readers (no audience) fail the audit', () => {
  const old = routineEvents(read(PHASE1), PHASE1).filter((e) => e.kind === 'create');
  assert.equal(old.length, 2, 'the phase-1 file no longer defines the two readers');
  for (const e of old) {
    const f = auditReader(e);
    assert.ok(f.some((x) => /no p_audience/.test(x)), `${e.name}: missing audience not caught`);
    assert.ok(f.some((x) => /without the customer predicate/.test(x)), `${e.name}: unfiltered branch not caught`);
    assert.ok(f.some((x) => /unapproved research/.test(x)), `${e.name}: pending research not caught`);
  }
});

test('KNOWN-BAD: a dispatch without the audience, or with a literal one, fails; passing it through does not', () => {
  const e = survivors(ORDERED).get('fn_reason_retrieve(text,vector,integer,text,text,text,text)');
  assert.ok(e, 'fn_reason_retrieve 7-argument overload not found');
  const inject = (call) => ({ ...e, body: e.body.replace(/\bbegin\b/i, `begin\n  if public.fn_knowledge_library_read() = 'library' then return ${call}; end if;`) });
  const bad = auditReader(inject('public.fn_reason_retrieve_library(p_seat, p_embedding, p_k, p_trade, p_kind, p_area)'));
  assert.ok(bad.some((x) => /dispatches to fn_reason_retrieve_library without p_audience/.test(x)), 'dispatch without audience not caught');
  const literal = auditReader(inject("public.fn_reason_retrieve_library(p_seat => p_seat, p_embedding => p_embedding, p_audience => 'internal')"));
  assert.ok(literal.some((x) => /dispatches to/.test(x)), 'dispatch with a literal audience not caught');
  const good = auditReader(inject('public.fn_reason_retrieve_library(p_seat => p_seat, p_embedding => p_embedding, p_k => p_k, p_trade => p_trade, p_kind => p_kind, p_area => p_area, p_audience => p_audience)'));
  assert.ok(!good.some((x) => /dispatches to/.test(x)), 'a dispatch passing the audience through was refused');
});

test('KNOWN-BAD: a library branch with its predicate removed, and an outside own-row reservation, fail', () => {
  const live = survivors(ORDERED);
  const gte = [...live.values()].find((e) => e.name === 'fn_reason_retrieve_library');
  const ml = [...live.values()].find((e) => e.name === 'fn_reason_retrieve_ml_library');
  assert.ok(gte && ml);
  const once = (b) => { const i = b.indexOf(FAST_PATH); return b.slice(0, i) + 'true' + b.slice(i + FAST_PATH.length); };
  assert.ok(auditReader({ ...gte, body: once(squash(gte.body)) }).some((x) => /without the customer predicate/.test(x)), 'gte: removed predicate not caught');
  const mlBody = squash(ml.body);
  const lastAt = mlBody.lastIndexOf(FAST_PATH);   // the lib_hits line every library row passes through
  const mlNoChoke = mlBody.slice(0, lastAt) + 'true' + mlBody.slice(lastAt + FAST_PATH.length);
  assert.ok(auditReader({ ...ml, body: mlNoChoke }).some((x) => /without the customer predicate/.test(x)), 'ml: removed lib_hits predicate not caught');
  const openOwn = mlBody.replace(/own integer := [^;]*;/, 'own integer := greatest(0, least(coalesce(p_own, 3), 2 * k));');
  assert.ok(auditReader({ ...ml, body: openOwn }).some((x) => /own rows are reserved/.test(x)), 'ml: outside own-row reservation not caught');
});

test('KNOWN-BAD: an old overload left undropped survives and fails; the old source mapping fails', () => {
  const resurrect = { file: 'resurrected.sql', text: read(PHASE1).replace(/DROP FUNCTION IF EXISTS public\.fn_reason_retrieve[^;]*;/g, '') };
  const files = [...ORDERED, resurrect];
  const { findings } = auditTree(files, { require1640: false });
  assert.ok(findings.some((x) => /resurrected\.sql\).*no p_audience/.test(x)), 'a resurrected audience-less overload was not caught');
  const oldSrc = [...survivors([{ file: PHASE1, text: read(PHASE1) }], /^fn_knowledge_library_source_sql$/).values()].pop();
  assert.ok(auditSourceSql(oldSrc).some((x) => /every kb_chunks row is verified/.test(x)), 'the verified=true mapping was not caught');
});

test('KNOWN-BAD: a legacy reader body from before ruling 1338 fails the kb_chunks rule', () => {
  const pre = routineEvents(read('scripts/sql/a_trade_question_reads_its_own_trade_pack.sql'), 'a_trade_question_reads_its_own_trade_pack.sql')
    .filter((e) => e.kind === 'create');
  assert.equal(pre.length, 2);
  for (const e of pre) assert.ok(auditReader(e, { require1640: true }).some((x) => /ruling 1338/.test(x)), `${e.name}: kb_chunks served outside not caught`);
});

// ---- the tree -----------------------------------------------------------------------------------------------------
test('every surviving customer-reachable reader carries the audience rules, and the library marks AI-written rows unverified', () => {
  const { live, findings } = auditTree(ORDERED, { require1640: HAS_1640 });
  assert.deepEqual(findings, [], findings.join('\n'));
  // the four readers survive exactly once each: one overload per name
  const names = [...live.values()].map((e) => e.name).sort();
  assert.deepEqual(names, ['fn_reason_retrieve', 'fn_reason_retrieve_library', 'fn_reason_retrieve_ml', 'fn_reason_retrieve_ml_library']);
});

// #1640 (knowledge_the_ai_wrote_itself_is_withheld_from_customers.sql) owns the legacy readers' kb_chunks rule and has
// its own check. Until its file is on disk here this one does not ask it of them; from the moment it is, it always does.
test("legacy readers' kb_chunks branch withholds generated and memory rows outside (ruling 1338)", { skip: HAS_1640 ? false : `waits for ${PR1640} (#1640) to reach this tree` }, () => {
  const { findings } = auditTree(ORDERED, { require1640: true });
  assert.deepEqual(findings.filter((x) => /ruling 1338/.test(x)), []);
});
