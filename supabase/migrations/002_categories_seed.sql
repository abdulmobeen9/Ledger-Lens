-- Defaults are inserted per user at first authenticated app session.
-- This function is safe to call repeatedly.
create or replace function public.seed_default_categories()
returns void language plpgsql security invoker set search_path = public as $$
begin
  insert into public.categories(user_id, name, icon, color, type)
  select auth.uid(), v.name, v.icon, v.color, v.type
  from (values
    ('Salary','payments','#16A34A','income'),
    ('Other income','trending_up','#22C55E','income'),
    ('Groceries','shopping_basket','#F59E0B','expense'),
    ('Transport','directions_car','#3B82F6','expense'),
    ('Utilities','bolt','#8B5CF6','expense'),
    ('Dining','restaurant','#EC4899','expense'),
    ('Other','category','#64748B','both')
  ) as v(name,icon,color,type)
  where auth.uid() is not null
  on conflict (user_id, name, type) do nothing;
end; $$;
grant execute on function public.seed_default_categories() to authenticated;
