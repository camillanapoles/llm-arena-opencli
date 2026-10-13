/**
 * SQLite persistence layer built on Node's built-in `node:sqlite`.
 *
 * Zero native dependencies: `node:sqlite` ships with Node >= 22.5. All
 * payloads that are not scalars are stored as JSON text and parsed on read.
 */

import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

export type SqlValue = string | number | bigint | null | Uint8Array;

export interface Queryable {
  query<T>(sql: string, ...params: SqlValue[]): T[];
  get<T>(sql: string, ...params: SqlValue[]): T | undefined;
  run(sql: string, ...params: SqlValue[]): { changes: number; lastInsertRowid: number };
}

export class Database implements Queryable {
  readonly handle: DatabaseSync;
  readonly path: string;

  constructor(path = process.env["ARENA_DB_PATH"] ?? "data/arena.db") {
    this.path = path;
    if (path !== ":memory:") {
      mkdirSync(dirname(path), { recursive: true });
    }
    this.handle = new DatabaseSync(path);
    this.handle.exec("PRAGMA journal_mode = WAL;");
    this.handle.exec("PRAGMA foreign_keys = ON;");
  }

  exec(sql: string): void {
    this.handle.exec(sql);
  }

  query<T>(sql: string, ...params: SqlValue[]): T[] {
    const rows = this.handle.prepare(sql).all(...params) as Record<string, unknown>[];
    // node:sqlite returns null-prototype rows; copy to plain objects so
    // consumers (and deepEqual tests) see ordinary JSON-friendly values.
    return rows.map((row) => ({ ...row })) as T[];
  }

  get<T>(sql: string, ...params: SqlValue[]): T | undefined {
    const row = this.handle.prepare(sql).get(...params) as Record<string, unknown> | undefined;
    return row === undefined ? undefined : ({ ...row } as T);
  }

  run(sql: string, ...params: SqlValue[]): { changes: number; lastInsertRowid: number } {
    const result = this.handle.prepare(sql).run(...params);
    return {
      changes: Number(result.changes),
      lastInsertRowid: Number(result.lastInsertRowid),
    };
  }

  /** Run `fn` inside a transaction, rolling back on throw. */
  transaction<T>(fn: (db: Queryable) => T): T {
    this.handle.exec("BEGIN");
    try {
      const result = fn(this);
      this.handle.exec("COMMIT");
      return result;
    } catch (err) {
      this.handle.exec("ROLLBACK");
      throw err;
    }
  }

  close(): void {
    this.handle.close();
  }
}

/** JSON helpers so repos can store structured params/outputs as TEXT. */
export function toJson(value: unknown): string {
  return JSON.stringify(value ?? null);
}

export function fromJson<T>(text: string | null | undefined, fallback: T): T {
  if (text == null || text === "") return fallback;
  try {
    return JSON.parse(text) as T;
  } catch {
    return fallback;
  }
}
