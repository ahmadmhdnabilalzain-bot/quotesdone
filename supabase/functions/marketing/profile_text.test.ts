// deno test --allow-read supabase/functions/marketing/profile_text.test.ts
// Instruction 920: one description, every profile within its limit, nothing a variant says that the canonical does not.
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { length, pushWhatsapp, pushYoutube, render, text, VARIANTS, violations } from './profile_text.ts';

Deno.test('every variant is built from canonical sentences and fits its platform', () => {
  assertEquals(violations(), []);
  for (const v of VARIANTS) console.log(`${v.platform}.${v.field} ${length(render(v))}/${v.limit} [${v.api}]`);
});

Deno.test('the platforms the founder named are all there', () => {
  const ids = new Set(VARIANTS.map((v) => v.platform + '.' + v.field));
  for (const id of ['whatsapp.about', 'whatsapp.description', 'instagram.bio', 'facebook.intro', 'linkedin.about', 'linkedin.tagline', 'tiktok.bio', 'youtube.description', 'x.bio']) assert(ids.has(id), id);
});

Deno.test('the corrected claims: trades suppliers confirm, drawings covered, first 1,000 free, no licence-activity matching', () => {
  const all = VARIANTS.map(render).join('\n');
  assert(/trades they confirm/.test(all) && /identity details are covered/.test(all) && /first 1,000 suppliers join free, permanently/.test(all));
  assert(!/licen[cs]e activit/i.test(all));
});

const res = (status: number, body: unknown) => new Response(JSON.stringify(body), { status });
Deno.test('whatsapp: a 202 that does not read back is a failure, not a success', async () => {
  const old = { sid: 'XE' + '0'.repeat(32), sender_id: 'whatsapp:+971500000000', status: 'ONLINE', profile: { about: 'old', description: 'old' } };
  const calls: string[] = [];
  const f = async (url: string, init?: RequestInit) => { calls.push((init?.method || 'GET') + ' ' + url.split('?')[0]);
    if (url.includes('/Senders/XE')) return res(202, {}); if (url.includes('monitor')) return res(200, { alerts: [{ error_code: '63115' }] });
    return res(200, { senders: [old] }); };
  await assertRejects(() => pushWhatsapp(f, 'Basic x', '+971500000000', new Date().toISOString()), Error, '63115');
  assert(calls.some((c) => c.startsWith('POST') && c.includes('/Senders/XE')));
});

Deno.test('whatsapp: equal already means no write', async () => {
  const s = { sid: 'XE1', sender_id: 'whatsapp:+971500000000', profile: { about: text('whatsapp', 'about'), description: text('whatsapp', 'description') } };
  let posts = 0;
  const f = async (_u: string, init?: RequestInit) => { if (init?.method === 'POST') posts++; return res(200, { senders: [s] }); };
  assertEquals((await pushWhatsapp(f, 'Basic x', '+971500000000', '')).status, 'matches');
  assertEquals(posts, 0);
});

Deno.test('youtube: only the description changes; every other branding field is sent back', async () => {
  let live = { id: 'UC1', brandingSettings: { channel: { title: 'QuotesDone', keywords: 'k', description: 'old' }, image: { x: 1 } } };
  let sent: any = null;
  const f = async (_u: string, init?: RequestInit) => { if (init?.method === 'PUT') { sent = JSON.parse(String(init.body)); live = sent; return res(200, sent); } return res(200, { items: [live] }); };
  assertEquals((await pushYoutube(f, 't')).status, 'updated');
  assertEquals(sent.brandingSettings.channel.keywords, 'k');
  assertEquals(sent.brandingSettings.image, { x: 1 });
  assertEquals(sent.brandingSettings.channel.description, text('youtube', 'description'));
});
