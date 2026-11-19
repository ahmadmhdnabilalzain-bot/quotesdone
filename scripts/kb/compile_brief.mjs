#!/usr/bin/env node
// Compiles knowledge/brief/*.md into the byte-stable blocks the customer-facing agents get as cached system
// blocks (founder rulings 1195, 1196, 1198, 12 Oct 2026: agents answer by reasoning from knowledge GIVEN in
// context, never searched at answer time; the knowledge is authored by Claude on the subscription).
// Until 3 Nov 2026 everything was one always-included block; it had grown to ~140k Sonnet tokens a reply, so it
// is now a core plus one trade pack chosen by code (see THE CORE AND THE TRADE PACKS below).
//
//   node scripts/kb/compile_brief.mjs           # write supabase/functions/_shared/brief.generated.ts
//   node scripts/kb/compile_brief.mjs --check   # exit 1 if the generated file is stale (CI)
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { isOwnEntry } from './verified_packs.mjs';
export { isOwnEntry };
import { join } from 'node:path';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const DIR = join(ROOT, 'knowledge/brief');
const OUT = join(ROOT, 'supabase/functions/_shared/brief.generated.ts');

// THE CORE AND THE TRADE PACKS (it_engineer, 3 Nov 2026). Measured on production (ai_cost_log, 30 Oct-3 Nov): every chat
// reply carried the WHOLE compiled brief, 333,392 characters of 32 files: wa_inbound 1,450 Sonnet calls averaged 144,310
// prompt tokens (min 139,874), the portal 146,796, inquiry_intake 143,668, supplier_api 142,157, reasoned_delivery 145,279.
// About 63% of it was the per-trade conversation playbooks, regulation digests and materials digests, of which a reply
// about one job needs one trade's. The founder asked whether that much for every reply is normal; it is not. Now:
//   BRIEF_TEXT     the CORE every reply carries, first and byte-identical (the gateway's sys_shared, cached 1 h):
//                  company.md, conversation_style.md, uae_contract_practice.md without its per-trade-group table, and
//                  gulf_arabic_guide.md.
//   BRIEF_SUPPLIER supplier_howto.md, carried only when the reader is a supplier.
//   a TRADE PACK   chosen by CODE from the trade the conversation names (company_brief.ts packOf): the family playbook's
//                  general rules, that trade's playbook section, the family's materials digest, the regulation digest
//                  whose scope names the trade, and the family's row of the contract-practice table.
// Nothing is dropped: every line of every source file is in the core, the supplier part or a pack, and
// scripts/checks/every_brief_line_reaches_a_reply.test.mjs fails if one is not.
export const CORE_FILES = ['company.md', 'conversation_style.md', 'uae_contract_practice.md', 'gulf_arabic_guide.md'];
const NORMS = '## Typical norms per trade group';

/** A token estimate calibrated on Sonnet 5.5 (3 Nov 2026): the whole old prompt of the cheapest wa_inbound call,
 *  358,603 Latin and 3,194 Arabic characters, was 139,874 prompt tokens: 2.6 and 2.0 give 139,521. 2.55 and 1.9 give
 *  142,228, about 2% high, on purpose.
 *  The same formula is company_brief.ts approxTokens; brief_budget.test.ts proves the two agree. */
export const approxTokens = (t) => { const ar = (String(t).match(/[\u0600-\u06FF]/g) || []).length; return Math.ceil((String(t).length - ar) / 2.55 + ar / 1.9); };

const md = (rel) => readFileSync(join(DIR, rel), 'utf8').replace(/\r\n/g, '\n').trim();
const block = (name, body) => `<<<FILE knowledge/brief/${name}>>>\n${body.trim()}\n<<<END>>>`;
/** A markdown file cut at its level-2 headings: the text before the first, then each section with its heading. */
export function sections(text) {
  const out = { preamble: '', list: [] };
  for (const piece of text.split(/^(?=## )/m)) (piece.startsWith('## ') ? out.list.push(piece.trim()) : (out.preamble = piece.trim()));
  return out;
}
/** The category codes a digest's Scope line names: its `backticked` codes, or else its comma list. */
export function scopeCodes(text) {
  const line = text.split('\n').slice(0, 8).find((l) => /^\W*Scope\b/.test(l)) ?? '';
  const after = line.slice(line.indexOf(':') + 1).replace(/\*/g, '');
  const ticked = [...after.matchAll(/`([a-z]+(?:-[a-z]+)*)`/g)].map((m) => m[1]);
  return ticked.length ? ticked : after.split(',').map((s) => s.trim().replace(/\.$/, '')).filter((s) => /^[a-z]+(?:-[a-z]+)*$/.test(s));
}

export function compileBrief() {
  const list = (d) => readdirSync(join(DIR, d)).filter((f) => f.endsWith('.md')).sort();
  const regs = list('uae_regulations'), convo = list('conversation'), mats = list('uae_materials_brands');
  const contract = md('uae_contract_practice.md');
  const cs = sections(contract);
  const normsSec = cs.list.find((s) => s.startsWith(NORMS));
  if (!normsSec) throw new Error('uae_contract_practice.md has no "' + NORMS + '" section');
  const coreText = CORE_FILES.map((f) => block(f, f === 'uae_contract_practice.md' ? contract.replace(normsSec, '').replace(/\n{3,}/g, '\n\n') : md(f))).join('\n\n');
  const supplier = block('supplier_howto.md', md('supplier_howto.md'));
  // the norms section: its prose head (everything before the table) and one row per trade group
  const normsLines = normsSec.split('\n');
  const normsHead = normsLines.filter((l) => !l.startsWith('|')).join('\n').trim();
  const tableHead = normsLines.filter((l) => l.startsWith('|')).slice(0, 2).join('\n');
  const partIds = [], partText = [];
  const part = (id, body) => { if (!partIds.includes(id)) { partIds.push(id); partText.push(block(id, body)); } return id; };
  const regScope = regs.map((f) => ({ f, codes: scopeCodes(md('uae_regulations/' + f)) }));
  const packs = [];
  for (const f of convo) {
    const fam = f.replace(/\.md$/, '');
    const s = sections(md('conversation/' + f));
    const cats = (s.preamble.match(/\*\*Categories:\*\*\s*([^\n]+)/)?.[1] ?? '').split(',').map((c) => c.trim()).filter(Boolean);
    const row = normsLines.filter((l) => l.startsWith(`| **${fam}** |`));
    if (row.length !== 1) throw new Error(`uae_contract_practice.md: ${row.length} norms rows for ${fam}`);
    for (const c of cats) {
      const sec = s.list.find((x) => new RegExp(`^## .*\\((?:[^)]*,\\s*)?${c}(?:\\s*,[^)]*)?\\)\\s*$`, 'm').test(x.split('\n')[0]));
      if (!sec) throw new Error(`conversation/${f} has no section for ${c}`);
      const key = sec.split('\n')[0].match(/\(([^)]+)\)\s*$/)[1].split(',')[0].trim();
      const reg = regScope.filter((r) => r.codes.includes(c));
      if (reg.length > 1) throw new Error(`${c} is in the scope of ${reg.map((r) => r.f).join(' and ')}`);
      packs.push([c, fam,
        part(`conversation/${f}`, s.preamble),
        part(`conversation/${f}#${key}`, sec),
        part(`uae_materials_brands/${f}`, md('uae_materials_brands/' + f)),
        ...reg.map((r) => part(`uae_regulations/${r.f}`, md('uae_regulations/' + r.f))),
        part(`uae_contract_practice.md#${fam}`, normsHead + '\n\n' + tableHead + '\n' + row[0]),
      ]);
    }
  }
  // a digest no trade reaches would never be read by any reply
  for (const f of [...regs.map((r) => 'uae_regulations/' + r), ...mats.map((m) => 'uae_materials_brands/' + m)]) {
    if (!partIds.includes(f)) throw new Error(`${f} is in no trade pack: no playbook category is in its scope`);
  }
  const text = [coreText, supplier, ...partText].join('\n\n');
  const sha = createHash('sha256').update(text).digest('hex');
  const files = [...CORE_FILES, 'supplier_howto.md', ...regs.map((f) => `uae_regulations/${f}`), ...convo.map((f) => `conversation/${f}`), ...mats.map((f) => `uae_materials_brands/${f}`)];
  return { text, core: coreText, supplier, partIds, partText, packs, sha, files, approxTokens: approxTokens(coreText) };
}

export function renderModule(b) {
  return `// GENERATED by scripts/kb/compile_brief.mjs from knowledge/brief/*.md -- do not edit by hand.\n` +
    `export const BRIEF_SHA256 = ${JSON.stringify(b.sha)};\n` +
    `export const BRIEF_VERSION = ${JSON.stringify(b.sha.slice(0, 12))};\n` +
    `export const BRIEF_FILES: string[] = ${JSON.stringify(b.files)};\n` +
    `// the CORE's estimated Sonnet tokens (approxTokens above); every reply carries the core\n` +
    `export const BRIEF_APPROX_TOKENS = ${b.approxTokens};\n` +
    `export const CONVERSATION_STYLE: string = ${JSON.stringify(readFileSync(join(DIR, 'conversation_style.md'), 'utf8').replace(/\r\n/g, '\n').trim())};\n` +
    `export const BRIEF_TEXT: string = ${JSON.stringify(b.core)};\n` +
    `export const BRIEF_SUPPLIER: string = ${JSON.stringify(b.supplier)};\n` +
    // the press, legal-notice and regulator position: read by the holding line and the CEO's escalation clock, never by every reply
    // (the core is at its cap; knowledge/brief/press_and_legal.md says why)
    `export const BRIEF_PRESS_LEGAL: string = ${JSON.stringify(readFileSync(join(DIR, 'press_and_legal.md'), 'utf8').replace(/\r\n/g, '\n').trim())};\n` +
    `export const BRIEF_PART_IDS: string[] = ${JSON.stringify(b.partIds)};\n` +
    `export const BRIEF_PART_TEXT: string[] = ${JSON.stringify(b.partText)};\n` +
    `// one row per trade: [category code, trade family, ...the part ids of its pack, in order]\n` +
    `export const BRIEF_PACKS: string[][] = ${JSON.stringify(b.packs)};\n` +
    `export const SEAT_FACTS_EXTERNAL: string = ${JSON.stringify(seatFacts(false))};\n` +
    `export const SEAT_FACTS_INTERNAL: string = ${JSON.stringify(seatFacts(true))};\n` +
    // one string per seat: the generated module stays data only (every_external_host_and_secret_is_registered)
    SEATS.map((s) => `export const SEAT_CARD_${s.toUpperCase()}: string = ${JSON.stringify(seatCard(s).text)};\n`).join('');
}

// THE SETTLED FACTS EVERY SEAT REASONS FROM (ceo, ledger 1003 stage 2, 19 Oct 2026). think(), the engine every seat
// uses, never carried the company brief: measured on the real-model seat exam, seats said the founder approves refunds,
// did not know the bank or the licence expiry, and used AED 187,500 for VAT. company.md (what the customer brief says)
// rides in every think() call; seats.md (internal facts and rulings) only when the audience is internal. Neither changes
// BRIEF_TEXT, so the customer chat's cached prefix is unchanged.
export function seatFacts(internal) {
  const md = (f) => readFileSync(join(DIR, f), 'utf8').replace(/\r\n/g, '\n').trim();
  return [md('company.md'), ...(internal ? [md('seats.md')] : [])].join('\n\n');
}

// EVERY SEAT CARRIES ITS OWN OPERATING FACTS (ceo, ledger 1003 stage 2, 19 Oct 2026). Measured on the after-exam
// (think() on the seats' real models, reworded questions): ceo 63/119, customer_support 35/96, accountant 53/109,
// it_engineer 42/109, marketing 38/78. Most misses were "not established" for a number, cadence, owner or rule that IS
// in the seat's pack (it_engineer:otp-usage-provider-watch holds cap_resend_emails_month 50000): retrieval returned
// generic kb_chunks at ~0.85 and the pack's short fact never reached the prompt. The card puts the pack's OWN facts in
// the cached prefix of every internal think() call, so they no longer depend on winning a ranking.
// Compiled by code from knowledge/seats/<seat>.json only -- a fact absent from the pack is absent from the card:
//   an entry is the company's own when its kind is 'company' or a source is internal:founder_instruction/... or
//   internal:memory/...; each sentence of it that carries a number, cadence, owner or rule word becomes one line,
//   verbatim (provenance parentheses such as "(instr 324)" dropped), tagged with its entry id. Duplicates are dropped.
//   Lines are chosen round-robin over the entries (each entry's numbered sentences first) to CARD_BUDGET characters (~4k tokens), then
//   printed in pack order. Byte-stable: same pack, same card.
//   prevented by: scripts/checks/every_seat_card_comes_from_its_pack.test.mjs
export const SEATS = ['ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing'];
export const CARD_BUDGET = 16000;
const CARRIES = /\d|\b(daily|weekly|monthly|hourly|quarterly|yearly|annual(ly)?|every|never|always|only|owns?|owner|approves?|approval|must|ceo|founder|accountant|it_engineer|customer_support|sales_engineer|marketing)\b/i;
const PROVENANCE = /\s*\([^()]*\b(instr|instruction|instructions|ledger|PR|duty)\b[^()]*\)/gi;
// A RULE TRAVELS WITH ITS EXCEPTION (it_engineer, 19 Nov 2026). Seat exam run 1 (15 Nov): customer_support-exam-10 was
// answered "the person is not transferred" citing [brief], because the card held "there is no escalation to a human" and the
// round-robin had dropped, two sentences later, "The only exception is a person who explicitly asks for a human on WhatsApp
// or social media; the founder is then emailed" (rulings 17, 721, 763). A card that overrides any SOURCE then states the
// opposite of the rule. So a sentence that opens with an exception (EXCEPTION below) is joined, as ONE line, to the sentences
// before it in its own line of the body: the rule and its exception are kept or dropped together, never one without the other.
const EXCEPTION = /^(?:the\s+)?(?:only\s+|one\s+)?(?:exceptions?|except|unless|however|but)\b/i;
export const cardSentences = (body) => String(body ?? '').replace(/\r\n/g, '\n').replace(PROVENANCE, '')
  .split(/\n+/).flatMap((para) => para.split(/(?<=[.;])\s+(?=[A-Z(])/).map((t) => t.replace(/\s+/g, ' ').trim()).filter(Boolean)
    .reduce((units, t) => (EXCEPTION.test(t) && units.length ? [[units.join(' '), t].join(' ')] : [...units, t]), []))
  .filter((t) => t.length >= 25 && CARRIES.test(t));

export function seatCard(seat, pack = JSON.parse(readFileSync(join(ROOT, 'knowledge/seats', seat + '.json'), 'utf8'))) {
  const own = pack.entries.filter(isOwnEntry);
  const seen = new Set();
  const cands = [];
  own.forEach((e, ei) => cardSentences(e.body_en).map((t, si) => ({ t, si, d: /\d/.test(t) ? 0 : 1 })).sort((a, b) => a.d - b.d || a.si - b.si).forEach(({ t, si }, rank) => {
    if (seen.has(t.toLowerCase())) return;
    seen.add(t.toLowerCase());
    cands.push({ ei, si, line: `- ${t} [${e.id}]`, pri: rank });
  }));
  const head = `# ${seat}: operating facts from its own verified pack (internal; settled, they override any SOURCE)\n`;
  let n = head.length;
  // Round-robin: every entry's first line before any entry's second, so a long entry cannot crowd out a short one.
  const keep = cands.slice().sort((a, b) => a.pri - b.pri || a.ei - b.ei || a.si - b.si)
    .filter((c) => (n + c.line.length + 1 <= CARD_BUDGET ? ((n += c.line.length + 1), true) : false))
    .sort((a, b) => a.ei - b.ei || a.si - b.si);
  const text = keep.length ? head + keep.map((c) => c.line).join('\n') : '';
  return { text, entries: own.length, lines: keep.length, dropped: cands.length - keep.length };
}

/** Writes knowledge/brief/seats/<seat>.md, or (check) returns the paths that differ from what the packs compile to. */
export function writeSeatCards(check = false) {
  const dir = join(DIR, 'seats');
  if (!check) mkdirSync(dir, { recursive: true });
  const stale = [];
  for (const s of SEATS) {
    const f = join(dir, s + '.md');
    const want = seatCard(s).text + '\n';
    if (check) { if ((existsSync(f) ? readFileSync(f, 'utf8') : '') !== want) stale.push(f); } else writeFileSync(f, want);
  }
  return stale;
}

if (process.argv[1]?.replaceAll('\\', '/').endsWith('scripts/kb/compile_brief.mjs')) {
  const b = compileBrief();
  const mod = renderModule(b);
  if (process.argv.includes('--check')) {
    const cur = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
    const stale = writeSeatCards(true);
    if (cur !== mod || stale.length) { console.error('brief.generated.ts or a seat card is stale: run node scripts/kb/compile_brief.mjs', stale.join(' ')); process.exit(1); }
    console.log(`brief up to date: ${b.files.length} files, core ~${b.approxTokens} tokens, ${b.packs.length} trade packs, ${b.sha.slice(0, 12)}`);
  } else {
    writeFileSync(OUT, mod);
    writeSeatCards();
    for (const s of SEATS) { const c = seatCard(s); console.log(`  card ${s}: ${c.entries} own entries, ${c.lines} lines, ${c.text.length} chars, ~${Math.round(c.text.length / 4)} tokens, ${c.dropped} lines over budget`); }
    const byId = new Map(b.partIds.map((id, i) => [id, b.partText[i]]));
    const packTok = b.packs.map(([c, , ...ids]) => [c, approxTokens(ids.map((id) => byId.get(id)).join('\n\n'))]).sort((x, y) => y[1] - x[1]);
    console.log(`  core ~${b.approxTokens} tokens, supplier part ~${approxTokens(b.supplier)}, ${b.packs.length} trade packs, largest ${packTok.slice(0, 3).map(([c, t]) => c + ' ~' + t).join(', ')}, smallest ${packTok.at(-1).join(' ~')}`);
    console.log(`wrote ${OUT}: ${b.files.length} files, ${b.text.length} chars, ${b.sha.slice(0, 12)}`);
  }
}
