-- Durable cloud deletion journal so deletes propagate to every device on its next sync.
create table if not exists public.sync_deletions (
  id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('transactions','categories')),
  deleted_at timestamptz not null default now(),
  primary key (id, entity_type)
);
create index if not exists sync_deletions_user_deleted_idx
  on public.sync_deletions(user_id, deleted_at desc);
alter table public.sync_deletions enable row level security;
drop policy if exists "users manage own sync deletions" on public.sync_deletions;
create policy "users manage own sync deletions" on public.sync_deletions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
