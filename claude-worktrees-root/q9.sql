select public.fn_judgement_without_recall() probe, (select count(*) from seat_judgement) rows;
