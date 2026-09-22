// Create the WhatsApp menu as Twilio Content items and record their SIDs (customer_support, 22 Sep 2026).
//
// Founder_instruction 759: a professional welcome and OPTIONS, "not simple text". wa_inbound sends the
// menu as a twilio/list-picker (an interactive list — session content, so no Meta approval is needed:
// it only ever answers a message the person sent in the last 24 hours). Four items: English and
// Arabic, each for suppliers and for everyone else. Every word comes from
// supabase/functions/wa_inbound/menu.ts — the same module the function sends from — so the list and the
// numbered fallback can never say different things.
//
// IDEMPOTENT. Each item's friendly_name carries a hash of its content. Re-running finds the existing
// item by that name and creates nothing; a changed menu.ts gets a new name, so a new item is created and
// its SID replaces the old one in app_secrets.wa_menu_content_sids (Content items are immutable).
//
// DRY RUN BY DEFAULT: prints what it would create and the SIDs it already finds. --apply creates the
// missing items and writes app_secrets.wa_menu_content_sids. It sends no message to anyone.
//
//   node scripts/whatsapp/create_menu_content.mjs            # dry run
//   node scripts/whatsapp/create_menu_content.mjs --apply    # create + record
//
// Credentials: app_secrets twilio_account_sid / twilio_api_key_sid / twilio_api_key_secret, read through
// the Supabase management token (scripts/lib/db.mjs). Nothing is printed but SIDs.
import { createHash } from 'node:crypto';
import { sql, lit } from '../lib/db.mjs';
import { contentKey, MENU_BUTTON, menuAsText, menuItems, WELCOME_TAIL } from '../../supabase/functions/wa_inbound/menu.ts';

const APPLY = process.argv.includes('--apply');
const CONTENT = 'https://content.twilio.com/v1/Content';

/** The four Content definitions, built from menu.ts. */
export function definitions() {
  const out = [];
  for (const lang of ['en', 'ar']) {
    for (const audience of ['unknown', 'supplier']) {
      const body = '{{1}}\n\n' + WELCOME_TAIL[lang];
      const types = {
        'twilio/list-picker': {
          body, button: MENU_BUTTON[lang],
          items: menuItems(lang, audience).map((i) => ({ id: i.id, item: i.item, description: i.description })),
        },
        // Where a list cannot be shown, Twilio falls back to this: the same menu as numbered text.
        'twilio/text': { body: menuAsText(lang, audience, '{{1}}') },
      };
      const sample = lang === 'ar' ? 'أهلًا وسهلًا، مرحبًا بكم في QuotesDone.' : 'Good day, and welcome to QuotesDone.';
      const hash = createHash('sha1').update(JSON.stringify(types)).digest('hex').slice(0, 8);
      const key = contentKey(lang, audience);
      out.push({ key, friendly_name: 'quotesdone_' + key + '_' + hash, language: lang, variables: { 1: sample }, types });
    }
  }
  return out;
}

async function main() {
  const rows = await sql("select key, value from public.app_secrets where key in ('twilio_account_sid','twilio_api_key_sid','twilio_api_key_secret','wa_menu_content_sids')");
  const s = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  if (!s.twilio_api_key_sid || !s.twilio_api_key_secret) throw new Error('twilio_api_key_sid / twilio_api_key_secret missing from app_secrets');
  const auth = 'Basic ' + Buffer.from(s.twilio_api_key_sid + ':' + s.twilio_api_key_secret).toString('base64');

  // Every existing Content item, by friendly_name.
  const existing = new Map();
  for (let url = CONTENT + '?PageSize=500'; url;) {
    const r = await fetch(url, { headers: { Authorization: auth } });
    if (!r.ok) throw new Error('listing Content failed: HTTP ' + r.status + ' ' + (await r.text()).slice(0, 200));
    const j = await r.json();
    for (const c of j.contents || []) existing.set(c.friendly_name, c.sid);
    url = j.meta?.next_page_url || null;
  }

  const sids = {};
  for (const d of definitions()) {
    const have = existing.get(d.friendly_name);
    if (have) { sids[d.key] = have; console.log('exists  ', d.key, have, d.friendly_name); continue; }
    if (!APPLY) { console.log('WOULD CREATE', d.key, d.friendly_name); continue; }
    const r = await fetch(CONTENT, {
      method: 'POST', headers: { Authorization: auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ friendly_name: d.friendly_name, language: d.language, variables: d.variables, types: d.types }),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || !/^HX[0-9a-f]{32}$/i.test(j.sid || '')) throw new Error('creating ' + d.key + ' failed: HTTP ' + r.status + ' ' + JSON.stringify(j).slice(0, 300));
    sids[d.key] = j.sid; console.log('created ', d.key, j.sid, d.friendly_name);
  }

  const complete = definitions().every((d) => sids[d.key]);
  if (!APPLY) { console.log(complete ? 'all four exist; --apply would only (re)record the SIDs' : 'dry run: nothing created, nothing recorded'); if (!complete) return; }
  const value = JSON.stringify(sids);
  if (s.wa_menu_content_sids === value) { console.log('app_secrets.wa_menu_content_sids already current'); return; }
  if (!APPLY) return;
  await sql(`insert into public.app_secrets (key, value) values ('wa_menu_content_sids', ${lit(value)})
             on conflict (key) do update set value = excluded.value, updated_at = now()`);
  const back = await sql("select value from public.app_secrets where key = 'wa_menu_content_sids'");
  if (back[0]?.value !== value) throw new Error('app_secrets.wa_menu_content_sids did not read back as written');
  console.log('recorded app_secrets.wa_menu_content_sids =', value);
}

if (import.meta.url === new URL(process.argv[1], 'file:').href || process.argv[1]?.endsWith('create_menu_content.mjs')) {
  main().catch((e) => { console.error(String(e?.message || e)); process.exit(1); });
}
