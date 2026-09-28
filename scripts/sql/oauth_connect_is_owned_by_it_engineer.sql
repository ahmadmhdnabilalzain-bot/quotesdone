-- it_engineer, 28 Sep 2026: the founder's three consent links (supabase/functions/oauth_connect) name their owner.
-- No routine, no table: one ownership row. The refresh tokens it writes are read by PR #961 and PR #966.
insert into public.function_owner (function_slug, owner, note) values
  ('oauth_connect', 'it_engineer',
   'The founder''s consent links for Gmail Postmaster Tools, the Gmail seed inbox and the Outlook seed inbox: signed state, PKCE, allowlisted account, refresh token written to app_secrets. No token is ever shown or logged.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

select case when exists (select 1 from public.function_owner where function_slug = 'oauth_connect' and owner = 'it_engineer')
            then 'PROBE OK' else 'PROBE FAILED: oauth_connect has no it_engineer owner row' end as verdict;
