select id, surface, status, subject, created_at from reasoning_held_question
 where created_at > now() - interval '2 hours' and surface ilike 'accountant%' order by id desc limit 5;
