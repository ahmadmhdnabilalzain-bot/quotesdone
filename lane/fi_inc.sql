insert into public.founder_instruction (instruction, said_at)
values ('12 Oct: someone who starts sign-up but does not finish every step (email, mobile OTP, terms signed with IP) is never a customer. 30 minutes after the start, an unfinished sign-up is deleted entirely as if they never tried - nothing kept, nothing sent ("what are we saving?").', now()) returning id;
