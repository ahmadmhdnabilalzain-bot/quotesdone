// widget_visitor_scope — the founder's ruling of 18 Oct 2026 on the homepage widget, graded against the DEPLOYED
// site_assistant with the model on. Seat: customer_support.
//   node scripts/eval/widget_visitor_scope.mjs        # exit 1 on any failure
// A visitor who is not signed up gets general answers only; a real inquiry is sent to sign up with no question
// about the job; past the message cap every reply is the sign-up direction. English and Arabic visitors.
// The cap's eight filler messages are ZZ DEMO traffic (never billed, prevented by
// our_own_test_traffic_never_reaches_a_paid_model); the graded general and inquiry answers are real model replies.
// Code half: supabase/functions/site_assistant/visitor_scope.test.ts.
const BASE = process.env.SUPABASE_URL || 'https://htdblwldjkcgjvmqkbeh.supabase.co';
const ANON = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZGJsd2xkamtjZ2p2bXFrYmVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU1NDYsImV4cCI6MjA5NjM2MTU0Nn0.cF9ZR_Qo1YBhLvhTLS8aANlYb6c9rTsuQS6kLxGw_Bo';
const AR = /[؀-ۿ]/;
const conv = (tag) => 'eval-' + tag + '-' + Math.random().toString(36).slice(2, 10);

async function ask(message, { lang, path = '/', c }) {
  const r = await fetch(BASE + '/functions/v1/site_assistant', { method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: ANON, Authorization: 'Bearer ' + ANON },
    body: JSON.stringify({ message, lang, path, conv: c, history: [{ role: 'user', content: message }] }) });
  return { status: r.status, ...(await r.json().catch(() => ({}))) };
}

const CASES = [
  { id: 'general-en', lang: 'en', path: '/', msg: 'How does QuotesDone work, and is it free for customers?', kind: 'general' },
  { id: 'general-ar', lang: 'ar', path: '/ar', msg: 'كيف تعمل QuotesDone وهل هي مجانية للعملاء؟', kind: 'general' },
  { id: 'inquiry-en', lang: 'en', path: '/', msg: 'I need a built-in wardrobe for my bedroom, about 3 metres wide, in white high-gloss. Can you get me quotes?', kind: 'inquiry', url: '/me' },
  { id: 'inquiry-ar', lang: 'ar', path: '/ar', msg: 'أحتاج تركيب أرضيات SPC لشقة مساحتها 120 متر مربع في دبي، هل يمكنكم مساعدتي؟', kind: 'inquiry', url: '/ar/me' },
];

const fails = [];
const check = (id, ok, why) => { if (!ok) fails.push(id + ': ' + why); };

for (const k of CASES) {
  const j = await ask(k.msg, { lang: k.lang, path: k.path, c: conv(k.id) });
  const reply = String(j.reply || '');
  console.log(`\n[${k.id}] ${j.status} routed=${j.routed} model=${j.model}\n${reply}\nsignup=${JSON.stringify(j.signup)}`);
  check(k.id, j.status === 200 && reply.length > 20 && j.routed === 'brief', 'no model reply');
  check(k.id, AR.test(reply) === (k.lang === 'ar'), 'reply is not in the visitor\'s language');
  check(k.id, j.signup && j.signup.url === (k.lang === 'ar' ? '/ar/me' : '/me'), 'no sign-up button');
  if (k.kind === 'inquiry') {
    check(k.id, reply.includes(k.url), 'the inquiry was not sent to sign up at ' + k.url);
    check(k.id, !/[?؟]/.test(reply), 'the reply asks the visitor a question (an inquiry is never collected here)');
  }
}

// THE CAP: eight messages in one conversation pass, the ninth is sign-up only with no model.
for (const lang of ['en', 'ar']) {
  const c = conv('cap-' + lang);
  for (let i = 1; i <= 8; i++) {
    const j = await ask('ZZ DEMO cap filler ' + i, { lang, path: lang === 'ar' ? '/ar' : '/', c });
    check('cap-' + lang, !j.visitor_cap, 'capped early at message ' + i);
  }
  const msg = lang === 'ar' ? 'ما هي رسوم الكشف؟' : 'What is the reveal fee?';
  const j = await ask(msg, { lang, path: lang === 'ar' ? '/ar' : '/', c });
  const url = lang === 'ar' ? '/ar/me' : '/me';
  console.log(`\n[cap-${lang}] message 9: routed=${j.routed} visitor_cap=${j.visitor_cap}\n${j.reply}`);
  check('cap-' + lang, j.visitor_cap === true && j.routed === 'visitor_cap' && !j.model, 'the 9th message was not capped');
  check('cap-' + lang, String(j.reply || '').trim().endsWith(url) && j.signup?.url === url, 'the capped reply is not sign-up only');
  check('cap-' + lang, AR.test(String(j.reply)) === (lang === 'ar'), 'capped reply in the wrong language');
}

console.log(fails.length ? '\nFAIL\n' + fails.join('\n') : '\nPASS: general answered, inquiries sent to sign-up with no question, cap is sign-up only (EN + AR)');
process.exit(fails.length ? 1 : 0);
