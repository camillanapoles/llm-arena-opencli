/**
 * TTL + LRU cache with optional SQLite write-through persistence.
 *
 * Best practice for the Actions runtime: cheap in-process lookups with the
 * durability of SQLite so state survives across jobs/steps of a workflow.
 */

import type { Database } from "../db/database.ts";
import { fromJson, toJson } from "../db/database.ts";

interface CacheEntry {
  value: unknown;
  expiresAt: number;
}

export interface CachePersistence {
  get(key: string): CacheEntry | undefined;
  set(key: string, entry: CacheEntry): void;
  delete(key: string): void;
}

export interface CacheStats {
  hits: number;
  misses: number;
  entries: number;
  evictions: number;
}

export interface CacheOptions {
  maxEntries?: number;
  defaultTtlMs?: number;
  persistence?: CachePersistence;
  now?: () => number;
}

export class ArenaCache {
  private readonly store = new Map<string, CacheEntry>();
  private readonly maxEntries: number;
  private readonly defaultTtlMs: number;
  private readonly persistence: CachePersistence | undefined;
  private readonly now: () => number;
  private hits = 0;
  private misses = 0;
  private evictions = 0;

  constructor(options: CacheOptions = {}) {
    this.maxEntries = options.maxEntries ?? 1024;
    this.defaultTtlMs = options.defaultTtlMs ?? 60_000;
    this.persistence = options.persistence;
    this.now = options.now ?? Date.now;
  }

  get(key: string): unknown | undefined {
    const entry = this.lookup(key);
    if (entry === undefined) {
      this.misses += 1;
      return undefined;
    }
    this.hits += 1;
    // LRU: re-insert to mark as most recently used.
    this.store.delete(key);
    this.store.set(key, entry);
    return entry.value;
  }

  set(key: string, value: unknown, ttlMs?: number): void {
    const ttl = ttlMs ?? this.defaultTtlMs;
    const entry: CacheEntry = { value, expiresAt: ttl > 0 ? this.now() + ttl : Number.MAX_SAFE_INTEGER };
    this.store.delete(key);
    this.store.set(key, entry);
    this.persistence?.set(key, entry);
    this.evict();
  }

  delete(key: string): void {
    this.store.delete(key);
    this.persistence?.delete(key);
  }

  clear(): void {
    for (const key of [...this.store.keys()]) {
      this.delete(key);
    }
  }

  stats(): CacheStats {
    return {
      hits: this.hits,
      misses: this.misses,
      entries: this.store.size,
      evictions: this.evictions,
    };
  }

  private lookup(key: string): CacheEntry | undefined {
    const local = this.store.get(key);
    if (local !== undefined) {
      if (local.expiresAt <= this.now()) {
        this.delete(key);
        return undefined;
      }
      return local;
    }
    const persisted = this.persistence?.get(key);
    if (persisted === undefined) return undefined;
    if (persisted.expiresAt <= this.now()) {
      this.persistence?.delete(key);
      return undefined;
    }
    this.store.set(key, persisted);
    return persisted;
  }

  private evict(): void {
    while (this.store.size > this.maxEntries) {
      const oldest = this.store.keys().next();
      if (oldest.done === true) break;
      this.delete(oldest.value);
      this.evictions += 1;
    }
  }
}

/** Write-through persistence backed by the `cache` table. */
export class SqliteCachePersistence implements CachePersistence {
  private readonly db: Database;

  constructor(db: Database) {
    this.db = db;
  }

  get(key: string): CacheEntry | undefined {
    const row = this.db.get<{ value: string; expires_at: number }>(
      "SELECT value, expires_at FROM cache WHERE key = ?",
      key,
    );
    if (row === undefined) return undefined;
    return { value: fromJson<unknown>(row.value, null), expiresAt: row.expires_at };
  }

  set(key: string, entry: CacheEntry): void {
    this.db.run(
      `INSERT INTO cache (key, value, expires_at, updated_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value,
                                      expires_at = excluded.expires_at,
                                      updated_at = excluded.updated_at`,
      key,
      toJson(entry.value),
      entry.expiresAt,
      Date.now(),
    );
  }

  delete(key: string): void {
    this.db.run("DELETE FROM cache WHERE key = ?", key);
  }
}
