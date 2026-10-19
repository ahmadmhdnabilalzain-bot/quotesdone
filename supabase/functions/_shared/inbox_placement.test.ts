// The folder classification, the exact allowlist and the fail-closed reader of inbox_placement.ts.
//   deno test supabase/functions/_shared/inbox_placement.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { addressOf, authVerdicts, forefront, gmailFolder, gmailIsOwnCopy, graphFolder, MAX_PAGES, placementTick, readGmail, readOutlook as readOutlookWith, SEED_GMAIL, SEED_OUTLOOK, seedAllowed, worstFolder } from './inbox_placement.ts';

const TOKEN = 'QD0123456789';
const SENDER = 'info@quotesdone.com';
const creds: Record<string, string> = {
  google_oauth_client_id: 'gid', google_oauth_client_secret: 'gsec', gmail_seed_refresh_token: 'grt',
  ms_graph_tenant_id: 'tid', ms_graph_client_id: 'mid', ms_graph_client_secret: 'msec',
};
const sec = (over: Record<string, string> = {}) => async (k: string) => ({ ...creds, ...over })[k] ?? '';
const ok = (o: unknown) => new Response(JSON.stringify(o), { status: 200 });
const since = () => new Date().toISOString();
// readOutlook reads the M365 app from the edge environment; the tests hand it one through its env parameter. Never
// Deno.env.set: `npm test` runs the Deno suite without --allow-env, and a top-level set is an uncaught NotCapable.
const M365_ENV: Record<string, string> = { MS_TENANT_ID: 'tid', MS_CLIENT_ID: 'mid', MS_CLIENT_SECRET: 'msec' };
const readOutlook = (...a: Parameters<typeof readOutlookWith>) => readOutlookWith(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7] ?? ((k) => M365_ENV[k]));

type GMsg = { labels: string[]; from?: string };
// A fake Gmail: the profile says `who`, and the token matches these messages (labels + From header).
function gmail(msgs: (GMsg | string[])[], who = SEED_GMAIL) {
  const list = msgs.map((m) => (Array.isArray(m) ? { labels: m, from: 'QuotesDone <' + SENDER + '>' } : m));
  const calls: string[] = [];
  const f = async (u: string) => {
    calls.push(u);
    if (u.startsWith('https://oauth2.googleapis.com/token')) return ok({ access_token: 'at' });
    if (u.endsWith('/profile')) return ok({ emailAddress: who });
    if (u.includes('/messages?')) {
      assert(u.includes('includeSpamTrash=true'), 'the search must include spam and trash');
      assert(decodeURIComponent(u).includes('subject:' + TOKEN), 'the search must match the run token');
      return ok({ messages: list.map((_, i) => ({ id: 'm' + i })) });
    }
    const i = Number(u.match(/messages\/m(\d+)/)?.[1]);
    assert(u.includes('metadataHeaders=From'), 'the From header must be read');
    return ok({ id: 'm' + i, labelIds: list[i].labels, payload: { headers: [{ name: 'From', value: list[i].from },
      { name: 'Authentication-Results', value: 'mx.google.com; dkim=pass header.i=@quotesdone.com; spf=softfail (google.com: domain of transitioning x) smtp.mailfrom=x; dmarc=fail (p=NONE) header.from=quotesdone.com' }] } });
  };
  return { f, calls };
}

type OMsg = { subject: string; parent: string; from?: string };
// A fake Graph: well-known folder ids, and the messages it holds; `pageSize` splits a listing over nextLinks.
function graph(msgs: OMsg[], opts: { junkOnlyInJunkList?: boolean; me?: string; pageSize?: number; endless?: boolean } = {}) {
  const calls: string[] = [];
  const f = async (u: string, init?: RequestInit) => {
    calls.push(u);
    if (u.startsWith('https://login.microsoftonline.com/')) {
      const b = String(init?.body);
      return ok({ access_token: 'at', ...(b.includes('refresh_token') ? { refresh_token: 'RT-NEW-SECRET' } : {}) });
    }
    if (/\/me\?\$select=mail/.test(u)) return ok({ mail: opts.me ?? SEED_OUTLOOK });
    const wk = u.match(/mailFolders\/(inbox|junkemail|deleteditems|sentitems|drafts)\?\$select=id/);
    if (wk) return ok({ id: 'F-' + wk[1] });
    if (u.includes('$select=internetMessageHeaders')) return ok({ internetMessageHeaders: [
      { name: 'X-Forefront-Antispam-Report', value: 'CIP:1.2.3.4;CTRY:US;LANG:en;SCL:5;SRV:;IPV:NLI;SFV:SPM;H:x;PTR:x;CAT:SPM;SFS:(1);DIR:INB;' },
      { name: 'Authentication-Results', value: 'spf=pass (sender IP is 1.2.3.4) smtp.mailfrom=quotesdone.com; dkim=pass (signature was verified) header.d=quotesdone.com;dmarc=pass action=none header.from=quotesdone.com;compauth=pass reason=100' }] });
    const inJunkList = u.includes('/mailFolders/junkemail/messages');
    const all = msgs.filter((m) => !opts.junkOnlyInJunkList || (m.parent === 'F-junkemail') === inJunkList)
      .map((m, i) => ({ id: 'g' + i, subject: m.subject, parentFolderId: m.parent, from: { emailAddress: { address: m.from ?? SENDER } } }));
    const page = Number(new URL(u).searchParams.get('page') || '0');
    const size = opts.pageSize ?? 50;
    const value = all.slice(page * size, page * size + size);
    const more = opts.endless || (page + 1) * size < all.length;
    const base = u.split('?')[0];
    return ok({ value: opts.endless ? [] : value, ...(more ? { '@odata.nextLink': `${base}?page=${page + 1}` } : {}) });
  };
  return { f, calls };
}
const subj = 'Invitation (ref ' + TOKEN + ')';

Deno.test('Gmail labels: INBOX is inbox (a category tab still counts), SPAM and TRASH win, anything else is other', () => {
  assertEquals(gmailFolder(['INBOX', 'UNREAD']), 'inbox');
  assertEquals(gmailFolder(['INBOX', 'CATEGORY_PROMOTIONS']), 'inbox');
  assertEquals(gmailFolder(['SPAM', 'UNREAD']), 'spam');
  assertEquals(gmailFolder(['TRASH']), 'trash');
  assertEquals(gmailFolder(['CATEGORY_UPDATES']), 'other');
  assertEquals(gmailFolder(undefined), 'other');
  assert(gmailIsOwnCopy(['SENT']) && gmailIsOwnCopy(['DRAFT']) && !gmailIsOwnCopy(['INBOX']));
});

Deno.test('Graph folders: Inbox, JunkEmail -> spam, DeletedItems -> trash, unknown -> other', () => {
  const ids = { inbox: 'A', junkemail: 'J', deleteditems: 'D' };
  assertEquals(graphFolder('A', ids), 'inbox');
  assertEquals(graphFolder('J', ids), 'spam');
  assertEquals(graphFolder('D', ids), 'trash');
  assertEquals(graphFolder('X', ids), 'other');
  assertEquals(graphFolder('', ids), 'other');
  assertEquals(graphFolder('A', {}), 'other', 'no well-known ids read: never assume Inbox');
});

Deno.test('several copies: the worst decides; none: not_found; a From is compared by its address', () => {
  assertEquals(worstFolder(['inbox', 'spam']), 'spam');
  assertEquals(worstFolder(['inbox', 'inbox']), 'inbox');
  assertEquals(worstFolder([]), 'not_found');
  assertEquals(addressOf('QuotesDone <Info@QuotesDone.com>'), 'info@quotesdone.com');
  assertEquals(addressOf(' sender@example.com '), 'sender@example.com');
});

Deno.test('the allowlist is two exact addresses, each tied to its provider', () => {
  assert(seedAllowed(SEED_GMAIL, 'gmail') && seedAllowed(' Management@QuotesDone.com ', 'outlook'));
  for (const bad of ['ahmadmhdnabilalzain+x@gmail.com', 'management@doratajewelries.com', 'supplier@quotesdone.com', 'test-abc@srv1.mail-tester.com',
    'management@quotesdone.com.evil.example', 'x@quotesdone.com', '', null, 'someone@gmail.com']) {
    assert(!seedAllowed(bad), `accepted ${bad}`);
  }
  assert(!seedAllowed(SEED_OUTLOOK, 'gmail') && !seedAllowed(SEED_GMAIL, 'outlook'), 'an address was accepted for the other provider');
});

Deno.test('a refused address is refused before any network call', async () => {
  let called = 0;
  const f = async () => { called++; return ok({}); };
  const g = await readGmail(f, sec(), 'someone@gmail.com', TOKEN, SENDER);
  const o = await readOutlook(f, sec(), 'management@doratajewelries.com', TOKEN, since(), SENDER);
  assertEquals([g.folder, o.folder], [null, null]);
  assert(String(g.detail.error).startsWith('refused') && String(o.detail.error).startsWith('refused'));
  assertEquals(called, 0);
});

Deno.test('Gmail: inbox, spam, not found', async () => {
  assertEquals((await readGmail(gmail([['INBOX']]).f, sec(), SEED_GMAIL, TOKEN, SENDER)).folder, 'inbox');
  assertEquals((await readGmail(gmail([['SPAM']]).f, sec(), SEED_GMAIL, TOKEN, SENDER)).folder, 'spam');
  assertEquals((await readGmail(gmail([]).f, sec(), SEED_GMAIL, TOKEN, SENDER)).folder, 'not_found');
});

Deno.test('Gmail: a reply copy in Sent plus the original in Inbox is inbox; a token mail from another sender is ignored', async () => {
  const r = await readGmail(gmail([['SENT'], ['DRAFT'], ['INBOX']]).f, sec(), SEED_GMAIL, TOKEN, 'QuotesDone <' + SENDER + '>');
  assertEquals(r.folder, 'inbox');
  assertEquals([r.detail.skipped_own_copies, r.detail.skipped_other_sender], [2, 0]);
  const spoof = await readGmail(gmail([{ labels: ['SPAM'], from: 'someone <x@evil.example>' }, ['INBOX']]).f, sec(), SEED_GMAIL, TOKEN, SENDER);
  assertEquals(spoof.folder, 'inbox', 'another sender\'s token mail in spam decided the placement');
  const only = await readGmail(gmail([{ labels: ['INBOX'], from: 'x@evil.example' }]).f, sec(), SEED_GMAIL, TOKEN, SENDER);
  assertEquals(only.folder, 'not_found', 'another sender\'s token mail counted as the seed');
});

Deno.test('Gmail: a credential that opens another mailbox is refused, not read', async () => {
  assertEquals((await readGmail(gmail([['INBOX']], 'someone.else@gmail.com').f, sec(), SEED_GMAIL, TOKEN, SENDER)).folder, null);
});

Deno.test('Outlook (application): inbox, junk found only in the Junk list, deleted, not found', async () => {
  assertEquals((await readOutlook(graph([{ subject: subj, parent: 'F-inbox' }]).f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER)).folder, 'inbox');
  assertEquals((await readOutlook(graph([{ subject: subj, parent: 'F-junkemail' }], { junkOnlyInJunkList: true }).f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER)).folder, 'spam');
  assertEquals((await readOutlook(graph([{ subject: subj, parent: 'F-deleteditems' }]).f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER)).folder, 'trash');
  assertEquals((await readOutlook(graph([{ subject: 'another mail', parent: 'F-inbox' }]).f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER)).folder, 'not_found');
  const app = graph([]); await readOutlook(app.f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER);
  assert(app.calls.some((u) => u.includes('/users/' + encodeURIComponent(SEED_OUTLOOK) + '/')), 'application mode must name the one seed mailbox');
});

Deno.test('Outlook: a reply in Sent Items / Drafts plus the original in Inbox is inbox; another sender is ignored', async () => {
  const r = await readOutlook(graph([{ subject: 'RE: ' + subj, parent: 'F-sentitems', from: SEED_OUTLOOK }, { subject: 'FW: ' + subj, parent: 'F-drafts', from: SEED_OUTLOOK },
    { subject: subj, parent: 'F-inbox' }]).f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER);
  assertEquals(r.folder, 'inbox');
  assertEquals(r.detail.skipped_own_copies, 2);
  const spoof = await readOutlook(graph([{ subject: subj, parent: 'F-junkemail', from: 'x@evil.example' }, { subject: subj, parent: 'F-inbox' }]).f,
    sec(), SEED_OUTLOOK, TOKEN, since(), SENDER);
  assertEquals(spoof.folder, 'inbox');
});

Deno.test('Outlook: a busy mailbox is paged, and a listing cut at the bound is unread, never not_found', async () => {
  const filler = Array.from({ length: 120 }, (_, i) => ({ subject: 'newsletter ' + i, parent: 'F-inbox' }));
  const paged = graph([...filler, { subject: subj, parent: 'F-junkemail' }], { pageSize: 50 });
  assertEquals((await readOutlook(paged.f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER)).folder, 'spam', 'the seed on page 3 was missed');
  const endless = graph([], { endless: true });
  const r = await readOutlook(endless.f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER);
  assertEquals(r.folder, null);
  assertEquals(endless.calls.filter((u) => u.includes('/messages')).length, 2 * MAX_PAGES);
});

Deno.test('FAIL CLOSED: missing credentials, an HTTP error, a thrown fetch or no sender never read as inbox', async () => {
  const noG = await readGmail(gmail([['INBOX']]).f, sec({ gmail_seed_refresh_token: '' }), SEED_GMAIL, TOKEN, SENDER);
  assertEquals(noG.folder, null); assert(String(noG.detail.error).includes('gmail_seed_refresh_token'));
  assertEquals((await readOutlook(graph([]).f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER, undefined, () => '')).folder, null);
  const e400 = async () => new Response('{"error":"invalid_grant"}', { status: 400 });
  assertEquals((await readGmail(e400, sec(), SEED_GMAIL, TOKEN, SENDER)).folder, null);
  assertEquals((await readOutlook(e400, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER)).folder, null);
  const boom = () => Promise.reject(new Error('network down'));
  assertEquals((await readGmail(boom, sec(), SEED_GMAIL, TOKEN, SENDER)).folder, null);
  assertEquals((await readOutlook(boom, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER)).folder, null);
  assertEquals((await readGmail(gmail([['INBOX']]).f, sec(), SEED_GMAIL, 'not-a-token', SENDER)).folder, null);
  assertEquals((await readGmail(gmail([['INBOX']]).f, sec(), SEED_GMAIL, TOKEN, '')).folder, null);
});

Deno.test('the tick reads only a sent seed, and records a failed reading as null (the database holds the batch)', async () => {
  const rpcs: [string, Record<string, unknown> | undefined][] = [];
  const due = { action: 'read', dubai_day: '2026-09-28', token: TOKEN, since: since(), sender: SENDER,
    gmail: { to: SEED_GMAIL, sent: true, folder: null }, outlook: { to: SEED_OUTLOOK, sent: false, folder: null } };
  const rpc = async (fn: string, args?: Record<string, unknown>) => {
    rpcs.push([fn, args]);
    return { data: fn === 'fn_invite_placement_due' ? due : { recorded: true, verdict: 'pending' }, error: null };
  };
  const out = await placementTick(rpc, () => Promise.reject(new Error('down')), sec());
  assertEquals(out.ok, true);
  const rec = rpcs.find(([fn]) => fn === 'fn_invite_placement_record')?.[1];
  assert(rec, 'nothing recorded');
  assertEquals((rec.p_gmail as { folder: unknown }).folder, null);
  assertEquals(rec.p_outlook, null, 'the unsent Outlook seed was read');
});

Deno.test('the public answer carries no token, From or notification id', async () => {
  const due = { action: 'read', dubai_day: '2026-09-28', token: TOKEN, since: since(), sender: SENDER,
    gmail: { to: SEED_GMAIL, sent: true, folder: null }, outlook: { to: SEED_OUTLOOK, sent: true, folder: null } };
  const rpc = async (fn: string) => ({ data: fn === 'fn_invite_placement_due' ? due : { recorded: true, verdict: 'inbox', notification: 42 }, error: null });
  const both = async (u: string, init?: RequestInit) => (u.includes('googleapis') ? gmail([['INBOX']]).f(u) : graph([{ subject: subj, parent: 'F-inbox' }]).f(u, init));
  const out = JSON.stringify(await placementTick(rpc, both, sec()));
  for (const leak of [TOKEN, SENDER, SEED_GMAIL, SEED_OUTLOOK, '42']) assert(!out.includes(leak), `the answer leaks ${leak}: ${out}`);
  assert(out.includes('"verdict":"inbox"'));
  const queued = JSON.stringify(await placementTick(async () => ({ data: { action: 'queued', dubai_day: '2026-09-28', token: TOKEN, notifications: [7, 8] }, error: null }), both, sec()));
  assert(!queued.includes(TOKEN) && !queued.includes('notifications'), queued);
});

Deno.test('the tick does nothing but ask when the database says idle, queued or settled', async () => {
  let fetched = 0;
  for (const action of ['idle', 'queued', 'settled']) {
    const out = await placementTick(async () => ({ data: { action }, error: null }), async () => { fetched++; return ok({}); }, sec());
    assertEquals(out.action, action);
  }
  assertEquals(fetched, 0);
  const err = await placementTick(async () => ({ data: null, error: { message: 'boom', code: 'XX000' } }), async () => ok({}), sec());
  assertEquals(err.ok, false);
});

Deno.test('deployed before its SQL: a missing routine is "skipped: schema not applied", not a failing step, and nothing is read', async () => {
  let fetched = 0;
  for (const code of ['42883', '42P01', 'PGRST202', 'PGRST205']) {
    const out = await placementTick(async () => ({ data: null, error: { message: 'missing', code } }), async () => { fetched++; return ok({}); }, sec());
    assertEquals([out.ok, out.skipped], [true, 'schema not applied']);
  }
  assertEquals(fetched, 0);
});

Deno.test('junk is diagnosed: Gmail labels + Authentication-Results; Microsoft SCL / SFV / CAT + Authentication-Results', async () => {
  const g = await readGmail(gmail([['SPAM', 'CATEGORY_PROMOTIONS']]).f, sec(), SEED_GMAIL, TOKEN, SENDER);
  const gd = (g.detail.messages as { diagnosis: Record<string, unknown> }[])[0].diagnosis;
  assertEquals([g.folder, gd.labels, gd.spf, gd.dkim, gd.dmarc], ['spam', ['SPAM', 'CATEGORY_PROMOTIONS'], 'softfail', 'pass', 'fail']);
  const o = await readOutlook(graph([{ subject: subj, parent: 'F-junkemail' }]).f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER);
  const od = (o.detail.messages as { diagnosis: Record<string, unknown> }[])[0].diagnosis;
  assertEquals([o.folder, od.scl, od.sfv, od.cat, od.spf, od.dkim, od.dmarc, od.compauth], ['spam', 5, 'SPM', 'SPM', 'pass', 'pass', 'pass', 'pass']);
});

Deno.test('a failed header read keeps the folder and records why', async () => {
  const base = graph([{ subject: subj, parent: 'F-junkemail' }]);
  const f = async (u: string, init?: RequestInit) => u.includes('internetMessageHeaders') ? new Response('nope', { status: 403 }) : base.f(u, init);
  const o = await readOutlook(f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER);
  assertEquals(o.folder, 'spam');
  assert(String((o.detail.messages as { diagnosis: { error?: string } }[])[0].diagnosis.error).includes('403'));
});

Deno.test('header parsers: forefront and Authentication-Results', () => {
  assertEquals(forefront('CIP:1.1.1.1;SCL:-1;SFV:NSPM;CAT:NONE;'), { scl: -1, sfv: 'NSPM', cat: 'NONE', ptr: null, ipv: null });
  assertEquals(forefront(null), { scl: null, sfv: null, cat: null, ptr: null, ipv: null });
  assertEquals(authVerdicts('spf=none; dkim=fail; dmarc=temperror'), { spf: 'none', dkim: 'fail', dmarc: 'temperror', compauth: null, compauth_reason: null });
});

Deno.test('Outlook reads app-only with the M365 app send_outbox sends with: MS_* edge secrets, client_credentials, /users/<seed>', async () => {
  const bodies: string[] = [];
  const base = graph([{ subject: subj, parent: 'F-inbox' }]);
  const f = async (u: string, init?: RequestInit) => { if (u.startsWith('https://login.microsoftonline.com/T/')) bodies.push(String(init?.body)); return base.f(u, init); };
  const r = await readOutlook(f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER, undefined, (k) => ({ MS_TENANT_ID: 'T', MS_CLIENT_ID: 'C', MS_CLIENT_SECRET: 'S' } as Record<string, string>)[k]);
  assertEquals(r.folder, 'inbox');
  assertEquals(bodies.length, 1, 'the token was not asked of the MS_TENANT_ID tenant');
  assert(bodies[0].includes('grant_type=client_credentials') && bodies[0].includes('client_id=C') && !bodies[0].includes('refresh_token'));
  assert(!base.calls.some((u) => u.includes('/v1.0/me')), 'no delegated /me read is left');
  for (const gone of ['MS_TENANT_ID', 'MS_CLIENT_ID', 'MS_CLIENT_SECRET']) {
    const m = await readOutlook(graph([{ subject: subj, parent: 'F-inbox' }]).f, sec(), SEED_OUTLOOK, TOKEN, since(), SENDER, undefined,
      (k) => k === gone ? '' : 'x');
    assertEquals(m.folder, null, gone + ' missing must fail closed'); assert(String(m.detail.error).includes(gone));
  }
});

Deno.test('compauth reason and Forefront PTR/IPV are kept', () => {
  assertEquals(authVerdicts('dmarc=pass action=none;compauth=softpass reason=201').compauth_reason, '201');
  const f = forefront('CIP:1.2.3.4;CTRY:US;SCL:1;SFV:NSPM;IPV:NLI;PTR:a.amazonses.com;CAT:NONE;');
  assertEquals([f.scl, f.sfv, f.cat, f.ipv, f.ptr], [1, 'NSPM', 'NONE', 'NLI', 'a.amazonses.com']);
});
