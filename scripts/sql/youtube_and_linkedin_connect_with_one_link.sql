-- YOUTUBE AND THE LINKEDIN COMPANY PAGE CONNECT WITH ONE LINK EACH (23 Sep 2026; seat: marketing; instructions 919-920).
--
-- Founder: "For YouTube and LinkedIn: give me a direct link to click and then I will connect you."
-- MEASURED before this file (read-only): app_secrets has no google_*/youtube_*/linkedin_oauth* key; social_message
-- and social_conversation admit 'instagram','facebook','youtube' (the_marketing_seat_answers_comments_on_every_channel.sql).
--
-- BUILDS
--   social_connect_link                   one row per connect link: only the SHA-256 of the link token, the platform,
--                                         a 24-hour expiry, and the state/PKCE bound when it is opened. Single use is
--                                         enforced by the edge function's conditional UPDATEs (started_at is null,
--                                         completed_at is null). Service role only; not exported (transient, secret).
--   fn_marketing_social_connect_link(p)   mints a link token and returns it ONCE; the raw token is never stored.
--   social_* platform checks              + 'linkedin' (the company page only; the duty never reads a member).
--   function_owner                        marketing_social_connect -> marketing.
--
--   node scripts/apply_sql.mjs scripts/sql/youtube_and_linkedin_connect_with_one_link.sql --apply --ddl
begin;

create table if not exists public.social_connect_link (
  id            bigint generated always as identity primary key,
  platform      text not null check (platform in ('youtube', 'linkedin')),
  token_hash    text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  started_at    timestamptz,
  state_hash    text unique check (state_hash is null or state_hash ~ '^[0-9a-f]{64}$'),
  code_verifier text,
  completed_at  timestamptz,
  result        text,
  constraint social_connect_link_order check (completed_at is null or started_at is not null)
);
comment on table public.social_connect_link is
  'Marketing seat. One row per founder connect link for YouTube / the LinkedIn company page (instructions 919-920). Holds only hashes; the edge function marketing_social_connect claims a row once to start and once to finish.';
alter table public.social_connect_link enable row level security;
drop policy if exists social_connect_link_service_role_only on public.social_connect_link;
create policy social_connect_link_service_role_only on public.social_connect_link
  as permissive for all to public using (false) with check (false);
revoke all on public.social_connect_link from anon, authenticated;

create or replace function public.fn_marketing_social_connect_link(p_platform text)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_token text;
begin
  if p_platform not in ('youtube', 'linkedin') then
    raise exception 'fn_marketing_social_connect_link: platform must be youtube or linkedin, not %', p_platform;
  end if;
  -- 32 random bytes, base64url: the edge function accepts 40-64 characters of [A-Za-z0-9_-].
  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.social_connect_link (platform, token_hash, expires_at)
  values (p_platform, encode(extensions.digest(v_token, 'sha256'), 'hex'), now() + interval '24 hours');
  return v_token;
end
$fn$;
revoke execute on function public.fn_marketing_social_connect_link(text) from public, anon, authenticated;

alter table public.social_conversation drop constraint if exists social_conversation_platform_check;
alter table public.social_conversation add constraint social_conversation_platform_check
  check (platform in ('instagram', 'facebook', 'youtube', 'linkedin'));
alter table public.social_message drop constraint if exists social_message_platform_check;
alter table public.social_message add constraint social_message_platform_check
  check (platform in ('instagram', 'facebook', 'youtube', 'linkedin'));

insert into public.function_owner (function_slug, owner, note) values
  ('marketing_social_connect', 'marketing',
   'The founder''s one connect link per platform for YouTube and the LinkedIn company page (instructions 919-920): OAuth with the minimum company scopes, tokens sealed in app_secrets, the account verified as QuotesDone''s.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

-- PROBE (cleans up after itself, returns a verdict row): a minted link is stored only as its hash, expires in 24 h.
-- The link is minted in its OWN statement: a row a function inserts is not visible to the statement that called it,
-- so minting inside the verdict query joined nothing and returned no verdict (release of #883, 23 Sep 2026).
create temp table probe_883_link on commit drop as select public.fn_marketing_social_connect_link('youtube') as tok;
select case when h.token_hash = encode(extensions.digest(t.tok, 'sha256'), 'hex')
             and h.expires_at between now() + interval '23 hours' and now() + interval '25 hours'
             and not exists (select 1 from public.social_connect_link x where x.token_hash = t.tok)
            then 'PROBE OK' else 'PROBE FAILED: link row wrong' end as verdict
  from probe_883_link t
  join public.social_connect_link h on h.token_hash = encode(extensions.digest(t.tok, 'sha256'), 'hex');
delete from public.social_connect_link where started_at is null and created_at = now();   -- now() is this transaction's: only the probe's row

commit;
