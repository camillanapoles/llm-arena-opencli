import type { Database } from "./database.ts";

/**
 * Schema for the arena driver's SQLite database.
 *
 * Tables:
 *  - functions: CRUD-managed FunctionSpec rows (kind resolved by the factory)
 *  - gates:     gate definitions (trigger + ordered function ids + policy)
 *  - runs:      one row per gate execution, steps stored as JSON
 *  - events:    gate events received from GitHub Actions triggers
 *  - cache:     persistent cache entries (write-through from ArenaCache)
 */

export const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS functions (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  kind          TEXT NOT NULL,
  params        TEXT NOT NULL DEFAULT '{}',
  cache_ttl_ms  INTEGER NOT NULL DEFAULT 0,
  enabled       INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS gates (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  policy        TEXT NOT NULL DEFAULT 'blocking',
  trigger       TEXT NOT NULL,
  functions     TEXT NOT NULL DEFAULT '[]',
  enabled       INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS events (
  id            TEXT PRIMARY KEY,
  type          TEXT NOT NULL,
  repo          TEXT NOT NULL,
  ref           TEXT,
  actor         TEXT,
  payload       TEXT NOT NULL DEFAULT '{}',
  received_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS runs (
  id            TEXT PRIMARY KEY,
  gate_id       TEXT NOT NULL,
  event_id      TEXT NOT NULL,
  status        TEXT NOT NULL,
  steps         TEXT NOT NULL DEFAULT '[]',
  started_at    TEXT NOT NULL,
  finished_at   TEXT
);

CREATE TABLE IF NOT EXISTS cache (
  key           TEXT PRIMARY KEY,
  value         TEXT NOT NULL,
  expires_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS pipeline_issues (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  instruction   TEXT NOT NULL,
  acceptance    TEXT NOT NULL,
  state         TEXT NOT NULL DEFAULT 'pending',
  attempts      INTEGER NOT NULL DEFAULT 0,
  next          TEXT,
  last_error    TEXT,
  updated_at    TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_runs_gate ON runs (gate_id, started_at);
CREATE INDEX IF NOT EXISTS idx_events_type ON events (type);
CREATE INDEX IF NOT EXISTS idx_cache_expires ON cache (expires_at);
`;

export function migrate(db: Database): void {
  db.exec(SCHEMA_SQL);
}
