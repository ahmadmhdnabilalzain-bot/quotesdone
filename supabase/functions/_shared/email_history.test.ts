// An e-mail reply reads the whole thread with that address, and only that address's (customer_support, 19 Nov 2026;
// ledger 1474). Until today email_triage gave the model the new mail alone. See _shared/email_history.ts.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { EMAIL_HISTORY_ROWS, emailConversation, redactLinks } from './email_history.ts';
import { UNANSWERED_NOTE } from './chat_history.ts';

type Row = Record<string, unknown>;
const ME = 'zz-demo-buyer@customer-history.invalid';
const OTHER = 'zz-demo-someone-else@customer-history.invalid';

// a PostgREST stand-in for the filters the helper uses: eq, ilike (escaped equality), lt, order, limit
function fakeAdmin(tables: Record<string, Row[]>, fail: Record<string, boolean> = {}) {
  const calls: { table: string; filters: string[] }[] = [];
  return { calls, from(table: string) {
    const filters: string[] = [];
    let rows = [...(tables[table] ?? [])];
    let lim = Infinity;
    const q = {
      select() { return q; },
      eq(c: string, v: unknown) { filters.push('eq ' + c); rows = rows.filter((r) => r[c] === v); return q; },
      ilike(c: string, p: string) { filters.push('ilike ' + c); const v = p.replace(/\\(.)/g, '$1'); rows = rows.filter((r) => String(r[c]).toLowerCase() === v); return q; },
      lt(c: string, v: number) { filters.push('lt ' + c); rows = rows.filter((r) => Number(r[c]) < v); return q; },
      order(c: string, o: { ascending: boolean }) { rows.sort((a, b) => (String(a[c]).localeCompare(String(b[c]), undefined, { numeric: true })) * (o.ascending ? 1 : -1)); return q; },
      limit(n: number) { lim = n; calls.push({ table, filters }); return Promise.resolve(fail[table] ? { data: null, error: { message: table + ' timed out' } } : { data: rows.slice(0, lim), error: null }); },
    };
    return q;
  } };
}

const world = () => ({
  inbound_messages: [
    { id: 1, from_email: ME, subject: 'Villa windows', body: 'Two villas in Al Barsha, 14 windows each.', created_at: '2026-11-10T08:00:00Z' },
    { id: 2, from_email: OTHER, subject: 'Private', body: 'Another person\'s mail that must never be read.', created_at: '2026-11-10T08:30:00Z' },
    { id: 3, from_email: ME, subject: 'Re: Villa windows', body: 'And the second villa needs sliding doors too.', created_at: '2026-11-12T09:00:00Z' },
    { id: 4, from_email: ME, subject: 'Now', body: 'The mail being answered now.', created_at: '2026-11-19T09:00:00Z' },
  ],
  notifications: [
    { type: 'inbound_reply', channel: 'email', to_email: ME, status: 'sent', subject: 'Re: Villa windows', body: 'Thanks: please post the job with the window sizes.', created_at: '2026-11-10T08:01:00Z' },
    { type: 'inbound_reply', channel: 'email', to_email: OTHER, status: 'sent', subject: 'Re: Private', body: 'Our reply to someone else.', created_at: '2026-11-10T08:31:00Z' },
    { type: 'inbound_reply', channel: 'email', to_email: ME, status: 'cancelled', subject: 'Re: x', body: 'A reply that never went.', created_at: '2026-11-12T09:01:00Z' },
    { type: 'login_otp', channel: 'email', to_email: ME, status: 'sent', subject: 'Your code', body: 'Your code is 123456', created_at: '2026-11-13T09:00:00Z' },
    { type: 'quote_ready', channel: 'whatsapp', to_email: ME, status: 'sent', subject: '', body: 'A WhatsApp message, not this thread.', created_at: '2026-11-13T10:00:00Z' },
  ],
});

Deno.test('the reply reads their earlier mail and what we sent, oldest first, and only theirs', async () => {
  const admin = fakeAdmin(world());
  const conv = await emailConversation(admin, { email: ' ZZ-Demo-Buyer@customer-history.invalid ', beforeId: 4, party: 'customer' });
  assertEquals(conv.map((t) => t.role), ['customer', 'seat', 'customer']);
  assert(conv[0].text.includes('14 windows each'));
  assert(conv[1].text.includes('post the job with the window sizes'));
  assert(conv[2].text.startsWith('Subject: Re: Villa windows') && conv[2].text.includes('sliding doors'));
  const all = conv.map((t) => t.text).join('\n');
  for (const never of ['must never be read', 'someone else', 'never went', '123456', 'WhatsApp message', 'answered now']) assert(!all.includes(never), never);
  // matched on the one address by equality, never a pattern (address_filter.ts)
  for (const c of admin.calls) assert(c.filters.some((f) => /^(eq|ilike) (from_email|to_email)$/.test(f)), JSON.stringify(c));
});

Deno.test('a mail of theirs that got no reply is marked so the new reply does not answer it', async () => {
  const w = world();
  w.notifications = [];
  const conv = await emailConversation(fakeAdmin(w), { email: ME, beforeId: 4, party: 'supplier' });
  assertEquals(conv.map((t) => t.role), ['supplier', 'supplier']);
  assert(conv[0].text.endsWith(UNANSWERED_NOTE));
});

Deno.test('a fixture address counts the captured reply (it never sends); a real one only what was sent', async () => {
  const w = world();
  w.notifications[0].status = 'skipped';
  assertEquals((await emailConversation(fakeAdmin(w), { email: ME, beforeId: 4, party: 'customer' })).filter((t) => t.role === 'seat').length, 0);
  assertEquals((await emailConversation(fakeAdmin(w), { email: ME, beforeId: 4, party: 'customer', fixture: true })).filter((t) => t.role === 'seat').length, 1);
});

Deno.test('a failed read is said and thins the answer; no address or no id reads nothing', async () => {
  const seen: string[] = [];
  const conv = await emailConversation(fakeAdmin(world(), { notifications: true }), { email: ME, beforeId: 4, party: 'customer' }, (e) => seen.push(e));
  assertEquals(conv.length, 2);   // their two mails, the read of ours failed
  assert(seen[0].includes('notifications timed out'));
  assertEquals(await emailConversation(fakeAdmin(world()), { email: 'not-an-address', beforeId: 4, party: 'customer' }), []);
  assertEquals(await emailConversation(fakeAdmin(world()), { email: ME, beforeId: 0, party: 'customer' }), []);
  assert(EMAIL_HISTORY_ROWS >= 100);
});

Deno.test('email_triage hands the thread to both reply roads and to the case', async () => {
  const src = await Deno.readTextFile(new URL('../email_triage/index.ts', import.meta.url));
  assert(/emailConversation\(admin, \{ email: m\.from_email, beforeId: Number\(m\.id\)/.test(src));
  assert(src.includes('past: conversation })'), 'loadCaseContext is given the thread');
  assert(src.includes('message: q, conversation: kase.past,'), 'aiReply reads the thread');
  assert(src.includes('{ conversation: kase.past }'), 'think reads the thread');
  assert(!src.includes('conversation: [],'), 'the fault handover is not handed an empty conversation');
});

Deno.test('a sign-in link with its token never reaches the model: it reads [link]', async () => {
  const w = world();
  w.notifications[0].body = 'Your quotes are ready: https://quotesdone.com/portal?t=zzSECRETtoken123 (valid 7 days).';
  w.inbound_messages[2].body = 'I clicked <https://quotesdone.com/en/portal?lang=en&t=zzSECRETtoken456> and it expired.';
  const all = (await emailConversation(fakeAdmin(w), { email: ME, beforeId: 4, party: 'customer' })).map((t) => t.text).join('\n');
  assert(!all.includes('zzSECRET'), 'a token reached the model');
  assert(all.includes('Your quotes are ready: [link] (valid 7 days).'));
  assert(all.includes('I clicked <[link]> and it expired.'));
  assertEquals(redactLinks('see https://quotesdone.com/how-it-works?ref=mail'), 'see https://quotesdone.com/how-it-works?ref=mail');
});
