-- Migração incremental para a lista de presentes: execute no SQL Editor do Supabase.
alter table public.gift_catalog add column if not exists photo_url text;
alter table public.gift_catalog add column if not exists sort_order integer not null default 0;

-- Mantém a lista sem itens de demonstração; a ordenação inicial é alfabética.
with ordered as (
  select id, row_number() over (order by name, id) as position
  from public.gift_catalog
)
update public.gift_catalog g set sort_order=ordered.position
from ordered where ordered.id=g.id and g.sort_order=0;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('gift-photos','gift-photos',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "Public can view gift photos" on storage.objects;
create policy "Public can view gift photos" on storage.objects
for select to anon, authenticated using (bucket_id='gift-photos');

drop policy if exists "Admins upload gift photos" on storage.objects;
create policy "Admins upload gift photos" on storage.objects
for insert to authenticated with check (bucket_id='gift-photos' and public.is_wedding_admin());

drop policy if exists "Admins update gift photos" on storage.objects;
create policy "Admins update gift photos" on storage.objects
for update to authenticated using (bucket_id='gift-photos' and public.is_wedding_admin())
with check (bucket_id='gift-photos' and public.is_wedding_admin());

drop policy if exists "Admins delete gift photos" on storage.objects;
create policy "Admins delete gift photos" on storage.objects
for delete to authenticated using (bucket_id='gift-photos' and public.is_wedding_admin());
