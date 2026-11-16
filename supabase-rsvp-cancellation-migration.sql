-- Migração: busca protegida e cancelamento de confirmação de presença.
-- Execute uma única vez no Supabase > SQL Editor.
-- A consulta exige nome completo + telefone cadastrado. Nenhuma lista pública de convidados é exposta.

alter table public.rsvps
  add column if not exists status text not null default 'Ativa';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'rsvps_status_check'
      and conrelid = 'public.rsvps'::regclass
  ) then
    alter table public.rsvps
      add constraint rsvps_status_check
      check (status in ('Ativa', 'Cancelada'));
  end if;
end;
$$;

create or replace function public.find_rsvp_for_cancellation(
  p_nome text,
  p_telefone text
)
returns table(id uuid, nome text, quantidade integer)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.nome, r.quantidade
  from public.rsvps r
  where lower(trim(r.nome)) = lower(trim(p_nome))
    and regexp_replace(r.telefone, '[^0-9]', '', 'g')
        = regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g')
    and r.presenca = 'Sim, estarei presente'
    and r.status = 'Ativa'
  order by r.created_at desc
  limit 5;
$$;

revoke all on function public.find_rsvp_for_cancellation(text, text) from public;
grant execute on function public.find_rsvp_for_cancellation(text, text) to anon, authenticated;

create or replace function public.cancel_rsvp_attendance(
  p_rsvp_id uuid,
  p_nome text,
  p_telefone text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  update public.rsvps r
     set status = 'Cancelada'
   where r.id = p_rsvp_id
     and lower(trim(r.nome)) = lower(trim(p_nome))
     and regexp_replace(r.telefone, '[^0-9]', '', 'g')
         = regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g')
     and r.presenca = 'Sim, estarei presente'
     and r.status = 'Ativa';

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$$;

revoke all on function public.cancel_rsvp_attendance(uuid, text, text) from public;
grant execute on function public.cancel_rsvp_attendance(uuid, text, text) to anon, authenticated;
