-- A WEBSITE-CHAT WORKER RUNS AT MOST FIVE TURNS AT ONCE (it_engineer, 11 Nov 2026; founder ruling 1622).
--
-- WHY. site_assistant admits at most `site_assistant_worker_turns` turns per edge worker at once and answers one more
-- with {busy, retry_after_ms}; the widget retries (#1925, #1929). The default is 8 (worker_admission.ts). The platform
-- kills a worker at about 2 s of CPU summed over every turn it holds (measured 11 Nov 02:42 UTC: one kill ended 18 turns),
-- and a worker is retired near a ~1.1 s soft limit, so the turns it already holds at that point must fit the gap.
-- MEASURED, chat load run zzloadb63e74, 05:28-05:45 UTC, model stubbed, AED 0: at 100 concurrent chats 8 turns answered
-- HTTP 546 together (one worker killed holding its 8), with 221 sheds all retried. At ~110-210 ms CPU per turn, 8 held
-- turns can overrun the gap; 5 keep it (1.1 s + 5 x 0.18 s ~= 2.0 s worst case, ~1.65 s typical). Sheds rise; the widget's
-- 6 tries (#1929) absorb them. Retunable here without a deploy (TD-38): the worker reads it once a minute.
--
--   node scripts/apply_sql.mjs scripts/sql/a_website_chat_worker_runs_at_most_five_turns_at_once.sql --apply --ddl --seat it_engineer

insert into public.app_secrets (key, value) values ('site_assistant_worker_turns', '5')
on conflict (key) do update set value = excluded.value;

-- VERDICT (this file sets one value and reads it back).
select case when (select value from public.app_secrets where key = 'site_assistant_worker_turns') = '5'
            then 'OK site_assistant_worker_turns = 5' else 'FAILED: site_assistant_worker_turns not 5' end as verdict;
