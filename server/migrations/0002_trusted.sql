-- Trusted Kennungen (ADR 0006): bins added by these are confirmed at once.
-- Filled by hand (wrangler d1 execute), never from the API.
CREATE TABLE IF NOT EXISTS trusted (
  uid TEXT PRIMARY KEY,
  note TEXT,
  created INTEGER NOT NULL
);
