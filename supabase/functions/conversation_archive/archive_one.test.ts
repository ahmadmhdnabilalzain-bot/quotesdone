// deno test supabase/functions/conversation_archive/archive_one.test.ts
// Review of #1797: a message too big to draw inside the CPU cap must still end archived, never pending for ever.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { archiveOne, type ArchiveDeps } from './archive_one.ts';
import { ATTEMPTS_BEFORE_COPY, conversationHtml, type ConversationRow } from './document.ts';

const big: ConversationRow = {
  source_table: 'notifications', source_id: 'zz-demo-1', channel: 'email', direction: 'in', occurred_at: '2026-11-02T05:00:00Z',
  from_addr: 'zz.demo@example.invalid', to_addr: 'supplier@quotesdone.com', cc: null, subject: 'ZZ DEMO a very long thread <b>',
  body: 'ZZ DEMO line & more\n'.repeat(20000), html: null, attachments: [{ filename: 'zz-demo.pdf' }],
  party_kind: null, party_id: null, inquiry_id: null,
};

function store() {
  const counter = new Map<string, number>(); const kept = new Map<string, { bytes: Uint8Array; type: string }>();
  const archived: string[] = []; const findings: string[] = [];
  const deps: ArchiveDeps = {
    attempt: (r) => { const k = r.source_table + ':' + r.source_id; const n = (counter.get(k) || 0) + 1; counter.set(k, n); return Promise.resolve(n); },
    // the renderer that the CPU cap kills: the worker dies, nothing comes back
    render: () => Promise.reject(new Error('CPU Time exceeded')),
    upload: (p, b, t) => { kept.set(p, { bytes: b, type: t }); return Promise.resolve(null); },
    record: (_r, p) => { archived.push(p); return Promise.resolve({ ok: true, queued: 1 }); },
    clear: (r) => { counter.delete(r.source_table + ':' + r.source_id); return Promise.resolve(); },
    finding: (_r, n, p) => { findings.push(n + ' ' + p); return Promise.resolve(); },
  };
  return { deps, counter, kept, archived, findings };
}

Deno.test('KNOWN-BAD control: a message the renderer cannot draw ends archived as its HTML copy within the attempt limit', async () => {
  const s = store();
  let attempts = 0, done = false;
  for (; attempts < ATTEMPTS_BEFORE_COPY + 1 && !done; attempts++) {
    const r = await archiveOne(big, s.deps).catch(() => null);   // a killed worker answers nothing
    done = !!r && r.ok;
  }
  assert(done, 'still pending after ' + attempts + ' attempts');
  assertEquals(attempts, ATTEMPTS_BEFORE_COPY + 1);
  assertEquals(s.archived, ['conversations/email/2026-11/notifications-zz-demo-1.html']);
  const copy = new TextDecoder().decode(s.kept.get(s.archived[0])!.bytes);
  assertMatch(s.kept.get(s.archived[0])!.type, /^text\/html/);
  assert(copy.includes('ZZ DEMO line &amp; more'), 'the whole text is in the copy');
  assertEquals((copy.match(/ZZ DEMO line &amp; more/g) || []).length, 20000);
  assert(copy.includes('zz-demo.pdf') && copy.includes('zz.demo@example.invalid'), 'the fields and the attachment list are kept');
  assert(!copy.includes('<b>'), 'the subject is escaped');
  assertEquals(s.findings.length, 1, 'an it_engineer finding names it');
  assertEquals(s.counter.size, 0, 'the counter row is cleared once it is kept');
});

Deno.test('a message that draws is kept as its PDF and no finding is filed', async () => {
  const s = store();
  s.deps.render = () => Promise.resolve({ ok: true, bytes: new Uint8Array([37, 80, 68, 70]) });
  const r = await archiveOne(big, s.deps);
  assert(r.ok && !r.light);
  assertEquals(s.archived, ['conversations/email/2026-11/notifications-zz-demo-1.pdf']);
  assertEquals(s.findings.length, 0);
});

Deno.test('a counter that cannot be read draws the PDF, as before the counter existed', async () => {
  const s = store();
  s.deps.attempt = () => Promise.reject(new Error('relation does not exist'));
  s.deps.render = () => Promise.resolve({ ok: true, bytes: new Uint8Array([1]) });
  const r = await archiveOne(big, s.deps);
  assert(r.ok && !r.light);
});

Deno.test('the HTML copy is linear in the text: a 400 kB message is built in well under the CPU cap', () => {
  const t = performance.now(); const html = conversationHtml(big); const ms = performance.now() - t;
  assert(html.length > 400_000);
  assert(ms < 500, ms + ' ms');
});

Deno.test('the sweep archives every message through archiveOne', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assertMatch(src, /const res = await archiveOne\(r, \{/);
  assertMatch(src, /rpc\('fn_conversation_archive_attempt'/);
});
