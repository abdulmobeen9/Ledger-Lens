-- Three-decimal currencies (BHD, KWD, OMR, JOD, IQD, LYD, TND) need more than numeric(14,2).
-- Without this, the server rounds those amounts to 2 decimals and devices disagree after sync.
alter table public.transactions alter column amount type numeric(18,3);
