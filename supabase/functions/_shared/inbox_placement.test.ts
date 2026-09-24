// The folder classification, the exact allowlist and the fail-closed reader of inbox_placement.ts.
//   deno test supabase/functions/_shared/inbox_placement.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { gmailFolder, graphFolder, placementTick, readGmail, readOutlook, SEED_GMAIL, SEED_OUTLOOK, seedAllowed, worstFolder } from './inbox_placement.ts';

const TOKEN = 'QD0123456789';
const creds: Record<string, string> = {
  google_oauth_client_id: 'gid', google_oauth_client_secret: 'gsec', gmail_seed_refresh_token: 'grt',
  ms_graph_tenant_id: 'tid', ms_graph_client_id: 'mid', ms_graph_client_secret: 'msec',
};
const sec = (over: Record<string, string> = {}) => async (k: string) => ({ ...creds, ...over })[k] ?? '';
const ok = (o: unknown) => new Response(JSON.stringify(o), { status: 200 });

// A fake Gmail: the profile says `who`, and the token matches messages with these label sets.
function gmail(labelSets: string[][], who = SEED_GMAIL) {
  const calls: string[] = [];
  const f = async (u: string) => {
    calls.push(u);
    if (u.startsWith('https://oauth2.googleapis.com/token')) return ok({ access_token: 'at' });
    if (u.endsWith('/profile')) return ok({ emailAddress: who });
    if (u.includes('/messages?')) {
      assert(u.includes('includeSpamTrash=true'), 'the search must include spam and trash');
      assert(decodeURIComponent(u).includes('subject:' + TOKEN), 'the search must match the run token');
      return ok({ messages: labelSets.map((_, i) => ({ id: 'm' + i })) });
    }
    const i = Number(u.match(/messages\/m(\d+)/)?.[1]);
    return ok({ id: 'm' + i, labelIds: labelSets[i] });
  };
  return { f, calls };
}

// A fake Graph: well-known folder ids, and the messages (subject + parentFolderId) it holds.
function graph(msgs: { subject: string; parent: string }[], opts: { junkOnlyInJunkList?: boolean; me?: string } = {}) {
  const calls: string[] = [];
  const f = async (u: string, init?: RequestInit) => {
    calls.push(u);
    if (u.startsWith('https://login.microsoftonline.com/')) {
      const b = String(init?.body);
      return ok({ access_token: 'at', ...(b.includes('refresh_token') ? { refresh_token: 'rotated' } : {}) });
    }
    if (/\/me\?\$select=mail/.test(u)) return ok({ mail: opts.me ?? SEED_OUTLOOK });
    const wk = u.match(/mailFolders\/(inbox|junkemail|deleteditems)\?\$select=id/);
    if (wk) return ok({ id: 'F-' + wk[1] });
    const inJunkList = u.includes('/mailFolders/junkemail/messages');
    const value = msgs.filter((m) => !opts.junkOnlyInJunkList || (m.parent === 'F-junkemail') === inJunkList)
      .map((m, i) => ({ id: 'g' + i, subject: m.subject, parentFolderId: m.parent }));
    return ok({ value });
  };
  return { f, calls };
}

Deno.test('Gmail labels: INBOX is inbox (a category tab still counts), SPAM and TRASH win, anything else is other', () => {
  assertEquals(gmailFolder(['INBOX', 'UNREAD']), 'inbox');
  assertEquals(gmailFolder(['INBOX', 'CATEGORY_PROMOTIONS']), 'inbox');
  assertEquals(gmailFolder(['SPAM', 'UNREAD']), 'spam');
  assertEquals(gmailFolder(['TRASH']), 'trash');
  assertEquals(gmailFolder(['CATEGORY_UPDATES']), 'other');
  assertEquals(gmailFolder(undefined), 'other');
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

Deno.test('several copies: the worst decides; none: not_found', () => {
  assertEquals(worstFolder(['inbox', 'spam']), 'spam');
  assertEquals(worstFolder(['inbox', 'inbox']), 'inbox');
  assertEquals(worstFolder([]), 'not_found');
});

Deno.test('the allowlist is two exact addresses, each tied to its provider', () => {
  assert(seedAllowed(SEED_GMAIL, 'gmail') && seedAllowed(' Management@DorataJewelries.com ', 'outlook'));
  for (const bad of ['ahmadmhdnabilalzain+x@gmail.com', 'management@quotesdone.com', 'test-abc@srv1.mail-tester.com',
    'management@doratajewelries.com.evil.example', 'x@doratajewelries.com', '', null, 'someone@gmail.com']) {
    assert(!seedAllowed(bad), `accepted ${bad}`);
  }
  assert(!seedAllowed(SEED_OUTLOOK, 'gmail') && !seedAllowed(SEED_GMAIL, 'outlook'), 'an address was accepted for the other provider');
});

Deno.test('a refused address is refused before any network call', async () => {
  let called = 0;
  const f = async () => { called++; return ok({}); };
  const g = await readGmail(f, sec(), 'someone@gmail.com', TOKEN);
  const o = await readOutlook(f, sec(), 'management@quotesdone.com', TOKEN, new Date().toISOString());
  assertEquals([g.folder, o.folder], [null, null]);
  assert(String(g.detail.error).startsWith('refused') && String(o.detail.error).startsWith('refused'));
  assertEquals(called, 0);
});

Deno.test('Gmail: inbox, spam, not found', async () => {
  assertEquals((await readGmail(gmail([['INBOX']]).f, sec(), SEED_GMAIL, TOKEN)).folder, 'inbox');
  assertEquals((await readGmail(gmail([['SPAM']]).f, sec(), SEED_GMAIL, TOKEN)).folder, 'spam');
  assertEquals((await readGmail(gmail([]).f, sec(), SEED_GMAIL, TOKEN)).folder, 'not_found');
});

Deno.test('Gmail: a credential that opens another mailbox is refused, not read', async () => {
  const r = await readGmail(gmail([['INBOX']], 'someone.else@gmail.com').f, sec(), SEED_GMAIL, TOKEN);
  assertEquals(r.folder, null);
});

Deno.test('Outlook (application): inbox, junk found only in the Junk list, deleted, not found', async () => {
  const since = new Date().toISOString();
  const subj = 'Invitation (ref ' + TOKEN + ')';
  assertEquals((await readOutlook(graph([{ subject: subj, parent: 'F-inbox' }]).f, sec(), SEED_OUTLOOK, TOKEN, since)).folder, 'inbox');
  assertEquals((await readOutlook(graph([{ subject: subj, parent: 'F-junkemail' }], { junkOnlyInJunkList: true }).f, sec(), SEED_OUTLOOK, TOKEN, since)).folder, 'spam');
  assertEquals((await readOutlook(graph([{ subject: subj, parent: 'F-deleteditems' }]).f, sec(), SEED_OUTLOOK, TOKEN, since)).folder, 'trash');
  assertEquals((await readOutlook(graph([{ subject: 'another mail', parent: 'F-inbox' }]).f, sec(), SEED_OUTLOOK, TOKEN, since)).folder, 'not_found');
  const app = graph([]); await readOutlook(app.f, sec(), SEED_OUTLOOK, TOKEN, since);
  assert(app.calls.some((u) => u.includes('/users/' + encodeURIComponent(SEED_OUTLOOK) + '/')), 'application mode must name the one seed mailbox');
});

Deno.test('Outlook (delegated): the mailbox must be the seed, and a rotated refresh token is kept', async () => {
  const since = new Date().toISOString();
  const saved: string[] = [];
  const r = await readOutlook(graph([{ subject: 'x (ref ' + TOKEN + ')', parent: 'F-inbox' }]).f,
    sec({ ms_graph_seed_refresh_token: 'rt' }), SEED_OUTLOOK, TOKEN, since, async (_k, v) => saved.push(v));
  assertEquals(r.folder, 'inbox');
  assertEquals(saved, ['rotated']);
  const other = await readOutlook(graph([], { me: 'someone@doratajewelries.com' }).f, sec({ ms_graph_seed_refresh_token: 'rt' }), SEED_OUTLOOK, TOKEN, since);
  assertEquals(other.folder, null);
});

Deno.test('FAIL CLOSED: missing credentials, an HTTP error or a thrown fetch never read as inbox', async () => {
  const since = new Date().toISOString();
  const noG = await readGmail(gmail([['INBOX']]).f, sec({ gmail_seed_refresh_token: '' }), SEED_GMAIL, TOKEN);
  assertEquals(noG.folder, null); assert(String(noG.detail.error).includes('gmail_seed_refresh_token'));
  const noO = await readOutlook(graph([]).f, sec({ ms_graph_client_secret: '' }), SEED_OUTLOOK, TOKEN, since);
  assertEquals(noO.folder, null);
  const e401 = async () => new Response('{"error":"invalid_grant"}', { status: 400 });
  assertEquals((await readGmail(e401, sec(), SEED_GMAIL, TOKEN)).folder, null);
  assertEquals((await readOutlook(e401, sec(), SEED_OUTLOOK, TOKEN, since)).folder, null);
  const boom = () => Promise.reject(new Error('network down'));
  assertEquals((await readGmail(boom, sec(), SEED_GMAIL, TOKEN)).folder, null);
  assertEquals((await readOutlook(boom, sec(), SEED_OUTLOOK, TOKEN, since)).folder, null);
  assertEquals((await readGmail(gmail([['INBOX']]).f, sec(), SEED_GMAIL, 'not-a-token')).folder, null);
});

Deno.test('the tick reads only a sent seed, and records a failed reading as null (the database holds the batch)', async () => {
  const rpcs: [string, Record<string, unknown> | undefined][] = [];
  const due = { action: 'read', dubai_day: '2026-09-28', token: TOKEN, since: new Date().toISOString(),
    gmail: { to: SEED_GMAIL, sent: true, folder: null }, outlook: { to: SEED_OUTLOOK, sent: false, folder: null } };
  const rpc = async (fn: string, args?: Record<string, unknown>) => {
    rpcs.push([fn, args]);
    return { data: fn === 'fn_invite_placement_due' ? due : { recorded: true, verdict: 'pending' }, error: null };
  };
  const boom = () => Promise.reject(new Error('down'));
  const out = await placementTick(rpc, boom, sec());
  assertEquals(out.ok, true);
  const rec = rpcs.find(([fn]) => fn === 'fn_invite_placement_record')?.[1];
  assert(rec, 'nothing recorded');
  assertEquals((rec.p_gmail as { folder: unknown }).folder, null);
  assertEquals(rec.p_outlook, null, 'the unsent Outlook seed was read');
});

Deno.test('the tick does nothing but ask when the database says idle or queued', async () => {
  let fetched = 0;
  for (const action of ['idle', 'queued', 'settled']) {
    const out = await placementTick(async () => ({ data: { action }, error: null }), async () => { fetched++; return ok({}); }, sec());
    assertEquals(out.action, action);
  }
  assertEquals(fetched, 0);
  const err = await placementTick(async () => ({ data: null, error: { message: 'no such function' } }), async () => ok({}), sec());
  assertEquals(err.ok, false);
});
