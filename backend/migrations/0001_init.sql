-- VoidMark Warpath analytics (Cloudflare D1).
-- No IP addresses, user agents, names, paths or game data are stored anywhere in this schema.

-- One row per anonymous Warpath installation (a random UUID made on the user's PC).
CREATE TABLE IF NOT EXISTS installs (
  install_id   TEXT PRIMARY KEY,
  first_seen   TEXT NOT NULL,   -- ISO day the server first heard from it
  last_seen    TEXT NOT NULL,
  app_version  TEXT
);

-- One row per installation + game + addon. first_kind: 'install' (installed through Warpath
-- after opt-in) or 'detected' (already there when the user opted in, or added by hand).
CREATE TABLE IF NOT EXISTS addon_installs (
  install_id   TEXT NOT NULL,
  game         TEXT NOT NULL,
  repo         TEXT NOT NULL,
  first_kind   TEXT NOT NULL,
  first_seen   TEXT NOT NULL,
  last_seen    TEXT NOT NULL,
  version      TEXT,
  pinned       INTEGER NOT NULL DEFAULT 0,
  last_init    TEXT,            -- in-game: addon last loaded (from SavedVariables), ISO time
  last_active  TEXT,            -- in-game: addon feature last actually used, ISO time
  PRIMARY KEY (install_id, game, repo)
);

-- Install / update / detected events. event_id is made by the client and reused on retries,
-- so a retried request can never be counted twice.
CREATE TABLE IF NOT EXISTS events (
  event_id     TEXT PRIMARY KEY,
  install_id   TEXT NOT NULL,
  type         TEXT NOT NULL,
  game         TEXT,
  repo         TEXT,
  version      TEXT,
  app_version  TEXT,
  day          TEXT NOT NULL,
  received_at  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS events_type_day ON events(type, day);
CREATE INDEX IF NOT EXISTS events_install ON events(install_id);

-- Daily activity. repo = '' and game = '' is the "Warpath ran" row; other rows mean
-- "Warpath ran and found this addon installed" (not proof of in-game use).
CREATE TABLE IF NOT EXISTS daily_activity (
  day          TEXT NOT NULL,
  install_id   TEXT NOT NULL,
  game         TEXT NOT NULL,
  repo         TEXT NOT NULL,
  version      TEXT,
  PRIMARY KEY (day, install_id, game, repo)
);
CREATE INDEX IF NOT EXISTS activity_install ON daily_activity(install_id);

-- Short-lived counters for per-installation rate limiting. Keys are installation ids or
-- keyed hashes; rows older than a day are purged.
CREATE TABLE IF NOT EXISTS rate_limits (
  bucket       TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count        INTEGER NOT NULL
);
