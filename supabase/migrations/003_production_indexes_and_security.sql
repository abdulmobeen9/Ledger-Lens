-- Production hardening: support category analytics, filtering and owner-scoped receipt access.
create index if not exists transactions_user_category_date_idx
  on public.transactions(user_id, category_id, txn_date desc);
create index if not exists transactions_user_type_date_idx
  on public.transactions(user_id, type, txn_date desc);
create index if not exists categories_user_name_idx
  on public.categories(user_id, name);

-- Storage bucket remains private; clients must use short-lived signed URLs for previews.
update storage.buckets set public = false, file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg','image/png','image/webp']
where id = 'receipts';

-- Keep the database clock authoritative for remote edits. Client sync compares timestamps
-- before upserting, and pulls rows that are newer than its local copy.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
