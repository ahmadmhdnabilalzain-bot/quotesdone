// A SIGN-IN CODE IS COUNTED AND SPENT ONCE, EVEN UNDER A BURST (pre-launch security pass, 6 Oct 2026, H1).
//
// Runs the committed body of public.fn_login_otp_email_verify against a throwaway Postgres (CI starts
// one as a service; locally: QD_OTP_RACE_PG=postgres://... deno test ...). It never touches the
// production project. Twenty guesses go in at once on twenty connections, the shape an attacker uses
// to beat a read-then-write counter, and the check asserts:
//   * 20 wrong guesses at one code: exactly 5 are evaluated (`wrong`), the counter ends at 5, and a
//     right guess after that finds the code burned;
//   * 20 copies of the RIGHT code at once: exactly one `ok`, so one code mints one session.
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
  } finally {
    await sql.unsafe('drop table if exists public.email_verifications cascade; drop function if exists public.fn_login_otp_email_verify(text,text,text,integer);').catch(() => {});
    await sql.end();
  }
} });
