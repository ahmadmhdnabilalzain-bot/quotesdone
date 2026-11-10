// founder.ts - THE FOUNDER'S COMMAND CHANNEL (v13): his registered number can change a setting by text, or ask a question the
// deterministic road answers. Moved out of index.ts's handleInbound unchanged (9 Nov 2026, customer_support). A Response means the
// number was his (the work continues under waitUntil); undefined means it was not and the turn goes on.
import { answerFromFaq, founderUnanswered } from './menu_flow.ts';
import { directiveSystemPrompt, readDirectiveReply } from './founder_directive.ts';
import { founderDirectiveAllowed } from './directive_gate.ts';
import { admin, GATEWAY, sec, TW } from './shared.ts';
import { bidiSafe, sendWa } from './replies.ts';
import type { WaTurn } from './turn.ts';

// ---- THE FOUNDER'S COMMAND CHANNEL, v13 ---------------------------------
// He asked to run the company by texting his registered number. Until now he could ASK it
// anything and it could OBEY nothing: this function made a bare model call with the leadership
// context pasted in, and the founder prompt itself admitted the limit - "if he asks you to DO
// something ... say what would have to be built. Do not claim to have done it."
//
// AGENT_BRAIN IS GONE, AND SO IS THE CALL (22 Sep 2026). Everything that was not a settings change
// went to agent_brain, which the 137-function sweep of 7 Sep deleted (config.toml has no entry; the
// URL answers 404). Measured on wa_messages 271: "What sectors you cover" came back to him as
// "I could not reach the company brain ... (agent_brain returned no reply (HTTP 404))". With the
// model held there is no live equivalent to forward to, so an unmatched message now takes the same
// deterministic road as everyone's: the live trade list for a coverage question, the approved FAQ
// (gte-small + lexical corroboration, the corpus the site assistant answers from), and otherwise the
// courteous fallback with the menu, the question filed for the team. No internal wording is sent.
// scripts/checks/no_function_calls_an_undeployed_function.test.mjs fails if a call like it returns.
//
// STILL BACKGROUNDED: the settings classifier below is a gateway call with a 45-second ceiling and
// Twilio's webhook wall is 15, so the webhook is acknowledged first and the answer sent when ready.
export async function founderTurn(t: WaTurn): Promise<Response | undefined> {
  const { From, Body, Profile, MessageSid, audience, known, signatureVerified, receivedAt, logRun, waInsert, sayFor, heldTurn, menuDeps, menuIn } = t;
  if (audience === 'founder') {
    const question = Body.slice(0, 1500);
    // HIS LANGUAGE IS THE LANGUAGE HE WROTE IN (gap #10): the model's reply, the held notice and its replay, and the row.
    const founderLang: 'en' | 'ar' = /[\u0600-\u06FF]/.test(question) ? 'ar' : 'en';

    const work = (async () => {
      let reply = ''; let directive: any = null;

      // ---- IS THIS AN INSTRUCTION OR A QUESTION? (v14, 13 Aug 2026) -------------------------
      // He asked for both: "send me the financial report for last week" must ANSWER, and "change
      // the weekly cap for emails into 15 instead of 10" must CHANGE something. Until now both
      // went to agent_brain (deleted 7 Sep 2026), which could queue an agent_action - and a queued
      // action is not a change.
      //
      // The model NEVER writes SQL and never names a table. It maps his sentence onto a key in
      // fn_founder_settings(), which is the same registry fn_founder_apply_setting validates
      // against, so the two cannot disagree. Anything it cannot map - or is unsure about - falls
      // through to the deterministic answer below rather than being guessed at. Money, refunds and the
      // three go-live switches are not in the registry and are refused BY NAME, with the list of
      // what can be changed, so a refusal teaches instead of stonewalling.
      // Only a signature-verified webhook from his number may CHANGE a setting (directive_gate.ts, 3 Nov 2026). Any
      // other turn is still read, so an instruction that is not applied is told so, never answered as a question.
      try {
        const { data: settings } = await admin.rpc('fn_founder_settings');
        const rows: any[] = Array.isArray(settings) ? settings : [];
        if (rows.length) {
          const catalogue = rows.map((s: any) =>
            `${s.setting_key} (${s.kind}${s.min_val !== null && s.min_val !== undefined ? `, ${s.min_val}..${s.max_val}` : ''}) = ${s.current_value} — ${s.description}`).join('\n');
          // The prompt and the read live in founder_directive.ts: a change outside the registry is still a directive, refused BY
          // NAME and audited by fn_founder_apply_setting, never answered as a question (gap #10, 3 Nov 2026).
          const sys = directiveSystemPrompt(catalogue);
          const gsecret = await sec('cred_fn_ai');
          const cr = await fetch(GATEWAY, {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            // cache_ttl_min: 0 IS LOAD-BEARING, MEASURED 13 Aug 2026. ai_gateway's cache does an
            // exact-hash lookup AND a SEMANTIC one at 0.95 similarity, over
            // (sys_stable + sys).slice(0,400) + convo.slice(0,800). This call's system prompt is
            // the 719-token settings catalogue and the user half is one short sentence, so every
            // message embeds almost identically. Tested on staging without this: "turn on stripe
            // live payments" and "send me the financial report for last week" both came back
            // classified as the PREVIOUS message's directive — ai_cost_log recorded cached:true,
            // 0 prompt tokens, for both. A classifier is the definition of an unrepeatable
            // request, and the gateway explicitly leaves the caller this override for exactly
            // that. Any classifier whose system prompt dwarfs its input needs this line.
            body: JSON.stringify({ __secret: gsecret, fn: 'founder_directive', sys, input: question, temperature: 0, task_class: 'json_extraction', cache_ttl_min: 0 }),
            signal: AbortSignal.timeout(45000),
          });
          const cj = readDirectiveReply(await cr.json().catch(() => ({} as any)));
          const m = String(cj?.content || '').match(/\{[\s\S]*\}/);
          const parsed = m ? JSON.parse(m[0]) : null;
          if (parsed?.directive === true && parsed?.key && !founderDirectiveAllowed({ audience, signatureVerified })) {
            directive = { ok: false, key: String(parsed.key), refusal: 'not applied: this message did not arrive with a verified Twilio signature, so it cannot change a setting' };
            reply = (await sayFor('founder')('He asked to change the setting ' + String(parsed.key) + ' to ' + String(parsed.value ?? '') + '. It was NOT changed: this message did not arrive with a verified Twilio signature, and only a verified message from his number may change a setting. Nothing else was done; he can send it again.')) || ' ';
          } else if (parsed?.directive === true && parsed?.key) {
            const { data: applied } = await admin.rpc('fn_founder_apply_setting', {
              p_key: String(parsed.key), p_value: String(parsed.value ?? ''),
              p_inbound: question, p_actor: String(known?.name || 'founder'), p_channel: 'whatsapp',
            });
            directive = applied || null;
            // The routine decided; the model says it (1195-1197). The routine's own sentence is a fact, not the reply.
            // What happened is stated to the model in plain words first, so a refusal is reported as NOT applied (gap #10).
            const outcome = applied?.ok === true && !applied?.unchanged ? 'The setting WAS changed on his instruction.'
              : applied?.ok === true ? 'Nothing was changed: the setting already had the value he asked for.'
              : 'The setting was NOT changed: the routine refused it. Say plainly that it was not applied, and why.';
            if (applied) reply = (await sayFor('founder')(outcome + ' The settings routine result, to report accurately (applied or refused, old and new value, the reason):\n' + JSON.stringify(applied), founderLang)) || ' ';
          }
        }
      } catch (e) {
        // A classifier failure must never swallow his message: fall through and answer it.
        directive = { classifier_error: String((e as Error)?.message || e) };
      }

      if (reply) {
        // A directive was applied or refused. ' ' = the routine ran but no model could word it: nothing is sent, the row says so.
        reply = reply.trim() ? bidiSafe(reply.slice(0, 1200)) : '';
        const enabledD = (await sec('wa_autoreply_enabled')) === 'true';
        let sentD = false; let sendErrD: string | undefined = reply ? undefined : 'no_model_reply';
        if (enabledD && reply) { const r = await sendWa(From, reply); sentD = r.ok; sendErrD = r.err; }
        if (!reply) { const h = await heldTurn('founder', founderLang, 'The settings routine result: ' + JSON.stringify(directive), 'founder_directive'); reply = h.notice; sentD = h.sent; sendErrD = h.err ?? undefined; }
        try {
          await waInsert(receivedAt, {
            wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile,
            inbound: question, reply, lang: founderLang, escalated: false, sent: sentD,
            meta: { enabled: enabledD, audience: 'founder', route: 'founder_directive',
                    directive, send_error: sendErrD || null, provenance_verified: true,
                    message_sid: MessageSid || null },
          });
        } catch (_e) { /* the reply already went out */ }
        await logRun(directive?.ok === false ? 'error' : 'ok',
          { audience: 'founder', route: 'founder_directive', applied: directive?.ok === true,
            key: directive?.key || null, sent: sentD },
          directive?.ok === true
            ? ('founder changed ' + directive.key + ' from ' + directive.old + ' to ' + directive.new + ' by WhatsApp')
            : ('founder directive REFUSED: ' + String(directive?.refusal || '').slice(0, 200)));
        return;
      }

      // No settings change: the deterministic road. The live trade list and the approved FAQ; anything
      // else gets the honest list of what can be answered without the model and is filed for the team.
      // His internal figures are NOT here (instruction 777): menuTurn sends them on the FIGURES command
      // only, and answers a natural size question with the capability statement, before this branch.
      if (await answerFromFaq(menuDeps, menuIn)) {
        await logRun('ok', { audience: 'founder', route: 'faq_answer', deferred: 1, cost_aed: 0 }, 'founder question answered from the trade list or the approved FAQ');
        return;
      }
      await founderUnanswered(menuDeps, menuIn, directive?.classifier_error ? 'settings_classifier_failed' : 'no_grounded_answer');
      await logRun('ok', { audience: 'founder', route: 'menu_reoffer', deferred: 1, cost_aed: 0 },
        'founder message had no settings change and no grounded answer; the answerable list and the reading were sent, the question filed');
    })();

    // waitUntil keeps the isolate alive after the response. Fall back to awaiting inline where it
    // is unavailable (local deno run) rather than dropping his message on the floor.
    const er = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime;
    if (er?.waitUntil) er.waitUntil(work); else await work;

    return TW(200);
  }
}
