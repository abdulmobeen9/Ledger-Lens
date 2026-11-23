create extension if not exists pgcrypto;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  icon text not null default 'category',
  color text not null default '#64748B',
  type text not null default 'both' check (type in ('income','expense','both')),
  created_at timestamptz not null default now(),
  unique(user_id, name, type)
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('income','expense')),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'USD',
  txn_date date not null,
  counterparty_name text,
  transfer_method text check (transfer_method is null or transfer_method in ('bank','cash','wallet','card','other')),
  reference_no text,
  receiving_number text,
  category_id uuid references public.categories(id) on delete set null,
  notes text,
  image_url text,
  ocr_raw_text text,
  ocr_confidence real check (ocr_confidence is null or (ocr_confidence >= 0 and ocr_confidence <= 1)),
  extraction_source text not null default 'manual' check (extraction_source in ('manual','ocr_llm')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.receipt_scans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  image_url text,
  ocr_raw_text text,
  llm_response jsonb,
  confidence real check (confidence is null or (confidence >= 0 and confidence <= 1)),
  status text not null default 'pending' check (status in ('pending','confirmed','discarded')),
  created_at timestamptz not null default now()
);

create index if not exists transactions_user_date_idx on public.transactions(user_id, txn_date desc);
create index if not exists transactions_user_updated_idx on public.transactions(user_id, updated_at desc);
create index if not exists transactions_category_idx on public.transactions(category_id);
create index if not exists receipt_scans_user_created_idx on public.receipt_scans(user_id, created_at desc);

alter table public.transactions enable row level security;
alter table public.categories enable row level security;
alter table public.receipt_scans enable row level security;

create policy "users manage own transactions" on public.transactions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "users manage own categories" on public.categories for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "users manage own receipt scans" on public.receipt_scans for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "owner can upload receipts" on storage.objects for insert to authenticated
with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owner can read receipts" on storage.objects for select to authenticated
using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owner can delete receipts" on storage.objects for delete to authenticated
using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists transactions_touch_updated_at on public.transactions;
create trigger transactions_touch_updated_at before update on public.transactions
for each row execute function public.touch_updated_at();
