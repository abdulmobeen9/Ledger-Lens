-- Prevent a user from attaching another account's category UUID to their transaction.
create or replace function public.enforce_transaction_category_owner()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if new.category_id is not null and not exists (
    select 1 from public.categories c
    where c.id = new.category_id and c.user_id = new.user_id
  ) then
    raise exception 'category does not belong to transaction owner' using errcode = '23503';
  end if;
  return new;
end;
$$;
drop trigger if exists transactions_category_owner_guard on public.transactions;
create trigger transactions_category_owner_guard
before insert or update of category_id, user_id on public.transactions
for each row execute function public.enforce_transaction_category_owner();
