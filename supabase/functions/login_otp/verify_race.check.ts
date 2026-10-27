// A SIGN-IN CODE IS COUNTED AND SPENT ONCE, EVEN UNDER A BURST (pre-launch security pass, 6 Oct 2026, H1).
//
// Runs the committed body of public.fn_login_otp_email_verify against a throwaway Postgres (CI starts
// one as a service; locally: QD_OTP_RACE_PG=postgres://... deno test ...). It never touches the
// production project. Twenty guesses go in at once on twenty connections, the shape an attacker uses
// to beat a read-then-write counter, and the check asserts:
//   * 20 wrong guesses at one code: exactly 5 are evaluated (`wrong`), the counter ends at 5, and a
//     right guess after that finds the code burned;
//   * 20 copies of the RIGHT code at once: exactly one `ok`, so one code mints one session;
//   * a resend retires the earlier code, and 20 sends at once leave exactly one live code.
// `p_max_attempts` is login_otp's EMAIL_VERIFY_MAX_ATTEMPTS (5).
import postgres from 'npm:postgres@3.4.5';

const PG_URL = Deno.env.get('QD_OTP_RACE_PG');
const FILE = new URL('../../../scripts/sql/a_sign_in_code_is_counted_compared_and_spent_in_one_statement.sql', import.meta.url);

Deno.test({ name: 'a sign-in code survives at most 5 guesses and verifies once under 20 parallel calls', ignore: !PG_URL, fn: async () => {
  const sql = postgres(PG_URL!, { max: 25, onnotice: () => {} });
  try {
    await sql.unsafe(`
      do $$ begin
        if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
        if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
      end $$;
      drop table if exists public.email_verifications cascade;
      create table public.email_verifications (id bigserial primary key, email text, purpose text, user_kind text,
        token text unique, token_hash text, attempts int default 0, used_at timestamptz, expires_at timestamptz,
        created_at timestamptz default now());`);
    await sql.unsafe(await Deno.readTextFile(FILE));

    const issue = async (email: string) => {
      await sql`insert into public.email_verifications (email, purpose, token_hash, expires_at)
                values (${email}, 'login', 'RIGHT', now() + interval '10 minutes')`;
    };
    const burst = (email: string, hash: string) => Promise.all(Array.from({ length: 20 }, () =>
      sql`select public.fn_login_otp_email_verify(${email}, ${hash}, '000000', 5) as v`.then((r) => r[0].v as string)));

    // 1. Twenty wrong guesses at once.
    await issue('zz-race-1@example.invalid');
    const wrong = await burst('zz-race-1@example.invalid', 'WRONG');
    const evaluated = wrong.filter((v) => v === 'wrong').length;
    const [row1] = await sql`select attempts, used_at from public.email_verifications where email = 'zz-race-1@example.invalid'`;
    if (evaluated !== 5) throw new Error(`expected exactly 5 guesses evaluated, got ${evaluated}: ${wrong.join(',')}`);
    if (row1.attempts !== 5) throw new Error(`expected attempts=5, got ${row1.attempts}`);
    const after = (await sql`select public.fn_login_otp_email_verify('zz-race-1@example.invalid', 'RIGHT', '000000', 5) as v`)[0].v;
    if (after === 'ok') throw new Error(`the right code after 5 wrong guesses must stay refused, got ${after}`);

    // 2. Twenty copies of the right code at once.
    await issue('zz-race-2@example.invalid');
    const right = await burst('zz-race-2@example.invalid', 'RIGHT');
    const oks = right.filter((v) => v === 'ok').length;
    if (oks !== 1) throw new Error(`a code must verify exactly once, verified ${oks} times: ${right.join(',')}`);

    // 3. An expired code is refused and not counted as a guess.
    await sql`insert into public.email_verifications (email, purpose, token_hash, expires_at)
              values ('zz-race-3@example.invalid', 'login', 'RIGHT', now() - interval '1 minute')`;
    const exp = (await sql`select public.fn_login_otp_email_verify('zz-race-3@example.invalid', 'RIGHT', '000000', 5) as v`)[0].v;
    if (exp !== 'expired') throw new Error(`an expired code must answer expired, got ${exp}`);

    // 4. A resend retires the earlier code: only the newest one verifies (review of #1245).
    await sql`select public.fn_login_otp_email_issue('zz-race-4@example.invalid', 'OLD', 'customer', 600)`;
    await sql`select public.fn_login_otp_email_issue('zz-race-4@example.invalid', 'NEW', 'customer', 600)`;
    const live = (await sql`select count(*)::int n from public.email_verifications where email = 'zz-race-4@example.invalid' and used_at is null`)[0].n;
    if (live !== 1) throw new Error(`after a resend exactly one code may be live, found ${live}`);
    const old = (await sql`select public.fn_login_otp_email_verify('zz-race-4@example.invalid', 'OLD', '000000', 5) as v`)[0].v;
    if (old === 'ok') throw new Error('the code issued before a resend still verified');
    const neu = (await sql`select public.fn_login_otp_email_verify('zz-race-4@example.invalid', 'NEW', '000000', 5) as v`)[0].v;
    if (neu !== 'ok') throw new Error(`the newest code must verify, got ${neu}`);

    // 5. Twenty sends at once still leave exactly one live code.
    await Promise.all(Array.from({ length: 20 }, (_, i) => sql`select public.fn_login_otp_email_issue('zz-race-5@example.invalid', ${'H' + i}, 'customer', 600)`));
    const live5 = (await sql`select count(*)::int n from public.email_verifications where email = 'zz-race-5@example.invalid' and used_at is null`)[0].n;
    if (live5 !== 1) throw new Error(`20 concurrent sends left ${live5} live codes`);
  } finally {
    await sql.unsafe('drop table if exists public.email_verifications cascade; drop function if exists public.fn_login_otp_email_verify(text,text,text,integer); drop function if exists public.fn_login_otp_email_issue(text,text,text,integer);').catch(() => {});
    await sql.end();
  }
} });

// THE SAME FOR A WHATSAPP PHONE CODE WE SEND OURSELVES (ledger 1252, _shared/wa_code.ts). The committed bodies of
// fn_phone_code_issue / fn_phone_code_sent / fn_phone_code_verify, the same bursts, plus: a code is checked only for
// the purpose it was issued for, and a send Twilio refused leaves nothing that can be guessed against.
const PHONE_FILE = new URL('../../../scripts/sql/a_whatsapp_phone_code_is_sent_by_us_without_the_verify_fee.sql', import.meta.url);
Deno.test({ name: 'a WhatsApp phone code survives at most 5 guesses, verifies once, and only for its own purpose', ignore: !PG_URL, fn: async () => {
  const sql = postgres(PG_URL!, { max: 25, onnotice: () => {} });
  try {
    await sql.unsafe(`
      do $$ begin
        if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
        if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
      end $$;
      drop table if exists public.phone_code cascade;
      -- the file registers phone_code in the daily export (excluded, a secret); production has this table
      create table if not exists public.table_export_registry (table_name text primary key, exported boolean not null,
        category text, reason text, added_by text);`);
    await sql.unsafe(await Deno.readTextFile(PHONE_FILE));
    const issue = (phone: string, hash: string, purpose = 'login') =>
      sql`select public.fn_phone_code_issue(${phone}, ${purpose}, ${hash}, 'customer', '', 600) as id`.then((r) => r[0].id as string);
    const verify = (phone: string, hash: string, purpose = 'login') =>
      sql`select public.fn_phone_code_verify(${phone}, ${purpose}, ${hash}, 5) as v`.then((r) => r[0].v as string);
    const burst = (phone: string, hash: string) => Promise.all(Array.from({ length: 20 }, () => verify(phone, hash)));

    await issue('+971500000091', 'RIGHT');
    const wrong = await burst('+971500000091', 'WRONG');
    if (wrong.filter((v) => v === 'wrong').length !== 5) throw new Error(`expected exactly 5 guesses evaluated: ${wrong.join(',')}`);
    if ((await verify('+971500000091', 'RIGHT')) === 'ok') throw new Error('the right code after 5 wrong guesses must stay refused');

    await issue('+971500000092', 'RIGHT');
    const oks = (await burst('+971500000092', 'RIGHT')).filter((v) => v === 'ok').length;
    if (oks !== 1) throw new Error(`a phone code must verify exactly once, verified ${oks} times`);

    await issue('+971500000093', 'OLD'); await issue('+971500000093', 'NEW');
    if ((await verify('+971500000093', 'OLD')) === 'ok') throw new Error('the code issued before a resend still verified');
    if ((await verify('+971500000093', 'NEW')) !== 'ok') throw new Error('the newest code must verify');

    await issue('+971500000094', 'RIGHT', 'kyc_whatsapp');
    if ((await verify('+971500000094', 'RIGHT', 'kyc_phone')) !== 'no_code') throw new Error('a kyc_whatsapp code was checked as a kyc_phone code');

    const id = await issue('+971500000095', 'RIGHT');
    await sql`select public.fn_phone_code_sent(${id}, 'refused:63016', false)`;
    if ((await verify('+971500000095', 'RIGHT')) !== 'no_code') throw new Error('a code Twilio refused to send is still live');

    await Promise.all(Array.from({ length: 20 }, (_, i) => issue('+971500000096', 'H' + i)));
    const live = (await sql`select count(*)::int n from public.phone_code where phone = '+971500000096' and used_at is null`)[0].n;
    if (live !== 1) throw new Error(`20 concurrent sends left ${live} live phone codes`);

    await sql`insert into public.phone_code (phone, purpose, code_hash, expires_at) values ('+971500000097', 'login', 'RIGHT', now() - interval '1 minute')`;
    if ((await verify('+971500000097', 'RIGHT')) !== 'expired') throw new Error('an expired phone code must answer expired');

    const anon = (await sql`select has_function_privilege('anon', 'public.fn_phone_code_verify(text,text,text,integer)', 'execute') as x`)[0].x;
    if (anon) throw new Error('anon can execute fn_phone_code_verify');
  } finally {
    await sql.unsafe('drop table if exists public.phone_code cascade; drop function if exists public.fn_phone_code_issue(text,text,text,text,text,integer); drop function if exists public.fn_phone_code_sent(bigint,text,boolean); drop function if exists public.fn_phone_code_verify(text,text,text,integer);').catch(() => {});
    await sql.end();
  }
} });
