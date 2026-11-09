-- GuildScribe – schéma Supabase.
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- Peut être relancé sans risque (idempotent).

create extension if not exists pgcrypto with schema extensions;

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------

create table if not exists public.guilds (
  key          text primary key,           -- "<Guilde>-<Royaume>"
  name         text not null,
  realm        text,
  info         jsonb not null default '{}',  -- motd, text, numMembers, numOnline
  ranks        jsonb not null default '[]',
  scanned_at   timestamptz,
  scanned_by   text,
  updated_at   timestamptz not null default now()
);

create table if not exists public.members (
  guild_key          text not null references public.guilds(key) on delete cascade,
  name               text not null,          -- "<Nom>-<Royaume>"
  guid               text,
  rank               text,
  rank_index         int,
  level              int,
  class              text,                   -- WARRIOR, MAGE...
  class_localized    text,
  zone               text,
  public_note        text,
  online             boolean,
  mobile             boolean,
  last_online        timestamptz,
  achievement_points int,
  guild_rep          int,
  in_guild           boolean not null default true,
  left_at            timestamptz,
  roster_seen_at     timestamptz,
  guild_professions  jsonb not null default '{}',
  profile            jsonb,                  -- fiche envoyée par l'add-on
  profile_at         timestamptz,
  updated_at         timestamptz not null default now(),
  primary key (guild_key, name)
);

-- Jetons des uploaders (seul le hash est stocké).
create table if not exists public.upload_tokens (
  id           bigserial primary key,
  label        text not null,
  token_hash   text not null unique,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz,
  revoked      boolean not null default false
);

-- Notes d'officier, à part : visibles seulement des officiers.
create table if not exists public.member_officer_notes (
  guild_key  text not null,
  name       text not null,
  note       text,
  updated_at timestamptz not null default now(),
  primary key (guild_key, name),
  foreign key (guild_key, name) references public.members(guild_key, name) on delete cascade
);

-- Qui a accès au site. Rempli automatiquement par /api/claim (Vercel)
-- après vérification que la personne est sur le serveur Discord de la guilde.
create table if not exists public.site_access (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  discord_id   text not null,
  discord_name text,
  role         text not null check (role in ('member', 'officer')),
  checked_at   timestamptz not null default now()
);

---------------------------------------------------------------------------
-- Sécurité : lecture réservée aux membres vérifiés (re-vérifiés à chaque
-- connexion, accès expiré après 30 jours sans reconnexion).
-- Personne n'écrit directement : tout passe par ingest_guild / l'API claim.
---------------------------------------------------------------------------

create or replace function public.gs_role()
returns text
language sql stable security definer
set search_path = public
as $$
  select role from public.site_access
  where user_id = auth.uid() and checked_at > now() - interval '30 days'
$$;

alter table public.guilds               enable row level security;
alter table public.members              enable row level security;
alter table public.member_officer_notes enable row level security;
alter table public.upload_tokens        enable row level security;
alter table public.site_access          enable row level security;

drop policy if exists "lecture publique" on public.guilds;
drop policy if exists "lecture publique" on public.members;
drop policy if exists "membres" on public.guilds;
create policy "membres" on public.guilds  for select to authenticated using (public.gs_role() is not null);
drop policy if exists "membres" on public.members;
create policy "membres" on public.members for select to authenticated using (public.gs_role() is not null);
drop policy if exists "officiers" on public.member_officer_notes;
create policy "officiers" on public.member_officer_notes for select to authenticated using (public.gs_role() = 'officer');
drop policy if exists "soi-meme" on public.site_access;
create policy "soi-meme" on public.site_access for select to authenticated using (user_id = auth.uid());
-- upload_tokens : aucune policy => illisible depuis le site.

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

create or replace function public._gs_ts(j jsonb, k text)
returns timestamptz language sql immutable as $$
  select case when jsonb_typeof(j->k) = 'number' then to_timestamp((j->>k)::double precision) end
$$;

create or replace function public._gs_int(j jsonb, k text)
returns int language sql immutable as $$
  select case when jsonb_typeof(j->k) = 'number' then round((j->>k)::numeric)::int end
$$;

create or replace function public._gs_bool(j jsonb, k text)
returns boolean language sql immutable as $$
  select case when jsonb_typeof(j->k) = 'boolean' then (j->>k)::boolean end
$$;

-- Fusion de deux objets "à sections" (fiche add-on, infos de guilde) :
-- pour chaque clé, la section qui a le champ "at" le plus récent gagne ;
-- les autres clés suivent p_newer (true = l'envoi est plus récent).
-- Une section absente de l'envoi est conservée (ex. sacs, banque : seul
-- l'uploader du joueur les connaît).
create or replace function public._gs_merge_sections(p_old jsonb, p_new jsonb, p_newer boolean)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, case
      when o.v is null then n.v
      when n.v is null then o.v
      when jsonb_typeof(o.v -> 'at') = 'number' or jsonb_typeof(n.v -> 'at') = 'number' then
        case when coalesce(case when jsonb_typeof(n.v -> 'at') = 'number' then (n.v ->> 'at')::numeric end, 0)
               >= coalesce(case when jsonb_typeof(o.v -> 'at') = 'number' then (o.v ->> 'at')::numeric end, 0)
             then n.v else o.v end
      when coalesce(p_newer, false) then n.v
      else o.v end), '{}'::jsonb)
  from jsonb_each(case when jsonb_typeof(p_old) = 'object' then p_old else '{}'::jsonb end) o(k, v)
  full join jsonb_each(case when jsonb_typeof(p_new) = 'object' then p_new else '{}'::jsonb end) n(k, v) using (k)
$$;

---------------------------------------------------------------------------
-- Création d'un jeton d'upload (à lancer dans le SQL Editor uniquement) :
--   select public.create_upload_token('Morgane');
-- Le jeton en clair n'est affiché qu'une fois : copie-le.
---------------------------------------------------------------------------

create or replace function public.create_upload_token(p_label text)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_token text := encode(gen_random_bytes(24), 'hex');
begin
  insert into public.upload_tokens(label, token_hash)
  values (p_label, encode(digest(v_token, 'sha256'), 'hex'));
  return v_token;
end;
$$;

revoke all on function public.create_upload_token(text) from public, anon, authenticated;

---------------------------------------------------------------------------
-- Ingestion : appelée par l'uploader avec la clé "anon" + un jeton d'upload.
-- Fusionne intelligemment : on ne remplace une donnée que par une plus récente,
-- donc plusieurs officiers peuvent envoyer sans s'écraser.
---------------------------------------------------------------------------

create or replace function public.ingest_guild(p_token text, p_payload jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_token_id bigint;
  g          record;
  m          record;
  gv         jsonb;
  mv         jsonb;
  v_guilds   int := 0;
  v_members  int := 0;
begin
  select id into v_token_id
  from public.upload_tokens
  where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
    and not revoked;
  if v_token_id is null then
    raise exception 'jeton invalide' using errcode = '42501';
  end if;
  update public.upload_tokens set last_used_at = now() where id = v_token_id;

  for g in select key, value from jsonb_each(coalesce(p_payload->'guilds', '{}'::jsonb)) loop
    gv := g.value;
    v_guilds := v_guilds + 1;

    insert into public.guilds as t (key, name, realm, info, ranks, scanned_at, scanned_by, updated_at)
    values (
      g.key,
      coalesce(gv->>'name', g.key),
      gv->>'realm',
      case when jsonb_typeof(gv->'info') = 'object' then gv->'info' else '{}'::jsonb end,
      case when jsonb_typeof(gv->'ranks') = 'array' then gv->'ranks' else '[]'::jsonb end,
      _gs_ts(gv, 'scannedAt'),
      gv->>'scannedBy',
      now()
    )
    on conflict (key) do update set
      name       = case when t.scanned_at is null or excluded.scanned_at >= t.scanned_at then excluded.name else t.name end,
      realm      = case when t.scanned_at is null or excluded.scanned_at >= t.scanned_at then excluded.realm else t.realm end,
      info       = public._gs_merge_sections(t.info, excluded.info,
                     t.scanned_at is null or excluded.scanned_at >= t.scanned_at),
      ranks      = case when t.scanned_at is null or excluded.scanned_at >= t.scanned_at then excluded.ranks else t.ranks end,
      scanned_by = case when t.scanned_at is null or excluded.scanned_at >= t.scanned_at then excluded.scanned_by else t.scanned_by end,
      scanned_at = greatest(t.scanned_at, excluded.scanned_at),
      updated_at = now();

    for m in select key, value from jsonb_each(
      case when jsonb_typeof(gv->'members') = 'object' then gv->'members' else '{}'::jsonb end
    ) loop
      mv := m.value;
      v_members := v_members + 1;

      insert into public.members (guild_key, name) values (g.key, m.key)
      on conflict do nothing;

      -- Infos du roster : seulement si plus récentes.
      update public.members t set
        guid               = mv->>'guid',
        rank               = mv->>'rank',
        rank_index         = _gs_int(mv, 'rankIndex'),
        level              = _gs_int(mv, 'level'),
        class              = mv->>'class',
        class_localized    = mv->>'classLocalized',
        zone               = mv->>'zone',
        public_note        = mv->>'publicNote',
        online             = _gs_bool(mv, 'online'),
        mobile             = _gs_bool(mv, 'mobile'),
        last_online        = coalesce(_gs_ts(mv, 'lastOnline'), t.last_online),
        achievement_points = _gs_int(mv, 'achievementPoints'),
        guild_rep          = _gs_int(mv, 'guildRep'),
        in_guild           = coalesce(_gs_bool(mv, 'inGuild'), t.in_guild),
        left_at            = _gs_ts(mv, 'leftAt'),
        roster_seen_at     = _gs_ts(mv, 'rosterSeenAt'),
        updated_at         = now()
      where t.guild_key = g.key and t.name = m.key
        and _gs_ts(mv, 'rosterSeenAt') is not null
        and (t.roster_seen_at is null or _gs_ts(mv, 'rosterSeenAt') >= t.roster_seen_at);

      -- Note d'officier (présente seulement si l'uploader a le droit de la voir en jeu).
      if jsonb_typeof(mv->'officerNote') = 'string' then
        insert into public.member_officer_notes as t (guild_key, name, note, updated_at)
        values (g.key, m.key, mv->>'officerNote', coalesce(_gs_ts(mv, 'rosterSeenAt'), now()))
        on conflict (guild_key, name) do update set
          note = excluded.note, updated_at = excluded.updated_at
        where excluded.updated_at >= t.updated_at;
      end if;

      -- Fiche détaillée de l'add-on : fusion section par section (la plus récente gagne).
      update public.members t set
        profile    = public._gs_merge_sections(t.profile, mv->'profile',
                       t.profile_at is null or _gs_ts(mv, 'profileAt') >= t.profile_at),
        profile_at = greatest(t.profile_at, _gs_ts(mv, 'profileAt')),
        updated_at = now()
      where t.guild_key = g.key and t.name = m.key
        and jsonb_typeof(mv->'profile') = 'object';

      -- Annuaire des métiers de guilde : fusion par métier.
      if jsonb_typeof(mv->'guildProfessions') = 'object' then
        update public.members t set
          guild_professions = t.guild_professions || (mv->'guildProfessions'),
          updated_at = now()
        where t.guild_key = g.key and t.name = m.key;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('guilds', v_guilds, 'members', v_members);
end;
$$;

revoke all on function public.ingest_guild(text, jsonb) from public;
grant execute on function public.ingest_guild(text, jsonb) to anon, authenticated;
