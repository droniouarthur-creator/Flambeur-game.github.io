-- Flambeur ! — schéma Supabase. À coller dans « SQL Editor » après avoir créé le projet (région UE).
-- Principe : la sécurité est dans la base (RLS). La clé « anon » peut être publique, la clé « service_role » JAMAIS.

create table public.admins (user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.admins enable row level security;  -- aucune politique : invisible depuis l'appli

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

-- Sauvegarde du joueur (noms habituels, questions perso, statistiques) : une ligne par compte
create table public.saves (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.saves enable row level security;
create policy saves_owner on public.saves for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Packs de questions
create table public.packs (
  id text primary key,
  title text not null,
  description text,
  price_cents integer not null default 0 check (price_cents >= 0),
  is_free boolean not null default false,
  active boolean not null default true
);
alter table public.packs enable row level security;
create policy packs_read  on public.packs for select using (active or public.is_admin());
create policy packs_admin on public.packs for all using (public.is_admin()) with check (public.is_admin());

create table public.pack_questions (
  id bigint generated always as identity primary key,
  pack_id text not null references public.packs(id) on delete cascade,
  q text not null,
  u text not null,
  a bigint not null check (a >= 1),
  s text, e text, v text,
  source_url text, verified_on date
);
alter table public.pack_questions enable row level security;
-- Lecture : packs gratuits pour tous, packs payants seulement pour ceux qui les ont achetés
create policy pq_read on public.pack_questions for select using (
  public.is_admin()
  or exists (select 1 from public.packs p where p.id = pack_questions.pack_id and p.is_free and p.active)
  or exists (select 1 from public.entitlements e where e.user_id = auth.uid() and e.pack_id = pack_questions.pack_id)
);
create policy pq_admin on public.pack_questions for all using (public.is_admin()) with check (public.is_admin());

-- Achats : AUCUNE écriture depuis l'appli. Seules tes fonctions serveur (webhook Stripe, RevenueCat) écrivent ici.
create table public.entitlements (
  user_id uuid not null references auth.users(id) on delete cascade,
  pack_id text not null references public.packs(id),
  source text not null check (source in ('stripe','apple','google','gift')),
  external_id text,
  purchased_at timestamptz not null default now(),
  primary key (user_id, pack_id)
);
alter table public.entitlements enable row level security;
create policy ent_read_own on public.entitlements for select using (user_id = auth.uid());

-- Propositions de questions des joueurs
create table public.suggestions (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  q text not null check (char_length(q) between 5 and 400),
  u text not null check (char_length(u) <= 40),
  a bigint not null check (a >= 1),
  s text check (char_length(s) <= 300),
  e text check (char_length(e) <= 200),
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now()
);
alter table public.suggestions enable row level security;
create policy sug_insert on public.suggestions for insert
  with check (user_id = auth.uid() and status = 'pending');
create policy sug_read   on public.suggestions for select using (user_id = auth.uid() or public.is_admin());
create policy sug_admin  on public.suggestions for update using (public.is_admin()) with check (public.is_admin());
create policy sug_delete on public.suggestions for delete using (public.is_admin());

-- Accepter une proposition : l'ajoute à un pack et la marque « acceptée » (réservé aux admins)
create or replace function public.approve_suggestion(sid bigint, target_pack text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  insert into public.pack_questions (pack_id, q, u, a, s, e)
    select target_pack, q, u, a, s, e from public.suggestions where id = sid and status = 'pending';
  update public.suggestions set status = 'accepted' where id = sid;
end $$;

-- Pack de base gratuit
insert into public.packs (id, title, description, price_cents, is_free)
values ('base', 'Pack de base', 'Les questions de départ', 0, true);
-- Exemple de pack payant (à décommenter) :
-- insert into public.packs (id, title, description, price_cents) values ('wtf', 'Pack WTF', 'Des faits improbables', 299);

-- Ton compte administrateur (après ta première connexion, remplace l'UUID par le tien, visible dans Authentication > Users) :
-- insert into public.admins (user_id) values ('00000000-0000-0000-0000-000000000000');
