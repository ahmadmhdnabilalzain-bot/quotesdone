// EVERY INQUIRY CONVERSATION KEEPS ONE STATE, AND NO SURFACE FORGETS (10 Nov 2026). Seat: sales_engineer, with
// customer_support for the shared state. Subject: scripts/sql/every_inquiry_conversation_keeps_one_state_every_surface_reads.sql
// and supabase/functions/_shared/inquiry_state.ts. Founder ledger 1572: "Hard limit 100 messages per inquiry, and nothing
// said in message 2 may be forgotten by message 30+"; Arabic dialects; ledger 1008: suppliers always in English.
//
// Reads the touched files offline (no database, no network). It fails when:
//   * the state table loses its RLS, its deliberate policy or its revokes, or a routine its pinned search_path or revoke;
//   * the SQL is neither in MANIFEST nor waiting in scripts/sql/pending/ with a note;
//   * a history window the design audit measured comes back: the request chat's reply writer cut to the last twelve turns,
//     the intake readings cut to the first 4,000 characters, the WhatsApp intent reading cut to six turns, supplier
//     onboarding cut to eight;
//   * the request chat's supplier count asks the matcher with raw intake slugs again;
//   * a surface stops writing the state, or the cap, the carry or the dialect register is unwired.
//   node --test scripts/checks/every_inquiry_conversation_keeps_one_state.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');
const NAME = 'every_inquiry_conversation_keeps_one_state_every_surface_reads';
const SQL = `scripts/sql/${NAME}.sql`;
const FN = 'supabase/functions/';
// code without its comment lines, so a comment describing a removed window can never satisfy or fail a rule
const code = (f) => read(f).split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');

test('the state table is service-role only, its routines pinned and closed, and the file is pending or listed', () => {
  const sql = read(SQL);
  assert.match(sql, /^-- .*\n-- Seat: sales_engineer/m);
  assert.match(sql, /create table if not exists public\.inquiry_state/);
  assert.match(sql, /alter table public\.inquiry_state enable row level security/);
  assert.match(sql, /create policy inquiry_state_service_role_only on public\.inquiry_state\s+as permissive for all to public using \(false\) with check \(false\)/);
  assert.match(sql, /revoke all on public\.inquiry_state from anon, authenticated/);
  for (const [fn, sig] of [['fn_inquiry_state_merge', 'text, text, jsonb'], ['fn_inquiry_state_carry', 'text, text, text, uuid']]) {
    const body = sql.slice(sql.indexOf(`create or replace function public.${fn}(`));
    assert.match(body.slice(0, 400), /security definer\s+set search_path to 'public', 'pg_temp'/, fn + ': search_path not pinned');
    assert.ok(sql.includes(`revoke execute on function public.${fn}(${sig}) from public, anon, authenticated;`), fn + ': no revoke on its signature');
  }
  for (const s of ['open', 'converging', 'summarising', 'handed_off', 'carried', 'closed']) assert.ok(sql.includes(`'${s}'`), 'status ' + s);
  const listed = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(SQL);
  const pending = fs.existsSync(path.join(ROOT, `scripts/sql/pending/${NAME}.txt`));
  assert.ok(listed !== pending, 'exactly one of: a MANIFEST line (applied) or a pending note (not yet applied)');
  assert.ok(fs.existsSync(path.join(ROOT, `scripts/sql/${NAME}_probe.sql`)) && fs.existsSync(path.join(ROOT, `scripts/sql/pending/${NAME}_probe.txt`)));
  assert.match(read(`scripts/sql/${NAME}_probe.sql`), /raise exception 'CHK<<%>>'/);
});

test('no history window the audit measured is back', () => {
  assert.doesNotMatch(code(FN + 'inquiry_intake/slots.ts'), /conversation\.slice\(-\d+\)/, 'the request chat reply writer is windowed again');
  assert.doesNotMatch(code(FN + '_shared/reasoned_decisions.ts'), /conversation\.slice\(0, *\d+\)/, 'an intake reading reads only the start again');
  assert.doesNotMatch(code(FN + '_shared/reasoned_channels.ts'), /conversation\.slice\(-\d+\)/, 'the WhatsApp intent reading is windowed again');
  assert.match(code(FN + '_shared/reasoned_channels.ts'), /conversation: intentWindow\(o\.conversation\)/);
  assert.doesNotMatch(code(FN + 'supplier_onboard/index.ts'), /history\.slice\(-\d+\)/, 'supplier onboarding is windowed again');
  assert.match(code(FN + 'supplier_onboard/index.ts'), /fitHistory\(/);
});

test('the request chat counts suppliers the way dispatch does', () => {
  const h = code(FN + 'inquiry_intake/handle.ts');
  assert.doesNotMatch(h, /rpc\('fn_match_capability'/, 'handle.ts calls the matcher directly again (raw slugs)');
  assert.match(h, /supplierCount\(/);
  const c = code(FN + 'inquiry_intake/supplier_count.ts');
  assert.ok(c.indexOf("'fn_taxonomy_trades_for'") > -1 && c.indexOf("'fn_taxonomy_trades_for'") < c.indexOf("'fn_match_capability'"));
});

test('every surface writes the state; the cap, the carry and the register are wired', () => {
  const h = code(FN + 'inquiry_intake/handle.ts');
  for (const x of ['capStage(replyNo)', "mergeState(admin, stKey, 'request_chat'", "b.carry_from === 'portal'", 'openPortalEpisode(', 'carryState(', 'slotUnknown', 'unknown_keys', "stage === 'over'"]) assert.ok(h.includes(x), 'handle.ts: ' + x);
  const p = code(FN + 'sales_engineer/actions/portal.ts');
  for (const x of ['capStage(replyNo)', "mergeState(admin, episodeKey, 'portal_assistant'", 'episodeStart(job)', "stage === 'over'", 'handOffAtCap(', 'dialect }, lang)']) assert.ok(p.includes(x), 'portal.ts: ' + x);
  assert.ok(code(FN + 'wa_inbound/say.ts').includes("mergeState(admin, whatsappKey(From), 'whatsapp'"));
  assert.ok(code(FN + 'site_assistant/index.ts').includes("mergeState(admin, convKey, 'widget'"));
  assert.ok(code('src/components/me/dashboard/Dashboard.tsx').includes('carryChat'));
  assert.ok(code('src/components/me/NewRequest.tsx').includes("carry_from: 'portal'"));
  // the register: an Arabic reply mirrors the customer's dialect; a supplier is never given one (ledger 1008)
  const ai = code(FN + '_shared/ai_reply.ts');
  assert.match(ai, /Reply in \$\{replyLang === 'ar' \? arabicRegister\(r\.dialect\)/);
  assert.match(ai, /const replyLang: 'en' \| 'ar' = r\.audience === 'supplier' \? 'en' : r\.lang;/);
  assert.match(code(FN + 'site_assistant/index.ts'), /arabicRegister\(audience === 'supplier' \? null : visitorDialect\)/);
  assert.match(code(FN + 'wa_inbound/say.ts'), /aud === 'supplier' \|\| aud === 'founder' \? null : dialectOf/);
});
