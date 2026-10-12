/**
 * Generic CRUD repository over SQLite.
 *
 * Every domain entity (functions, gates, runs, events) gets a thin subclass
 * that supplies the table name, column mapping and row hydration. All writes
 * go through parameterized statements (no string interpolation of values).
 */

import type { Database } from "../db/database.ts";

export interface Entity {
  id: string;
}

export class CrudRepository<T extends Entity> {
  protected readonly db: Database;
  protected readonly table: string;
  private readonly columns: string[];
  private readonly hydrate: (row: Record<string, unknown>) => T;
  private readonly serialize: (entity: T) => Record<string, string | number>;

  constructor(options: {
    db: Database;
    table: string;
    columns: string[];
    hydrate: (row: Record<string, unknown>) => T;
    serialize: (entity: T) => Record<string, string | number>;
  }) {
    this.db = options.db;
    this.table = options.table;
    this.columns = options.columns;
    this.hydrate = options.hydrate;
    this.serialize = options.serialize;
  }

  create(entity: T): T {
    const record = this.serialize(entity);
    const columns = this.columns.join(", ");
    const placeholders = this.columns.map(() => "?").join(", ");
    const values = this.columns.map((col) => record[col] ?? "");
    this.db.run(`INSERT INTO ${this.table} (${columns}) VALUES (${placeholders})`, ...values);
    return entity;
  }

  get(id: string): T | undefined {
    const row = this.db.get<Record<string, unknown>>(`SELECT * FROM ${this.table} WHERE id = ?`, id);
    return row === undefined ? undefined : this.hydrate(row);
  }

  list(): T[] {
    return this.db
      .query<Record<string, unknown>>(`SELECT * FROM ${this.table} ORDER BY id`)
      .map((row) => this.hydrate(row));
  }

  update(id: string, patch: Record<string, unknown>): T | undefined {
    const existing = this.get(id);
    if (existing === undefined) return undefined;
    const merged = { ...existing, ...patch, id } as T;
    const record = this.serialize(merged);
    const assignments = this.columns
      .filter((col) => col !== "id")
      .map((col) => `${col} = ?`)
      .join(", ");
    const values = this.columns
      .filter((col) => col !== "id")
      .map((col) => record[col] ?? "");
    this.db.run(`UPDATE ${this.table} SET ${assignments} WHERE id = ?`, ...values, id);
    return merged;
  }

  remove(id: string): boolean {
    const result = this.db.run(`DELETE FROM ${this.table} WHERE id = ?`, id);
    return result.changes > 0;
  }

  count(): number {
    const row = this.db.get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${this.table}`);
    return row?.n ?? 0;
  }
}
