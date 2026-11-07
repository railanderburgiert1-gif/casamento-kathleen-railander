-- Configuração do banco de dados do site Kathleen & Railander
-- Execute este arquivo uma vez no SQL Editor do seu projeto Supabase.

create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.rsvps (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(trim(nome)) between 3 and 120),
  telefone text not null check (char_length(trim(telefone)) between 8 and 25),
  presenca text not null check (presenca in ('Sim, estarei presente', 'Não poderei comparecer')),
  quantidade integer not null check (quantidade between 1 and 10),
  mensagem text not null default '' check (char_length(mensagem) <= 1000),
  created_at timestamptz not null default now()
);

create table if not exists public.gift_catalog (
  id text primary key,
  name text not null,
  description text not null default '',
  is_reserved boolean not null default false,
  active boolean not null default true,
  photo_url text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- A lista começa vazia. Os noivos cadastram os itens pelo painel administrativo.

create table if not exists public.gift_reservations (
  id uuid primary key default gen_random_uuid(),
  gift_id text not null references public.gift_catalog(id),
  gift_name text not null,
  guest_name text not null check (char_length(trim(guest_name)) between 2 and 120),
  status text not null default 'Aguardando confirmação'
    check (status in ('Aguardando confirmação', 'Confirmado', 'Cancelado')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists private.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_wedding_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.admin_users
    where user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_wedding_admin() from public;
grant execute on function public.is_wedding_admin() to authenticated;

create or replace function public.reserve_wedding_gift(p_gift_id text, p_guest_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_gift_name text;
begin
  if p_guest_name is null or char_length(trim(p_guest_name)) not between 2 and 120 then
    raise exception 'Informe um nome válido.';
  end if;

  update public.gift_catalog
     set is_reserved = true
   where id = p_gift_id
     and active = true
     and is_reserved = false
   returning name into v_gift_name;

  if v_gift_name is null then
    raise exception 'PRESENTE_INDISPONIVEL';
  end if;

  insert into public.gift_reservations (gift_id, gift_name, guest_name)
  values (p_gift_id, v_gift_name, trim(p_guest_name));

  return jsonb_build_object('success', true, 'gift_name', v_gift_name);
end;
$$;

revoke all on function public.reserve_wedding_gift(text, text) from public;
grant execute on function public.reserve_wedding_gift(text, text) to anon, authenticated;

create or replace function public.sync_gift_reserved_flag()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status then
    update public.gift_catalog
       set is_reserved = (new.status <> 'Cancelado')
     where id = new.gift_id;
    new.updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_gift_reserved_flag on public.gift_reservations;
create trigger trg_sync_gift_reserved_flag
before update of status on public.gift_reservations
for each row execute function public.sync_gift_reserved_flag();

alter table public.rsvps enable row level security;
alter table public.gift_catalog enable row level security;
alter table public.gift_reservations enable row level security;

revoke all on public.rsvps from public, anon, authenticated;
revoke all on public.gift_catalog from public, anon, authenticated;
revoke all on public.gift_reservations from public, anon, authenticated;

grant insert on public.rsvps to anon, authenticated;
grant select, update, delete on public.rsvps to authenticated;

grant select on public.gift_catalog to anon;
grant select, insert, update, delete on public.gift_catalog to authenticated;

grant select, update, delete on public.gift_reservations to authenticated;

drop policy if exists "Public can submit RSVP" on public.rsvps;
create policy "Public can submit RSVP"
on public.rsvps for insert to anon
with check (
  char_length(trim(nome)) between 3 and 120
  and char_length(trim(telefone)) between 8 and 25
  and presenca in ('Sim, estarei presente', 'Não poderei comparecer')
  and quantidade between 1 and 10
  and char_length(mensagem) <= 1000
);

drop policy if exists "Admins manage RSVPs" on public.rsvps;
create policy "Admins manage RSVPs"
on public.rsvps for all to authenticated
using (public.is_wedding_admin())
with check (public.is_wedding_admin());

drop policy if exists "Public can view active gift availability" on public.gift_catalog;
create policy "Public can view active gift availability"
on public.gift_catalog for select to anon, authenticated
using (active = true);

drop policy if exists "Admins manage gift catalog" on public.gift_catalog;
create policy "Admins manage gift catalog"
on public.gift_catalog for all to authenticated
using (public.is_wedding_admin())
with check (public.is_wedding_admin());

drop policy if exists "Admins manage gift reservations" on public.gift_reservations;
create policy "Admins manage gift reservations"
on public.gift_reservations for all to authenticated
using (public.is_wedding_admin())
with check (public.is_wedding_admin());

-- Depois de criar o usuário dos noivos em Authentication > Users,
-- execute este comando trocando o e-mail pelo e-mail cadastrado:
-- insert into private.admin_users (user_id)
-- select id from auth.users where email = 'EMAIL_DOS_NOIVOS'
-- on conflict (user_id) do nothing;


-- Fotos dos presentes: leitura pública, gravação e exclusão somente por administradores.
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

-- Para projetos que já tinham a tabela antes desta atualização:
alter table public.gift_catalog add column if not exists photo_url text;
alter table public.gift_catalog add column if not exists sort_order integer not null default 0;
