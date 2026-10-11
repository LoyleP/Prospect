-- Prospect — initial schema.
--
-- Two kinds of people use the API:
--   * admins: accounts (email + password) that belong to organizations via `memberships`;
--   * participants: agents / conseillers who joined ONE event with that event's code and a name.
-- Every business table carries org_id; the API scopes every query by the caller, so an
-- organization can never read another's rows and a participant never leaves their event.

create table users (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique check (email = lower(email)),
  display_name  text not null check (length(trim(display_name)) > 0),
  password_hash text not null,
  created_at    timestamptz not null default now()
);

create table organizations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) > 0),
  -- What this org calls its events ("Événement", "JPO", "Salon"...).
  event_label text not null default 'Événement' check (length(trim(event_label)) > 0),
  -- Shared with co-admins so they can join the organization.
  admin_code  text not null unique,
  created_at  timestamptz not null default now()
);

-- Admins of an organization.
create table memberships (
  org_id       uuid not null references organizations (id) on delete cascade,
  user_id      uuid not null references users (id) on delete cascade,
  last_seen_at timestamptz,
  created_at   timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index memberships_user_idx on memberships (user_id);

create table programs (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references organizations (id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  color       text not null check (color ~ '^#[0-9A-Fa-f]{6}$'),
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  unique (org_id, name)
);
create index programs_org_idx on programs (org_id, sort_order);

create table events (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references organizations (id) on delete cascade,
  name               text not null check (length(trim(name)) > 0),
  date               date not null,
  status             text not null default 'pas_commence'
                     check (status in ('pas_commence', 'en_cours', 'termine')),
  is_archived        boolean not null default false,
  pre_registered     integer not null default 0 check (pre_registered >= 0),
  rdv_target_low     integer not null default 0 check (rdv_target_low >= 0),
  rdv_target_high    integer not null default 0 check (rdv_target_high >= 0),
  -- { "<program uuid>": <target count> }
  program_objectives jsonb not null default '{}'::jsonb,
  -- Join codes handed out by the admin. Unusable once the event is archived.
  agent_code         text not null unique,
  cf_code            text not null unique,
  created_at         timestamptz not null default now()
);
create index events_org_idx on events (org_id, date desc);

-- People who joined an event with its code. No account, no email.
create table participants (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references organizations (id) on delete cascade,
  event_id     uuid not null references events (id) on delete cascade,
  role         text not null check (role in ('agent', 'conseiller_formation')),
  display_name text not null check (length(trim(display_name)) > 0),
  -- Programs a conseiller follows (dashboard closing stats).
  program_ids  uuid[] not null default '{}',
  last_seen_at timestamptz,
  revoked_at   timestamptz,
  created_at   timestamptz not null default now()
);
create index participants_event_idx on participants (event_id) where revoked_at is null;

create table prospects (
  id                     uuid primary key default gen_random_uuid(),
  org_id                 uuid not null references organizations (id) on delete cascade,
  event_id               uuid not null references events (id) on delete cascade,
  first_name             text not null,
  last_name              text not null,
  email                  text not null,
  phone                  text not null,
  program_id             uuid references programs (id) on delete set null,
  education_level        text not null,
  status                 text not null default 'Curieux'
                         check (status in ('Curieux', 'Intéressé', 'Rdv d''info pris', 'Rdv d''admission pris')),
  notes                  text,
  -- Exactly one author kind: an admin account or an event participant.
  created_by_user        uuid references users (id) on delete set null,
  created_by_participant uuid references participants (id) on delete set null,
  -- Author's display name at creation, kept if the author is later removed.
  created_by_name        text not null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  -- Soft delete: non-null means archived.
  deleted_at             timestamptz
);
create index prospects_event_active_idx on prospects (event_id, created_at desc) where deleted_at is null;
create index prospects_org_archived_idx on prospects (org_id, deleted_at desc) where deleted_at is not null;

-- Rotating refresh tokens (only a SHA-256 is stored), for an admin OR a participant.
create table refresh_tokens (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references users (id) on delete cascade,
  participant_id uuid references participants (id) on delete cascade,
  token_hash     text not null unique,
  expires_at     timestamptz not null,
  revoked_at     timestamptz,
  created_at     timestamptz not null default now(),
  check ((user_id is null) <> (participant_id is null))
);
create index refresh_tokens_user_idx on refresh_tokens (user_id);
create index refresh_tokens_participant_idx on refresh_tokens (participant_id);

-- Failed sign-in / join attempts, for rate limiting (pruned as they age out).
create table auth_failures (
  key        text not null,
  created_at timestamptz not null default now()
);
create index auth_failures_key_idx on auth_failures (key, created_at);
