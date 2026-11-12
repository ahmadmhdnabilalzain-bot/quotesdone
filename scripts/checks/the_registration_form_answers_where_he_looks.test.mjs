// THE REGISTRATION FORM ANSWERS WHERE HE LOOKS, AND EVERY PRESS SHOWS IT IS WORKING (12 Nov 2026, customer_support; browser
// perfection walk of supplier registration, findings B1, H1-H4, M16, M17, M19-M22; founder ruling 1645: "if you notice a text box
// that is small or hidden, not showing, typing takes time, some buttons are not clickable, there is no loading animation when you
// are submitting something. I'm looking for perfection").
//
// Measured on production at 390x844 on main b2bf64c82: every mid-form error was one line under Submit, 459-1,046 px from the
// control pressed; 0 running animations during every submit (1.1-10.1 s); every text box 15 px and 40 px tall (Safari zooms the
// page into a box under 16 px); the agreement line in four columns beside a 13x13 box; Tab never reached the three "Attach file"
// controls; the licence went as base64 three times. The walk itself is the proof on a screen; this holds the source to it so a
// later edit cannot quietly undo one. Each assertion names the finding. Fails on main 0b612866e.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const FORM = R('src/components/portal/supplier/core/ProfileForm.tsx');
const LOGIN = R('src/components/portal/supplier/core/Login.tsx');
const ONB = R('src/components/portal/supplier/core/Onboarding.tsx');
const HELP = R('src/components/portal/supplier/core/helpers.tsx');
const STY = R('src/components/portal/supplier/core/styles.ts');
const INPUT = R('src/components/ui/input.tsx');
const WA = R('src/components/portal/WhatsAppChoice.tsx');
const UP = R('src/components/portal/supplier/core/upload.ts');
const buttons = (src) => [...src.matchAll(/<Button\b[^>]*onClick=\{([^}]*(?:\}[^>]*?)?)\}[^>]*>/g)].map((m) => m[0]);

test('B1: the licence goes once, straight to storage, small, and process_docs is given its path', () => {
  const up = FORM.slice(FORM.indexOf('const upLicense'), FORM.indexOf('const save = async'));
  assert.doesNotMatch(up, /original_b64|file_b64|fileToImages/, 'the licence is never sent as base64 again');
  assert.match(up, /file = await preparePhoto\(file\)/, 'a photo is made small before it leaves');
  assert.match(up, /uploadDirect\('licence', file, tok\.current, progress, ac\.signal\)/);
  assert.match(up, /action: 'process_docs', license: \{ path: d\.path, filename: d\.filename, mime: d\.mime, issued: d\.issued \}/);
  assert.match(up, /licenceFileProblem\(file\)/, 'a wrong type or an empty file is refused in the browser (M1, M2)');
  assert.match(up, /setLicRetry\(picked\)/, 'a failure keeps his file chosen, so trying again is one tap');
  assert.match(UP, /onProgress\?: \(done: number\) => void/);
});

test('H1: each step answers under its own control; Submit\'s answer is scrolled to and focused', () => {
  for (const [name, re] of [['licence', /role="alert" data-testid="licence-error"/], ['mobile', /role="alert" data-testid="mobile-error"/], ['e-mail', /role="alert" className=\{cn\(fieldLine[^}]*\)\}>\{mailErr\}/], ['profile', /role="alert" data-testid="profile-error"/]]) assert.match(FORM, re, name + ' has its own alert');
  for (const fn of ['sendSms', 'verifySms', 'sendMail', 'verifyMail']) {
    const body = FORM.slice(FORM.indexOf(`const ${fn} = async`), FORM.indexOf('\n', FORM.indexOf(`const ${fn} = async`) + 400));
    assert.doesNotMatch(body.split('\n')[0], /setMsg\(/, `${fn} writes to the bottom line again`);
  }
  assert.match(FORM, /ref=\{submitMsg\} tabIndex=\{-1\} role="alert"/);
  assert.match(FORM, /el\.scrollIntoView\(\{ block: 'center'[^)]*\}\); el\.focus\(\{ preventScroll: true \}\)/);
  assert.match(LOGIN, /\{msg && <div role="alert" className=\{S\.err\}>\{msg\}<\/div>\}/, 'L5: sign-in errors are announced');
});

test('M4: a refusal goes when he changes what it was about', () => {
  assert.match(FORM, /const stillMissing = missing\.filter\(/, 'Submit names only what is still missing');
  // re-pinned 12 Nov 2026 (ruling 1672): in registration the agreement is the server's acceptance, recorded at its own step
  assert.match(FORM, /\(c === 'reg_terms' && \(isEdit \? terms : accepted\)\)/);
  assert.match(FORM, /onChange=\{\(e\) => \{ set\('phone', e\.target\.value\); setMobileErr\(''\); \}\}/);
  // re-pinned 12 Nov 2026 (ruling 1672): the name box is gone; the start of the registration says what went wrong where he looks
  assert.match(ONB, /role="alert" data-testid="registration-open-error"/);
});

test('H2: every submit on the registration screens turns a ring while it works and cannot be pressed twice', () => {
  const need = [
    [LOGIN, /busy=\{busy === 'send'\}[^>]*onClick=\{\(\) => send\(\)\}/, 'Create my account / Send me a code'],
    [LOGIN, /busy=\{busy === 'verify'\}[^>]*onClick=\{verify\}/, 'Verify'],
    [LOGIN, /busy=\{busy === 'again'\}[^>]*onClick=\{\(\) => send\(true\)\}/, 'Send the code again'],
    [ONB, /busy=\{busy\} disabled=\{busy\} onClick=\{create\}/, 'Try again (opening the registration)'],
    [ONB, /data-testid="registration-opening"[^>]*><span aria-hidden="true" className="qd-spin" \/>/, 'Opening your registration'],
    [FORM, /busy=\{vbusy === 'wa'\}/, 'Get the code on WhatsApp'],
    [FORM, /busy=\{vbusy === 'sms'\}/, 'Get it by SMS'],
    [FORM, /busy=\{vbusy === 'verify_sms'\}[^>]*onClick=\{verifySms\}/, 'Verify mobile'],
    [FORM, /busy=\{vbusy === 'mail'\}[^>]*onClick=\{sendMail\}/, 'Verify my e-mail'],
    [FORM, /busy=\{vbusy === 'verify_mail'\}[^>]*onClick=\{verifyMail\}/, 'Verify e-mail'],
    [FORM, /busy=\{uploading\}[^>]*testId="pick-licence"/, 'Attach licence'],
    [FORM, /busy=\{busy\} disabled=\{busy \|\| uploading \|\| !kycRead\} onClick=\{save\}/, 'Submit for approval / Save changes'],
    [WA, /busy=\{busy === 'choose'\}/, 'WhatsApp answer'],
  ];
  for (const [src, re, what] of need) assert.match(src, re, what + ' shows it is working');
  assert.match(FORM, /data-testid="submit-stage"/, 'Submit says the step it is on');
  assert.match(FORM, /<UploadBar progress=\{licProgress\}/, 'the licence upload shows its progress');
  assert.match(FORM, /<UploadBar progress=\{stageProgress\}/, 'the profile and catalogue uploads show their progress');
  for (const b of buttons(FORM).concat(buttons(LOGIN))) if (/onClick=\{(save|verify|verifySms|verifyMail|sendMail)\}/.test(b)) assert.match(b, /busy=/, b);
});

test('H3, M19, M20: every box is 16 px and 44 px tall to a finger; explanations 14-15 px', () => {
  assert.match(INPUT, /pointer-coarse:min-h-11 pointer-coarse:text-\[16px\]/);
  assert.match(STY, /field: '[^']*pointer-coarse:text-\[16px\]/);
  assert.match(STY, /area: '[^']*pointer-coarse:text-\[16px\]/);
  assert.match(STY, /sub: '[^']*pointer-coarse:text-\[15px\]/);
  assert.match(STY, /hint: '[^']*pointer-coarse:text-\[14px\]/);
  assert.match(STY, /err: '[^']*pointer-coarse:text-\[15px\]/);
  assert.match(R('src/components/CookieConsent.tsx'), /const btn = 'inline-flex h-10 pointer-coarse:min-h-11/);
});

test('H4, M22: the agreement is one sentence beside a 20 px box, and opens over the form', () => {
  const label = FORM.slice(FORM.indexOf('data-testid="accept-terms"') - 200, FORM.indexOf('</label>', FORM.indexOf('data-testid="accept-terms"')));
  assert.match(label, /<label className="[^"]*min-h-11[^"]*items-start/);
  assert.match(label, /<input type="checkbox" className="[^"]*h-5 w-5 shrink-0/);
  assert.match(label, /<span>\{t\(lang, 'accept_pre'\)\}<a [\s\S]*?>\{t\(lang, 'terms_link'\)\}<\/a>\{t\(lang, 'accept_post'\)\}/, 'one sentence, the link inside it');
  assert.match(label, /e\.preventDefault\(\); e\.stopPropagation\(\); setAgreementOpen\(true\);/);
  assert.match(FORM, /<AgreementSheet open=\{agreementOpen\}/);
  assert.match(R('src/components/portal/supplier/core/AgreementSheet.tsx'), /Back to registration/);
});

test('M16, M17, M8, M21: the file pickers take the keyboard, every box keeps a visible name, read fields are text, required first', () => {
  assert.match(HELP, /<input type="file"[^>]*className="sr-only"/);
  assert.match(HELP, /focus-within:ring-2/);
  assert.doesNotMatch(HELP, /<input type="file"[^>]*className="hidden"/);
  for (const k of ['email_code', 'sms_code', 'products_ph', 'services_ph', 'desc_ph', 'signatory']) assert.match(FORM, new RegExp(`<Lbl [^>]*visible[^>]*text=\\{t\\(lang, '${k}'\\)\\}`), k);
  assert.doesNotMatch(FORM, /<Input[^>]*readOnly aria-readonly="true" tabIndex=\{-1\}/, 'no box that looks typeable and is not');
  assert.ok(FORM.indexOf("t(lang, 'h_trade')") < FORM.indexOf('<div className="mt-4"><EmirateCheckboxes'), 'the optional emirates come after the licence');
});

test('M18, L12, M10: the sign-up address box is an e-mail box; the code step says how long and from where', () => {
  assert.match(LOGIN, /type=\{isSignup \? 'email' : 'text'\}/);
  assert.match(LOGIN, /autoCapitalize="none"/);
  assert.match(LOGIN, /\{t\(lang, 'code_life'\)\}/);
  const copy = R('src/components/portal/supplier/core/copy.ts');
  assert.match(copy, /code_life:'The code works for 10 minutes\./, 'login_otp issues it for 600 s');
  assert.match(copy, /contact_note:'So our messages reach your inbox, add info@quotesdone\.com/, 'login_otp sends from email_from_info (measured 12 Nov: info@quotesdone.com)');
  assert.doesNotMatch(copy, /supplier@quotesdone\.com to your contacts/);
});

// ── The review of this change (12 Nov 2026, it_engineer): each finding held here ──────────────────────────────────────────────
test('review 1: inside the portal (.osx) the ring keeps a transparent side, after the rule that recolours every border', () => {
  const css = R('src/app/globals.css');
  const all = css.indexOf('.osx *{border-color');
  const ring = css.indexOf('.osx .qd-spin{border-color:currentColor;border-inline-end-color:transparent}');
  assert.ok(all > 0 && ring > all, '.osx .qd-spin must follow .osx * (same layer, higher specificity), or all four sides are one colour');
  assert.match(css, /\.qd-spin \{[^}]*border-inline-end-color: transparent;/);
});

test('review 2: the WhatsApp question closes at the press of Continue and holds no height', () => {
  assert.doesNotMatch(FORM, /minHeight|waHold/, 'no held height: its collapse sent his next tap onto the emirates');
  assert.match(FORM, /onChoose=\{closeWa\} onChooseFailed=\{\(\) => setWaAnswer\(''\)\}/);
  // round 2, finding 2: a second tap right after the close is swallowed before it reaches the control that moved under it
  assert.match(FORM, /const closeWa = \(\) => \{ tapGuard\.current = Date\.now\(\) \+ TAP_GUARD_MS; setWaAnswer\('saving'\); \};/);
  assert.match(FORM, /<Card className="qd-panel p-5" onClickCapture=\{swallow\} onTouchEndCapture=\{swallow\} onMouseDownCapture=\{swallow\}>/);
  // round 3, D: the different-number Verify keeps the question in place until the answer lands; a wrong code is said by the box
  assert.match(WA, /setBusy\('verify'\); setErr\(''\);\n    const j = await kyc\(\{ action: 'whatsapp_verify'/);
  assert.match(WA, /onClick=\{verify\}>[^\n]*<\/Button>\n          <\/div>\n          \{err && <div role="alert" data-testid="wa-code-error"/);
  assert.match(FORM, /<div className=\{cn\('mt-3', waAnswer && 'hidden'\)\}>/, 'hidden (still mounted) from the press until it is gone');
  assert.match(WA, /setBusy\('choose'\); setErr\(''\); onChoose\?\.\(opt\);/);
});

test('review 4, 10: sign-out clears the drafts; the shell can ask Login for Register at any time', () => {
  assert.match(R('src/components/portal/SupplierPortal.tsx'), /const doSignOut = \(\) => \{ try \{ clearRegistrationDrafts\(window\.sessionStorage\); \} catch \(_e\) \{\}/);
  assert.match(LOGIN, /function Login\(\{ onAuth, lang, startMode, modeRequest = 0 \}\)/);
  assert.match(LOGIN, /useEffect\(\(\) => \{ if \(!modeRequest\) return; setMode\('signup'\);/);
});

test('review 7: each answer sits directly under its own control', () => {
  const at = (s, a) => s.indexOf(a);
  assert.ok(at(FORM, 'testId="pick-profile"') < at(FORM, 'data-testid="profile-error"') && at(FORM, 'data-testid="profile-error"') < at(FORM, 'testId="pick-catalogues"'), 'the profile error comes before the catalogue picker');
  assert.ok(at(LOGIN, 'data-testid="resend-code"') < at(LOGIN, 'data-testid="code-resent"') && at(LOGIN, 'data-testid="code-resent"') < at(LOGIN, "t(lang, 'use_diff')"), '"We sent a new code" directly under its link');
});

// ── Founder ruling 1672 (12 Nov 2026): the order he meets, and nothing typed that a document says ───────────────────────────────
test('ruling 1672: e-mail, mobile and WhatsApp, the agreement, then the licence and the profile; the company is the licence\'s', () => {
  const at = (needle) => { const i = FORM.indexOf(needle); assert.ok(i > 0, needle + ' is missing'); return i; };
  const contact = at("{t(lang, 'pf_contact')}"), terms = at('{!isEdit && termsBlock}'), licence = at("{t(lang, 'h_trade')}"), profile = at("{t(lang, 'doc_profile')}");
  assert.ok(contact < terms && terms < licence && licence < profile, 'the registration is not in the order e-mail, mobile, terms, documents');
  assert.match(FORM, /\{isEdit && termsBlock\}/, 'the Profile tab lost its agreement beside Save');
  assert.match(FORM, /<ReadField text=\{t\(lang, 'lic_company'\)\} value=\{f\.licence_legal_name\} \/>/, 'the licensed name is not shown back');
  assert.doesNotMatch(FORM, /<Input[^>]*value=\{f\.company_name\}/, 'a company-name box is in the form');
  assert.match(FORM, /data-testid="trading-name"/, 'the optional trading name is missing');
  assert.match(FORM, /need=\{isEdit \? null : 'opt'\}[^>]*text=\{t\(lang, 'trading_name'\)\}/, 'the trading name is not marked optional');
  assert.match(FORM, /payload\.trading_name = /, 'the trading name is not sent');
  assert.match(R('supabase/functions/supplier_api/lib/fields.ts'), /export const PROFILE_COLS = \[[^\]]*'trading_name'/, 'save_profile does not keep the trading name');
  assert.doesNotMatch(R('supabase/functions/supplier_api/lib/fields.ts'), /export const PROFILE_COLS = \[[^\]]*'company_name'/, 'the company name became typeable');
});

test('ruling 1672: the agreement is accepted at its own step, with the accepting person\'s full name, and the press shows it is working', () => {
  assert.match(FORM, /<Button className="mt-2 w-full min-h-11" data-testid="accept-agreement" busy=\{acceptBusy\} disabled=\{acceptBusy\} onClick=\{acceptAgreement\}>/);
  assert.match(FORM, /need="req" visible lang=\{lang\} text=\{t\(lang, 'full_name_label'\)\}><Input autoComplete="name"/);
  assert.match(FORM, /action: 'accept_terms', full_name: accepter/);
  assert.match(FORM, /role="alert" data-testid="accept-error"/, 'its refusal is said under it');
  assert.match(FORM, /if \(!\(isEdit \? terms : accepted\)\) missing\.push\('reg_terms'\);/, 'Submit goes on without the server\'s acceptance');
  assert.match(FORM, /useState\(!!me\.accepted_terms_at && me\.terms_stands !== false\)/, 'a reload does not land on the accepted step');
});
