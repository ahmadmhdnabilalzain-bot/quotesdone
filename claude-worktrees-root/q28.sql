select max(sent_at) last_email_sent, count(*) filter (where status='queued' and channel='email') q from notifications where created_at > now()-interval '1 day';
