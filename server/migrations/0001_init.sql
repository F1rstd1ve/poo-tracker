-- Gassi-Server (ADR 0006), Etappe B: shared Mülleimer.
-- Times are Unix seconds (UTC). Kinds: 1 = Mülleimer, 2 = Hundekot-Behälter.

-- Shared bins. A row exists while the bin is visible for everyone; a bin hidden
-- by 2 reports is deleted. root = "<ri>_<rj>" of the 0.4 degree root grid (t1).
CREATE TABLE bins (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  lat          REAL    NOT NULL,
  lon          REAL    NOT NULL,
  kind         INTEGER NOT NULL CHECK (kind IN (1, 2)),
  confirmed    INTEGER NOT NULL DEFAULT 0,
  uid          TEXT    NOT NULL,
  imprecise    INTEGER NOT NULL DEFAULT 0,
  created      INTEGER NOT NULL,
  confirmed_at INTEGER,
  root         TEXT    NOT NULL
);
CREATE INDEX bins_root ON bins (root);
-- Neighbourhood search (same bin = same kind within 8 m).
CREATE INDEX bins_kind_lat ON bins (kind, lat, lon);
-- Daily cleanup of old unconfirmed bins.
CREATE INDEX bins_unconfirmed ON bins (confirmed, created);

-- Reports ("Hier ist kein Mülleimer"). target = "s:<id>" for a shared bin or
-- "o:<kind>:<lat5>:<lon5>" for an OSM bin (coordinates in 1e-5 degrees).
CREATE TABLE reports (
  target  TEXT    NOT NULL,
  uid     TEXT    NOT NULL,
  created INTEGER NOT NULL,
  PRIMARY KEY (target, uid)
) WITHOUT ROWID;
CREATE INDEX reports_created ON reports (created);

-- OSM bins hidden for everyone after reports from 2 different uids.
CREATE TABLE hidden_osm (
  kind    INTEGER NOT NULL,
  lat5    INTEGER NOT NULL,
  lon5    INTEGER NOT NULL,
  root    TEXT    NOT NULL,
  created INTEGER NOT NULL,
  PRIMARY KEY (kind, lat5, lon5)
) WITHOUT ROWID;
CREATE INDEX hidden_osm_root ON hidden_osm (root);

-- Daily limits. day = "YYYY-MM-DD" (UTC); key = "u:<uid>" or "ip:<hash>"
-- (SHA-256 of the IP address with a daily salt, never the raw address).
-- anchor_* = first add of the day (50 km rule, uid keys only).
CREATE TABLE counters (
  day        TEXT    NOT NULL,
  key        TEXT    NOT NULL,
  n_add      INTEGER NOT NULL DEFAULT 0,
  n_other    INTEGER NOT NULL DEFAULT 0,
  anchor_lat REAL,
  anchor_lon REAL,
  PRIMARY KEY (day, key)
) WITHOUT ROWID;
