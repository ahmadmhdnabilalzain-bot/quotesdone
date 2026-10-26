select proname, left(prosrc, 1500) s from pg_proc where proname in ('trg_pages_legal_sync','trg_pages_dirty');
